// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

import { modalsModel } from "@/app/store/modalmodel";
import { makeIconClass } from "@/util/util";
import clsx from "clsx";
import React, { useCallback, useEffect, useRef, useState } from "react";
import ReactDOM from "react-dom";
import { getCommands, getRecentIds, PaletteCommand, recordRecentId } from "./command-registry";

import "./commandpalette.scss";

type CategoryFilter = "all" | "blocks" | "nav" | "settings" | "ai" | "ssh";

const CATEGORY_TABS: { key: CategoryFilter; label: string }[] = [
    { key: "all", label: "All" },
    { key: "blocks", label: "Blocks" },
    { key: "nav", label: "Navigate" },
    { key: "settings", label: "Settings" },
    { key: "ai", label: "AI" },
    { key: "ssh", label: "SSH" },
];

const PREFIX_CATEGORY: Record<string, CategoryFilter> = {
    "@": "blocks",
    "#": "settings",
    "/": "nav",
    "!": "ai",
    "$": "ssh",
};

function fuzzyMatch(query: string, text: string): boolean {
    const q = query.toLowerCase();
    const t = text.toLowerCase();
    let qi = 0;
    for (let i = 0; i < t.length && qi < q.length; i++) {
        if (t[i] === q[qi]) qi++;
    }
    return qi === q.length;
}

function highlightMatch(query: string, text: string): React.ReactNode {
    if (!query) return text;
    const parts: React.ReactNode[] = [];
    const q = query.toLowerCase();
    const t = text;
    let qi = 0;
    let lastIdx = 0;
    for (let i = 0; i < t.length && qi < q.length; i++) {
        if (t[i].toLowerCase() === q[qi]) {
            if (lastIdx < i) parts.push(t.slice(lastIdx, i));
            parts.push(
                <mark key={i} className="cmd-highlight">
                    {t[i]}
                </mark>
            );
            qi++;
            lastIdx = i + 1;
        }
    }
    if (lastIdx < t.length) parts.push(t.slice(lastIdx));
    return parts.length ? parts : text;
}

