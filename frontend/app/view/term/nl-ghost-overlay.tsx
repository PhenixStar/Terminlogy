// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

// Ghost text overlay for NL-to-command feature.
// Renders a slim banner below the terminal input showing the AI-suggested command.
// Tab accepts, Escape dismisses.

import * as jotai from "jotai";
import * as React from "react";
import type { GhostTextState } from "./nl-ghost-text";

interface NlGhostOverlayProps {
    stateAtom: jotai.PrimitiveAtom<GhostTextState>;
}

export const NlGhostOverlay = React.memo(({ stateAtom }: NlGhostOverlayProps) => {
    const state = jotai.useAtomValue(stateAtom);

    if (!state.visible) return null;

    return (
        <div className="nl-ghost-overlay" aria-label="AI command suggestion" role="status" aria-live="polite">
            <span className="nl-ghost-icon">AI</span>
            {state.loading ? (
                <span className="nl-ghost-loading">thinking...</span>
            ) : (
                <>
                    <span className="nl-ghost-command">{state.command}</span>
                    <span className="nl-ghost-hint">Tab to accept · Esc to dismiss</span>
                </>
            )}
        </div>
    );
});

NlGhostOverlay.displayName = "NlGhostOverlay";
