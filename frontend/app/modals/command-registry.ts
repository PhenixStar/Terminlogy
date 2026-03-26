// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

import { createBlock, createTab, globalStore, replaceBlock } from "@/app/store/global";
import { modalsModel } from "@/app/store/modalmodel";
import { WorkspaceLayoutModel } from "@/app/workspace/workspace-layout-model";
import { getLayoutModelForStaticTab } from "@/layout/index";
import { fireAndForget } from "@/util/util";

export interface PaletteCommand {
    id: string;
    label: string;
    description?: string;
    category: "blocks" | "nav" | "settings" | "ai" | "ssh";
    icon?: string;
    shortcut?: string;
    action: () => void;
}

const RECENT_KEY = "wave-palette-recent";
const RECENT_MAX = 10;

export function getRecentIds(): string[] {
    try {
        return JSON.parse(localStorage.getItem(RECENT_KEY) ?? "[]");
    } catch {
        return [];
    }
}

export function recordRecentId(id: string): void {
    const recent = getRecentIds().filter((r) => r !== id);
    recent.unshift(id);
    localStorage.setItem(RECENT_KEY, JSON.stringify(recent.slice(0, RECENT_MAX)));
}

function getFocusedBlockId(): string | null {
    try {
        const layoutModel = getLayoutModelForStaticTab();
        if (!layoutModel) return null;
        const node = globalStore.get(layoutModel.focusedNode) as { data?: { blockId?: string } } | null;
        return node?.data?.blockId ?? null;
    } catch {
        return null;
    }
}

function openSshBlock(connName: string): void {
    fireAndForget(() =>
        createBlock({
            meta: {
                view: "term",
                connection: connName,
            },
        })
    );
}

export function getCommands(): PaletteCommand[] {
    return [
        // --- Blocks ---
        {
            id: "block:new-terminal",
            label: "New Terminal",
            description: "Open a new terminal block",
            category: "blocks",
            icon: "square-terminal",
            action: () => fireAndForget(() => createBlock({ meta: { view: "term" } })),
        },
        {
            id: "block:new-browser",
            label: "New Browser",
            description: "Open a new web browser block",
            category: "blocks",
            icon: "globe",
            action: () => fireAndForget(() => createBlock({ meta: { view: "web" } })),
        },
        {
            id: "block:new-ai",
            label: "New AI Chat",
            description: "Open a new AI chat block",
            category: "blocks",
            icon: "sparkles",
            action: () => fireAndForget(() => createBlock({ meta: { view: "waveai" } })),
        },
        {
            id: "block:new-files",
            label: "New File Browser",
            description: "Open a new file browser block",
            category: "blocks",
            icon: "folder",
            action: () => fireAndForget(() => createBlock({ meta: { view: "filebrowser" } })),
        },
        {
            id: "block:close",
            label: "Close Block",
            description: "Close the focused block",
            category: "blocks",
            icon: "xmark",
            shortcut: "Ctrl+W",
            action: () => {
                const blockId = getFocusedBlockId();
                if (!blockId) return;
                const layoutModel = getLayoutModelForStaticTab();
                const node = layoutModel?.getNodeByBlockId(blockId);
                if (node) fireAndForget(() => layoutModel.closeNode(node.id));
            },
        },
        {
            id: "block:magnify",
            label: "Magnify Block",
            description: "Toggle fullscreen for the focused block",
            category: "blocks",
            icon: "expand",
            shortcut: "Cmd+M",
            action: () => {
                const layoutModel = getLayoutModelForStaticTab();
                if (!layoutModel) return;
                const focusedNode = globalStore.get(layoutModel.focusedNode) as { id?: string } | null;
                if (focusedNode?.id) layoutModel.magnifyNodeToggle(focusedNode.id);
            },
        },
        // --- Navigation ---
        {
            id: "nav:new-tab",
            label: "New Tab",
            description: "Create a new workspace tab",
            category: "nav",
            icon: "plus",
            shortcut: "Cmd+T",
            action: () => createTab(),
        },
        {
            id: "nav:toggle-ai",
            label: "Toggle AI Panel",
            description: "Show or hide the AI side panel",
            category: "nav",
            icon: "brain",
            shortcut: "Cmd+Shift+A",
            action: () => {
                const wlm = WorkspaceLayoutModel.getInstance();
                wlm.setAIPanelVisible(!wlm.getAIPanelVisible());
            },
        },
        // --- Settings ---
        {
            id: "settings:open",
            label: "Open Settings",
            description: "Open the settings panel",
            category: "settings",
            icon: "gear",
            action: () => fireAndForget(() => createBlock({ meta: { view: "settings" } })),
        },
        // --- AI ---
        {
            id: "ai:open-chat",
            label: "Open AI Chat",
            description: "Open AI chat in a new block",
            category: "ai",
            icon: "sparkles",
            action: () => fireAndForget(() => createBlock({ meta: { view: "waveai" } })),
        },
        // --- SSH ---
        {
            id: "ssh:annex4",
            label: "Connect: alaa@annex4",
            description: "10.1.1.1:2222",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("alaa@annex4"),
        },
        {
            id: "ssh:dgx1",
            label: "Connect: alaa@dgx1",
            description: "120.28.138.55:2222",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("alaa@dgx1"),
        },
        {
            id: "ssh:dgx1-internal",
            label: "Connect: alaa@dgx1-internal",
            description: "10.10.101.13:2222",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("alaa@dgx1-internal"),
        },
        {
            id: "ssh:mikrotik-hq",
            label: "Connect: alaa@mikrotik-hq",
            description: "10.10.101.1:2222",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("alaa@mikrotik-hq"),
        },
        {
            id: "ssh:ssh-mikrotik",
            label: "Connect: alaa@ssh-mikrotik",
            description: "120.28.138.55:2222",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("alaa@ssh-mikrotik"),
        },
        {
            id: "ssh:warpgate",
            label: "Connect: alaa@warpgate",
            description: "warp.nulled.ai:2222",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("alaa@warpgate"),
        },
        {
            id: "ssh:phenix-dgx",
            label: "Connect: phenix@dgx",
            description: "120.28.138.55:2442",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("phenix@dgx"),
        },
        {
            id: "ssh:phenix-dgx-internal",
            label: "Connect: phenix@dgx-internal",
            description: "10.10.101.13:2222",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("phenix@dgx-internal"),
        },
        {
            id: "ssh:mce-new",
            label: "Connect: root@mce-new",
            description: "152.42.191.40:2222",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("root@mce-new"),
        },
        {
            id: "ssh:hosting",
            label: "Connect: u384663192@hosting",
            description: "77.37.81.228:65002",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("u384663192@hosting"),
        },
        {
            id: "ssh:kali-linux",
            label: "Connect: wsl://kali-linux",
            description: "WSL Kali Linux",
            category: "ssh",
            icon: "server",
            action: () => openSshBlock("wsl://kali-linux"),
        },
    ];
}