const CommandPaletteInner = () => {
    const [query, setQuery] = useState("");
    const [selectedIdx, setSelectedIdx] = useState(0);
    const [activeTab, setActiveTab] = useState<CategoryFilter>("all");
    const inputRef = useRef<HTMLInputElement>(null);
    const listRef = useRef<HTMLDivElement>(null);

    const allCommands = getCommands();
    const recentIds = getRecentIds();

    // Parse prefix from query
    const prefixChar = query.length > 0 ? query[0] : null;
    const prefixCategory = prefixChar && PREFIX_CATEGORY[prefixChar] ? PREFIX_CATEGORY[prefixChar] : null;
    const searchTerm = prefixCategory ? query.slice(1).trim() : query.trim();
    const effectiveCategory = prefixCategory ?? (activeTab === "all" ? null : activeTab);

    const filteredItems: PaletteCommand[] = (() => {
        let items = allCommands;
        if (effectiveCategory) items = items.filter((c) => c.category === effectiveCategory);
        if (!searchTerm) {
            // Show recents first when query empty
            const recent = recentIds.map((id) => items.find((c) => c.id === id)).filter(Boolean) as PaletteCommand[];
            const rest = items.filter((c) => !recentIds.includes(c.id));
            const combined = [...recent, ...rest];
            return combined.slice(0, 15);
        }
        return items.filter(
            (c) => fuzzyMatch(searchTerm, c.label) || (c.description && fuzzyMatch(searchTerm, c.description))
        );
    })();

    const closeModal = useCallback(() => {
        modalsModel.popModal();
    }, []);

    const executeCommand = useCallback(
        (cmd: PaletteCommand) => {
            recordRecentId(cmd.id);
            closeModal();
            // Defer action so modal is gone before it runs
            setTimeout(() => cmd.action(), 50);
        },
        [closeModal]
    );

    // Focus input on mount
    useEffect(() => {
        inputRef.current?.focus();
    }, []);

    // Reset selection when filtered list changes
    useEffect(() => {
        setSelectedIdx(0);
    }, [query, activeTab]);

    // Scroll selected item into view
    useEffect(() => {
        const el = listRef.current?.children[selectedIdx] as HTMLElement | undefined;
        el?.scrollIntoView({ block: "nearest" });
    }, [selectedIdx]);

    const handleKeyDown = useCallback(
        (e: React.KeyboardEvent) => {
            if (e.key === "Escape") {
                e.preventDefault();
                closeModal();
                return;
            }
            if (e.key === "ArrowDown") {
                e.preventDefault();
                setSelectedIdx((i) => Math.min(i + 1, filteredItems.length - 1));
                return;
            }
            if (e.key === "ArrowUp") {
                e.preventDefault();
                setSelectedIdx((i) => Math.max(i - 1, 0));
                return;
            }
            if (e.key === "Enter") {
                e.preventDefault();
                const cmd = filteredItems[selectedIdx];
                if (cmd) executeCommand(cmd);
                return;
            }
        },
        [closeModal, filteredItems, selectedIdx, executeCommand]
    );

    const renderIcon = (icon?: string) => {
        if (!icon) return null;
        return <i className={clsx(makeIconClass(icon, false), "cmd-item-icon-fa")} />;
    };

    return ReactDOM.createPortal(
        <div className="cmd-overlay" onClick={closeModal} onKeyDown={handleKeyDown}>
            <div className="cmd-palette" onClick={(e) => e.stopPropagation()}>
                {/* Search bar */}
                <div className="cmd-search-wrap">
                    <i className="fa-regular fa-magnifying-glass cmd-search-icon" />
                    <input
                        ref={inputRef}
                        className="cmd-input"
                        placeholder="Type a command... (@blocks #settings /nav !ai $ssh)"
                        value={query}
                        onChange={(e) => setQuery(e.target.value)}
                        onKeyDown={handleKeyDown}
                        autoComplete="off"
                        spellCheck={false}
                    />
                    {query && (
                        <button className="cmd-clear" onClick={() => setQuery("")} tabIndex={-1}>
                            <i className="fa-solid fa-xmark" />
                        </button>
                    )}
                </div>

                {/* Category tabs */}
                <div className="cmd-tabs">
                    {CATEGORY_TABS.map((tab) => (
                        <button
                            key={tab.key}
                            className={clsx("cmd-tab", { "cmd-tab--active": activeTab === tab.key && !prefixCategory })}
                            onClick={() => {
                                setActiveTab(tab.key);
                                setSelectedIdx(0);
                                inputRef.current?.focus();
                            }}
                            tabIndex={-1}
                        >
                            {tab.label}
                        </button>
                    ))}
                </div>

                {/* Results list */}
                <div className="cmd-results" ref={listRef}>
                    {filteredItems.length === 0 ? (
                        <div className="cmd-empty">
                            <i className="fa-regular fa-magnifying-glass cmd-empty-icon" />
                            <span>No results for "{searchTerm}"</span>
                        </div>
                    ) : (
                        filteredItems.map((cmd, idx) => (
                            <div
                                key={cmd.id}
                                className={clsx("cmd-item", { "cmd-item--selected": idx === selectedIdx })}
                                onClick={() => executeCommand(cmd)}
                                onMouseEnter={() => setSelectedIdx(idx)}
                            >
                                <span className={clsx("cmd-item-icon", `cmd-item-icon--${cmd.category}`)}>
                                    {renderIcon(cmd.icon)}
                                </span>
                                <div className="cmd-item-body">
                                    <span className="cmd-item-label">
                                        {highlightMatch(searchTerm, cmd.label)}
                                    </span>
                                    {cmd.description && (
                                        <span className="cmd-item-desc">{cmd.description}</span>
                                    )}
                                </div>
                                <span className={clsx("cmd-item-badge", `cmd-item-badge--${cmd.category}`)}>
                                    {cmd.category}
                                </span>
                                {cmd.shortcut && <span className="cmd-shortcut">{cmd.shortcut}</span>}
                            </div>
                        ))
                    )}
                </div>

                {/* Footer */}
                <div className="cmd-footer">
                    <span>
                        <kbd>↑↓</kbd> navigate
                    </span>
                    <span>
                        <kbd>↵</kbd> select
                    </span>
                    <span>
                        <kbd>Esc</kbd> close
                    </span>
                    <span className="cmd-footer-count">{filteredItems.length} items</span>
                </div>
            </div>
        </div>,
        document.getElementById("main")!
    );
};

const CommandPaletteModal = () => {
    return <CommandPaletteInner />;
};

CommandPaletteModal.displayName = "CommandPaletteModal";

export { CommandPaletteModal };
