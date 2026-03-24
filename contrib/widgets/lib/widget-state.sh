#!/usr/bin/env bash
# widget-state.sh — Shared state persistence library for WaveTerm widgets
# Source this file in any widget script to get save/load state functions.
# Uses wsh setvar/getvar with graceful fallback when wsh is unavailable.

# Save a named state value.
# Usage: widget_save_state <key> <value>
widget_save_state() {
    local key="$1"
    local value="$2"
    wsh setvar "widget:state:${key}" "${value}" 2>/dev/null || true
}

# Load a named state value. Prints empty string if not found or wsh unavailable.
# Usage: result=$(widget_load_state <key>)
widget_load_state() {
    local key="$1"
    wsh getvar "widget:state:${key}" 2>/dev/null || echo ""
}
