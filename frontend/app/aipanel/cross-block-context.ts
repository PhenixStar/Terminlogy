// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

import { globalStore } from "@/app/store/jotaiStore";
import * as WOS from "@/app/store/wos";
import { RpcApi } from "@/app/store/wshclientapi";
import { TabRpcClient } from "@/app/store/wshrpcutil";
import { makeFeBlockRouteId } from "@/app/store/wshrouter";
import { getLayoutModelForStaticTab } from "@/layout/index";

const MAX_LINES_PER_BLOCK = 20;
const MAX_BLOCKS = 8;

/**
 * Gathers scrollback output from all visible term blocks in the current tab.
 * Returns a formatted context string to prepend to AI queries, or "" if nothing found.
 */
export async function gatherVisibleBlockContext(tabId: string): Promise<string> {
    const layoutModel = getLayoutModelForStaticTab();
    if (!layoutModel) return "";

    const leafs = globalStore.get(layoutModel.leafs);
    if (!leafs || leafs.length === 0) return "";

    const contextParts: string[] = [];
    let blocksProcessed = 0;

    for (const leaf of leafs) {
        if (blocksProcessed >= MAX_BLOCKS) break;

        const blockId = (leaf.data as any)?.blockId;
        if (!blockId) continue;

        const blockAtom = WOS.getWaveObjectAtom<Block>(`block:${blockId}`);
        const block = globalStore.get(blockAtom);
        const view = block?.meta?.["view"];
        if (view !== "term") continue;

        // respect opt-out flag
        if (block?.meta?.["term:privacy"] === "hidden") continue;

        try {
            const result = await RpcApi.TermGetScrollbackLinesCommand(
                TabRpcClient,
                { linestart: -MAX_LINES_PER_BLOCK, lineend: -1, lastcommand: false },
                { route: makeFeBlockRouteId(blockId), timeout: 3000 }
            );
            if (result?.lines?.length) {
                const blockName = block?.meta?.["display:name"] ?? blockId.slice(0, 8);
                contextParts.push(`[Block: ${blockName}]\n${result.lines.join("\n")}`);
                blocksProcessed++;
            }
        } catch (_) {
            // non-fatal: block may not have an active term wsh client yet
        }
    }

    if (contextParts.length === 0) return "";
    return contextParts.join("\n\n");
}
