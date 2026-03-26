// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

// Banner shown at top of terminal when last command exits non-zero.
// Triggered by Ctrl+Shift+F or the "AI Fix" button.
// Streams AI analysis inline; "Apply" copies the suggested fix command.

import { Markdown } from "@/app/element/markdown";
import { ClientModel } from "@/app/store/client-model";
import { globalStore } from "@/app/store/jotaiStore";
import { RpcApi } from "@/app/store/wshclientapi";
import { makeFeBlockRouteId } from "@/app/store/wshrouter";
import { TabRpcClient } from "@/app/store/wshrpcutil";
import { atoms, getSettingsKeyAtom } from "@/store/global";
import { fireAndForget } from "@/util/util";
import * as jotai from "jotai";
import * as React from "react";
import type { TermViewModel } from "./term-model";

interface AiErrorBannerProps {
    blockId: string;
    model: TermViewModel;
}

interface AiResponseState {
    text: string;
    isStreaming: boolean;
    error: string | null;
}

// Extract first fenced code block from markdown AI response
function extractFirstCodeBlock(text: string): string | null {
    const match = text.match(/```(?:\w+)?\n([\s\S]*?)```/);
    return match ? match[1].trim() : null;
}

// Build AI opts from global settings (same pattern as WaveAiModel.aiOpts)
function getGlobalAiOpts(): WaveAIOptsType {
    const settings = globalStore.get(atoms.settingsAtom) ?? {};
    return {
        model: settings["ai:model"] ?? null,
        apitype: settings["ai:apitype"] ?? null,
        orgid: settings["ai:orgid"] ?? null,
        apitoken: settings["ai:apitoken"] ?? null,
        apiversion: settings["ai:apiversion"] ?? null,
        maxtokens: settings["ai:maxtokens"] ?? null,
        timeoutms: settings["ai:timeoutms"] ?? 60000,
        baseurl: settings["ai:baseurl"] ?? null,
        proxyurl: settings["ai:proxyurl"] ?? null,
    };
}

// Stable fallback atoms so hooks are never called conditionally
const nullAtom = jotai.atom<null>(null);
const nullStringAtom = jotai.atom<string | null>(null);

