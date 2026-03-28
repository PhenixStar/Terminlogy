// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

// Package mcp implements a Model Context Protocol (MCP) server for Terminolgy.
// It exposes terminal state as JSON-RPC 2.0 tools that external AI agents can consume.
// Spec target: MCP 2024-11-05 (stable).
//
// Phase 1 — read-only tools:
//   - terminolgy.list_blocks   — list blocks in the active tab
//   - terminolgy.get_sysinfo   — return system metrics
//
// Wire the HTTP handler via web.go:
//   gr.HandleFunc("/mcp", mcp.MCPHandler)
package mcp

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"

	"github.com/wavetermdev/waveterm/pkg/wavebase"
	"github.com/wavetermdev/waveterm/pkg/waveobj"
	"github.com/wavetermdev/waveterm/pkg/wstore"
)

// ---------- JSON-RPC 2.0 types ----------

type rpcRequest struct {
	Jsonrpc string          `json:"jsonrpc"`
	ID      interface{}     `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type rpcResponse struct {
	Jsonrpc string      `json:"jsonrpc"`
	ID      interface{} `json:"id"`
	Result  interface{} `json:"result,omitempty"`
	Error   *rpcError   `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// ---------- MCP protocol types ----------

type toolDef struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	InputSchema interface{} `json:"inputSchema"`
}

type toolsListResult struct {
	Tools []toolDef `json:"tools"`
}

type toolCallParams struct {
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments,omitempty"`
}

type toolCallResult struct {
	Content []toolContent `json:"content"`
	IsError bool          `json:"isError,omitempty"`
}

type toolContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

// ---------- Tool registry ----------

type toolHandlerFn func(ctx context.Context, args json.RawMessage) (*toolCallResult, error)

var toolRegistry = map[string]toolHandlerFn{
	"terminolgy.list_blocks": handleListBlocks,
	"terminolgy.get_sysinfo": handleGetSysinfo,
}

var registeredTools = []toolDef{
	{
		Name:        "terminolgy.list_blocks",
		Description: "List all open blocks in the active tab, including their view type and display name.",
		InputSchema: map[string]interface{}{
			"type":       "object",
			"properties": map[string]interface{}{},
		},
	},
	{
		Name:        "terminolgy.get_sysinfo",
		Description: "Get system metrics: OS, CPU, memory, and runtime environment.",
		InputSchema: map[string]interface{}{
			"type": "object",
			"properties": map[string]interface{}{
				"block_id": map[string]interface{}{
					"type":        "string",
					"description": "Optional block ID — reserved for future sysinfo block routing.",
				},
			},
		},
	},
}

// ---------- Tool handlers ----------

type blockInfo struct {
	BlockId     string `json:"block_id"`
	View        string `json:"view"`
	DisplayName string `json:"display_name,omitempty"`
	Connection  string `json:"connection,omitempty"`
}

func handleListBlocks(ctx context.Context, _ json.RawMessage) (*toolCallResult, error) {
	workspaces, err := wstore.DBGetAllObjsByType[*waveobj.Workspace](ctx, waveobj.OType_Workspace)
	if err != nil {
		return nil, fmt.Errorf("failed to list workspaces: %w", err)
	}

	var blocks []blockInfo
	for _, ws := range workspaces {
		if ws.ActiveTabId == "" {
			continue
		}
		tab, err := wstore.DBMustGet[*waveobj.Tab](ctx, ws.ActiveTabId)
		if err != nil {
			log.Printf("[mcp] list_blocks: failed to get tab %s: %v", ws.ActiveTabId, err)
			continue
		}
		for _, blockId := range tab.BlockIds {
			block, err := wstore.DBGet[*waveobj.Block](ctx, blockId)
			if err != nil || block == nil {
				continue
			}
			info := blockInfo{
				BlockId:     blockId,
				View:        block.Meta.GetString(waveobj.MetaKey_View, ""),
				DisplayName: block.Meta.GetString("display:name", ""),
				Connection:  block.Meta.GetString(waveobj.MetaKey_Connection, ""),
			}
			blocks = append(blocks, info)
		}
		// only the first workspace's active tab for Phase 1
		break
	}

	out, err := json.MarshalIndent(blocks, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("failed to marshal blocks: %w", err)
	}
	return &toolCallResult{
		Content: []toolContent{{Type: "text", Text: string(out)}},
	}, nil
}

func handleGetSysinfo(_ context.Context, _ json.RawMessage) (*toolCallResult, error) {
	summary := wavebase.GetSystemSummary()
	return &toolCallResult{
		Content: []toolContent{{Type: "text", Text: summary}},
	}, nil
}

// ---------- HTTP handler ----------

// MCPHandler handles JSON-RPC 2.0 requests at /mcp.
// Supports: tools/list, tools/call.
func MCPHandler(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20)) // 1 MB max
	if err != nil {
		writeJSONError(w, nil, -32700, "failed to read request body")
		return
	}

	var req rpcRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeJSONError(w, nil, -32700, "parse error")
		return
	}
	if req.Jsonrpc != "2.0" {
		writeJSONError(w, req.ID, -32600, "invalid request: jsonrpc must be \"2.0\"")
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()

	switch req.Method {
	case "tools/list":
		writeJSON(w, req.ID, toolsListResult{Tools: registeredTools})

	case "tools/call":
		var params toolCallParams
		if err := json.Unmarshal(req.Params, &params); err != nil {
			writeJSONError(w, req.ID, -32602, "invalid params")
			return
		}
		handler, ok := toolRegistry[params.Name]
		if !ok {
			writeJSONError(w, req.ID, -32601, fmt.Sprintf("unknown tool: %s", params.Name))
			return
		}
		result, toolErr := handler(ctx, params.Arguments)
		if toolErr != nil {
			result = &toolCallResult{
				Content: []toolContent{{Type: "text", Text: toolErr.Error()}},
				IsError: true,
			}
		}
		writeJSON(w, req.ID, result)

	default:
		writeJSONError(w, req.ID, -32601, fmt.Sprintf("method not found: %s", req.Method))
	}
}

func writeJSON(w http.ResponseWriter, id interface{}, result interface{}) {
	resp := rpcResponse{
		Jsonrpc: "2.0",
		ID:      id,
		Result:  result,
	}
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Printf("[mcp] writeJSON encode error: %v", err)
	}
}

func writeJSONError(w http.ResponseWriter, id interface{}, code int, msg string) {
	resp := rpcResponse{
		Jsonrpc: "2.0",
		ID:      id,
		Error:   &rpcError{Code: code, Message: msg},
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK) // JSON-RPC errors use 200 OK
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		log.Printf("[mcp] writeJSONError encode error: %v", err)
	}
}
