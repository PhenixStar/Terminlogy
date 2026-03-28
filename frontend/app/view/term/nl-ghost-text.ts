// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

// NL-to-command ghost text overlay.
// Watches terminal shell input buffer for "# " or "?? " prefix,
// debounces 300ms, queries AI, renders a positioned DOM overlay.
// Tab accepts (replaces NL query with command), Escape dismisses.

import { ClientModel } from "@/app/store/client-model";
import { globalStore } from "@/app/store/jotaiStore";
import { RpcApi } from "@/app/store/wshclientapi";
import { TabRpcClient } from "@/app/store/wshrpcutil";
import { atoms, getSettingsKeyAtom } from "@/store/global";
import { PLATFORM } from "@/util/platformutil";
import type * as jotai from "jotai";
import type { TermWrap } from "./termwrap";

const NL_PREFIX_HASH = "# ";
const NL_PREFIX_QQ = "?? ";
const DEBOUNCE_MS = 300;

// Build AI opts from global settings (same pattern as ai-error-banner.tsx)
function getGlobalAiOpts(): WaveAIOptsType {
    const settings = globalStore.get(atoms.settingsAtom) ?? {};
    return {
        model: settings["ai:model"] ?? "",
        apitype: settings["ai:apitype"] ?? null,
        orgid: settings["ai:orgid"] ?? null,
        apitoken: settings["ai:apitoken"] ?? "",
        apiversion: settings["ai:apiversion"] ?? null,
        maxtokens: settings["ai:maxtokens"] ?? null,
        timeoutms: settings["ai:timeoutms"] ?? 60000,
        baseurl: settings["ai:baseurl"] ?? null,
        proxyurl: settings["ai:proxyurl"] ?? null,
    };
}

function extractNlQuery(inputBuffer: string | null): string | null {
    if (!inputBuffer) return null;
    if (inputBuffer.startsWith(NL_PREFIX_HASH)) {
        return inputBuffer.slice(NL_PREFIX_HASH.length).trim();
    }
    if (inputBuffer.startsWith(NL_PREFIX_QQ)) {
        return inputBuffer.slice(NL_PREFIX_QQ.length).trim();
    }
    return null;
}

// Resolve OS name for prompt context
function getOsName(): string {
    switch (PLATFORM) {
        case "darwin":
            return "macOS";
        case "win32":
            return "Windows";
        default:
            return "Linux";
    }
}

export type GhostTextState = {
    visible: boolean;
    command: string;
    loading: boolean;
    query: string;
};

export type GhostTextAcceptCallback = (command: string, fullInputBuffer: string) => void;

/**
 * NlGhostText manages the AI NL-to-command ghost text feature for a single terminal block.
 * It watches the shellInputBufferAtom on TermWrap, debounces, calls AI, and exposes
 * state for the React overlay to render.
 */
export class NlGhostText {
    private termWrap: TermWrap | null = null;
    private debounceTimer: ReturnType<typeof setTimeout> | null = null;
    private abortController: AbortController | null = null;
    private lastQuery: string = "";
    private unsubscribe: (() => void) | null = null;

    stateAtom: jotai.PrimitiveAtom<GhostTextState>;

    constructor(stateAtom: jotai.PrimitiveAtom<GhostTextState>) {
        this.stateAtom = stateAtom;
    }

    attach(termWrap: TermWrap) {
        this.detach();
        this.termWrap = termWrap;

        // Subscribe to shell input buffer changes
        this.unsubscribe = globalStore.sub(termWrap.shellInputBufferAtom, () => {
            this.onInputBufferChange();
        });
    }

    detach() {
        this.unsubscribe?.();
        this.unsubscribe = null;
        this.clearDebounce();
        this.cancelAi();
        this.hide();
        this.termWrap = null;
    }

    private hide() {
        this.lastQuery = "";
        globalStore.set(this.stateAtom, { visible: false, command: "", loading: false, query: "" });
    }

    private clearDebounce() {
        if (this.debounceTimer != null) {
            clearTimeout(this.debounceTimer);
            this.debounceTimer = null;
        }
    }

    private cancelAi() {
        if (this.abortController) {
            this.abortController.abort();
            this.abortController = null;
        }
    }

    private onInputBufferChange() {
        if (!this.termWrap) return;
        // Respect the term:nlcommand setting (default: true)
        const enabled = globalStore.get(getSettingsKeyAtom("term:nlcommand")) ?? true;
        if (!enabled) {
            this.clearDebounce();
            this.cancelAi();
            this.hide();
            return;
        }
        const inputBuffer = globalStore.get(this.termWrap.shellInputBufferAtom);
        const query = extractNlQuery(inputBuffer);

        if (!query) {
            this.clearDebounce();
            this.cancelAi();
            this.hide();
            return;
        }

        // Already showing result for same query — no-op
        const cur = globalStore.get(this.stateAtom);
        if (cur.command && query === this.lastQuery) return;

        this.clearDebounce();
        this.cancelAi();

        // Show loading state immediately after debounce
        this.debounceTimer = setTimeout(() => {
            this.debounceTimer = null;
            this.fetchCommand(query);
        }, DEBOUNCE_MS);
    }

    private async fetchCommand(query: string) {
        if (!query) return;
        this.lastQuery = query;
        this.cancelAi();

        globalStore.set(this.stateAtom, { visible: true, command: "", loading: true, query });

        const ctrl = new AbortController();
        this.abortController = ctrl;

        try {
            const os = getOsName();
            const prompt = `Convert this natural language to a shell command for ${os}. Output ONLY the command, no explanation, no markdown, no code fences: ${query}`;
            const clientId = ClientModel.getInstance().clientId;
            const opts = getGlobalAiOpts();
            const beMsg: WaveAIStreamRequest = {
                clientid: clientId,
                opts,
                prompt: [{ role: "user", content: prompt }],
            };

            const aiGen = RpcApi.StreamWaveAiCommand(TabRpcClient, beMsg, { timeout: opts.timeoutms });
            let fullText = "";
            for await (const msg of aiGen) {
                if (ctrl.signal.aborted) return;
                fullText += msg.text ?? "";
            }

            if (ctrl.signal.aborted) return;

            // Clean up any accidental markdown code fences
            const cleaned = fullText
                .replace(/```[a-z]*\n?/gi, "")
                .replace(/```/g, "")
                .trim();

            globalStore.set(this.stateAtom, { visible: true, command: cleaned, loading: false, query });
        } catch (e) {
            if (ctrl.signal.aborted) return;
            console.warn("[NlGhostText] AI fetch failed:", e);
            globalStore.set(this.stateAtom, { visible: false, command: "", loading: false, query });
        }
    }

    /**
     * Called by the keydown handler when Tab is pressed.
     * Returns true if ghost text was accepted (caller should preventDefault).
     */
    accept(onAccept: GhostTextAcceptCallback): boolean {
        const state = globalStore.get(this.stateAtom);
        if (!state.visible || !state.command) return false;
        if (!this.termWrap) return false;

        const inputBuffer = globalStore.get(this.termWrap.shellInputBufferAtom) ?? "";
        this.clearDebounce();
        this.cancelAi();
        this.hide();
        onAccept(state.command, inputBuffer);
        return true;
    }

    /**
     * Called when Escape is pressed to dismiss ghost text.
     * Returns true if ghost text was visible (caller should handle accordingly).
     */
    dismiss(): boolean {
        const state = globalStore.get(this.stateAtom);
        if (!state.visible) return false;
        this.clearDebounce();
        this.cancelAi();
        this.hide();
        return true;
    }
}