export const AiErrorBanner = ({ blockId, model }: AiErrorBannerProps) => {
    const aiEnabledAtom = React.useMemo(() => getSettingsKeyAtom("term:aierroranalysis"), []);
    const aiEnabled = jotai.useAtomValue(aiEnabledAtom);

    // cmd-mode: exit code via shellProcFullStatus
    const shellProcFullStatus = jotai.useAtomValue(model.shellProcFullStatus);

    // shell-integration: exit code via termWrap atoms (stable refs via useMemo)
    const termWrap = model.termRef.current;
    const siExitCodeAtom = termWrap?.lastCmdExitCodeAtom ?? nullAtom;
    const siStatusAtom = termWrap?.shellIntegrationStatusAtom ?? nullAtom;
    const lastCommandAtom = termWrap?.lastCommandAtom ?? nullStringAtom;

    const siExitCode = jotai.useAtomValue(siExitCodeAtom as jotai.Atom<number | null>);
    const siStatus = jotai.useAtomValue(siStatusAtom as jotai.Atom<string | null>);
    const lastCommand = jotai.useAtomValue(lastCommandAtom);
    const aiFixRequested = jotai.useAtomValue(model.aiFixRequestedAtom);

    const [dismissed, setDismissed] = React.useState(false);
    const [response, setResponse] = React.useState<AiResponseState>({ text: "", isStreaming: false, error: null });
    const cancelRef = React.useRef(false);

    // Determine active exit code + command from whichever source is live
    const { exitCode, command } = React.useMemo(() => {
        // cmd-mode block
        const isCmdDone = shellProcFullStatus?.shellprocstatus === "done";
        const cmdExitCode = isCmdDone ? (shellProcFullStatus?.shellprocexitcode ?? 0) : 0;

        // For cmd-mode, read command from block meta
        const blockMeta = globalStore.get(model.blockAtom)?.meta;
        let cmdCommand: string | null = null;
        if (blockMeta?.controller === "cmd" && blockMeta?.cmd) {
            const args = blockMeta?.["cmd:args"];
            cmdCommand = blockMeta.cmd + (args?.length ? " " + args.join(" ") : "");
        }

        // shell-integration: ready + non-zero exit from "D" handler
        const siActive = siStatus === "ready" && siExitCode != null && siExitCode !== 0;
        const siCmd = lastCommand;

        if (siActive) {
            return { exitCode: siExitCode, command: siCmd };
        }
        if (isCmdDone && cmdExitCode !== 0) {
            return { exitCode: cmdExitCode, command: cmdCommand };
        }
        return { exitCode: 0, command: null };
    }, [shellProcFullStatus, siStatus, siExitCode, lastCommand]);

    // Dismiss when a new command starts
    React.useEffect(() => {
        if (siStatus === "running-command") {
            setDismissed(true);
            setResponse({ text: "", isStreaming: false, error: null });
            cancelRef.current = true;
        }
    }, [siStatus]);

    // Dismiss when cmd-mode restarts (shellprocstatus transitions to "running")
    React.useEffect(() => {
        if (shellProcFullStatus?.shellprocstatus === "running") {
            setDismissed(true);
            setResponse({ text: "", isStreaming: false, error: null });
            cancelRef.current = true;
        }
    }, [shellProcFullStatus?.shellprocstatus]);

    // Re-show banner when a new error occurs
    React.useEffect(() => {
        if (exitCode !== 0) {
            setDismissed(false);
            setResponse({ text: "", isStreaming: false, error: null });
            cancelRef.current = false;
        }
    }, [exitCode, command]);

    // Handle aiFixRequestedAtom toggle from Ctrl+Shift+F
    React.useEffect(() => {
        if (aiFixRequested && exitCode !== 0 && !response.isStreaming) {
            globalStore.set(model.aiFixRequestedAtom, false);
            fireAndForget(() => triggerAiFix());
        }
    }, [aiFixRequested]);

    const triggerAiFix = React.useCallback(async () => {
        if (response.isStreaming) return;
        cancelRef.current = false;
        setResponse({ text: "", isStreaming: true, error: null });

        try {
            // Fetch recent terminal output
            let scrollbackContent = "";
            try {
                const route = makeFeBlockRouteId(blockId);
                const hasSI = globalStore.get(termWrap?.shellIntegrationStatusAtom ?? jotai.atom(null)) != null;
                const scrollbackData = await RpcApi.TermGetScrollbackLinesCommand(
                    TabRpcClient,
                    { linestart: 0, lineend: 50, lastcommand: hasSI },
                    { route }
                );
                scrollbackContent = scrollbackData.lines.join("\n");
            } catch (e) {
                scrollbackContent = "(could not retrieve terminal output)";
            }

            const cmdStr = command ?? "(unknown command)";
            const prompt = `A command failed with exit code ${exitCode}.

Command: \`${cmdStr}\`

Output (last 50 lines):
\`\`\`
${scrollbackContent}
\`\`\`

Briefly explain what went wrong and provide the corrected command or fix in a fenced code block.`;

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
                if (cancelRef.current) break;
                fullText += msg.text ?? "";
                setResponse({ text: fullText, isStreaming: true, error: null });
            }
            setResponse({ text: fullText, isStreaming: false, error: null });
        } catch (e) {
            setResponse({ text: "", isStreaming: false, error: (e as Error).message ?? "AI request failed" });
        }
    }, [blockId, exitCode, command, response.isStreaming, termWrap]);

    // Skip render if disabled or no error or dismissed
    if (aiEnabled === false) return null;
    if (exitCode === 0 || dismissed) return null;

    const hasResponse = response.text.length > 0 || response.error != null;
    const fixCommand = response.text ? extractFirstCodeBlock(response.text) : null;

    return (
        <div className="term-ai-error-banner">
            <div className="term-ai-error-banner-header">
                <span className="term-ai-error-dot" />
                <span className="term-ai-error-label">
                    Command failed (exit {exitCode})
                </span>
                {!response.isStreaming && !hasResponse && (
                    <button
                        className="term-ai-error-btn"
                        onClick={() => fireAndForget(() => triggerAiFix())}
                        title="Analyze error with AI (Ctrl+Shift+F)"
                    >
                        AI Fix
                    </button>
                )}
                {response.isStreaming && (
                    <span className="term-ai-error-streaming">analyzing...</span>
                )}
                <button
                    className="term-ai-error-dismiss"
                    onClick={() => {
                        cancelRef.current = true;
                        setDismissed(true);
                    }}
                    title="Dismiss"
                >
                    ✕
                </button>
            </div>
            {hasResponse && (
                <div className="term-ai-error-response">
                    {response.error ? (
                        <span className="term-ai-error-err">{response.error}</span>
                    ) : (
                        <>
                            <Markdown text={response.text} />
                            {fixCommand && (
                                <button
                                    className="term-ai-error-apply"
                                    onClick={() => {
                                        navigator.clipboard.writeText(fixCommand).catch(console.error);
                                    }}
                                    title="Copy fix command to clipboard"
                                >
                                    Copy Fix
                                </button>
                            )}
                        </>
                    )}
                </div>
            )}
        </div>
    );
};
