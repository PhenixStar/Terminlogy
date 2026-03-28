// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

import { getTabBadgeAtom } from "@/app/store/badge";
import { refocusNode } from "@/app/store/global";
import { RpcApi } from "@/app/store/wshclientapi";
import { TabRpcClient } from "@/app/store/wshrpcutil";
import { waveEventSubscribeSingle } from "@/app/store/wps";
import { WaveEnv, WaveEnvSubset, useWaveEnv } from "@/app/waveenv/waveenv";
import { Button } from "@/element/button";
import { validateCssColor } from "@/util/color-validator";
import { fireAndForget } from "@/util/util";
import clsx from "clsx";
import { useAtomValue } from "jotai";
import { forwardRef, memo, useCallback, useEffect, useImperativeHandle, useRef, useState } from "react";
import { getWaveObjectAtom, makeORef } from "../store/wos";
import { TabBadges } from "./tabbadges";
import "./tab.scss";
import { buildTabContextMenu } from "./tabcontextmenu";

export type TabEnv = WaveEnvSubset<{
    rpc: {
        ActivityCommand: WaveEnv["rpc"]["ActivityCommand"];
        SetConfigCommand: WaveEnv["rpc"]["SetConfigCommand"];
        SetMetaCommand: WaveEnv["rpc"]["SetMetaCommand"];
        UpdateTabNameCommand: WaveEnv["rpc"]["UpdateTabNameCommand"];
    };
    atoms: {
        fullConfigAtom: WaveEnv["atoms"]["fullConfigAtom"];
    };
    wos: WaveEnv["wos"];
    getSettingsKeyAtom: WaveEnv["getSettingsKeyAtom"];
    showContextMenu: WaveEnv["showContextMenu"];
}>;

interface TabVProps {
    tabId: string;
    tabName: string;
    active: boolean;
    showDivider: boolean;
    isDragging: boolean;
    tabWidth: number;
    isNew: boolean;
    badges?: Badge[] | null;
    flagColor?: string | null;
    connection?: string | null;
    hasCompletedBlock?: boolean;
    onClick: () => void;
    onMouseEnter?: () => void;
    onClose: (event: React.MouseEvent<HTMLButtonElement, MouseEvent> | null) => void;
    onDragStart: (event: React.MouseEvent<HTMLDivElement, MouseEvent>) => void;
    onContextMenu: (e: React.MouseEvent<HTMLDivElement>) => void;
    onRename: (newName: string) => void;
    /** Optional ref that TabV populates with a startRename() function for external callers */
    renameRef?: React.RefObject<(() => void) | null>;
}

const TabV = forwardRef<HTMLDivElement, TabVProps>((props, ref) => {
    const {
        tabId,
        tabName,
        active,
        showDivider,
        isDragging,
        tabWidth,
        isNew,
        badges,
        flagColor,
        connection,
        hasCompletedBlock,
        onClick,
        onMouseEnter,
        onClose,
        onDragStart,
        onContextMenu,
        onRename,
        renameRef,
    } = props;
    const MaxTabNameLength = 14;
    const truncateTabName = (name: string) => [...(name ?? "")].slice(0, MaxTabNameLength).join("");
    const displayName = truncateTabName(tabName);
    const [originalName, setOriginalName] = useState(displayName);
    const [isEditable, setIsEditable] = useState(false);

    const editableRef = useRef<HTMLDivElement>(null);
    const editableTimeoutRef = useRef<NodeJS.Timeout>(null);
    const tabRef = useRef<HTMLDivElement>(null);

    useImperativeHandle(ref, () => tabRef.current as HTMLDivElement);

    useEffect(() => {
        setOriginalName(truncateTabName(tabName));
    }, [tabName]);

    useEffect(() => {
        return () => {
            if (editableTimeoutRef.current) {
                clearTimeout(editableTimeoutRef.current);
            }
        };
    }, []);

    const selectEditableText = useCallback(() => {
        if (!editableRef.current) {
            return;
        }
        editableRef.current.focus();
        const range = document.createRange();
        const selection = window.getSelection();
        if (!selection) {
            return;
        }
        range.selectNodeContents(editableRef.current);
        selection.removeAllRanges();
        selection.addRange(range);
    }, []);

    const startRename = useCallback(() => {
        setIsEditable(true);
        editableTimeoutRef.current = setTimeout(() => {
            selectEditableText();
        }, 50);
    }, [selectEditableText]);

    const handleRenameTab: React.MouseEventHandler<HTMLDivElement> = useCallback(
        (event) => {
            event?.stopPropagation();
            startRename();
        },
        [startRename]
    );

    // Expose startRename to external callers (e.g. context menu in TabInner)
    if (renameRef != null) {
        renameRef.current = startRename;
    }

    const handleBlur = () => {
        if (!editableRef.current) return;
        let newText = editableRef.current.innerText.trim();
        newText = newText || originalName;
        editableRef.current.innerText = newText;
        setIsEditable(false);
        onRename(newText);
    };

    const handleKeyDown: React.KeyboardEventHandler<HTMLDivElement> = (event) => {
        if ((event.metaKey || event.ctrlKey) && event.key === "a") {
            event.preventDefault();
            selectEditableText();
            return;
        }
        if (!editableRef.current) return;
        const curLen = Array.from(editableRef.current.innerText).length;
        if (event.key === "Enter") {
            event.preventDefault();
            event.stopPropagation();
            if (editableRef.current.innerText.trim() === "") {
                editableRef.current.innerText = originalName;
            }
            editableRef.current.blur();
        } else if (event.key === "Escape") {
            editableRef.current.innerText = originalName;
            editableRef.current.blur();
            event.preventDefault();
            event.stopPropagation();
        } else if (curLen >= 14 && !["Backspace", "Delete", "ArrowLeft", "ArrowRight"].includes(event.key)) {
            const selection = window.getSelection();
            if (!selection || selection.isCollapsed) {
                event.preventDefault();
                event.stopPropagation();
            }
        }
    };

    useEffect(() => {
        if (tabRef.current && isNew) {
            const initialWidth = `${(tabWidth / 3) * 2}px`;
            tabRef.current.style.setProperty("--initial-tab-width", initialWidth);
            tabRef.current.style.setProperty("--final-tab-width", `${tabWidth}px`);
        }
    }, [isNew, tabWidth]);

    const handleMouseDownOnClose = (event: React.MouseEvent<HTMLButtonElement, MouseEvent>) => {
        event.stopPropagation();
    };

    return (
        <div
            ref={tabRef}
            className={clsx("tab", {
                active,
                dragging: isDragging,
                "new-tab": isNew,
            })}
            onMouseDown={onDragStart}
            onClick={onClick}
            onMouseEnter={onMouseEnter}
            onContextMenu={onContextMenu}
            data-tab-id={tabId}
        >
            {showDivider && <div className="tab-divider" />}
            <div className="tab-inner">
                <div
                    ref={editableRef}
                    className={clsx("name", { focused: isEditable })}
                    contentEditable={isEditable}
                    onDoubleClick={handleRenameTab}
                    onBlur={handleBlur}
                    onKeyDown={handleKeyDown}
                    suppressContentEditableWarning={true}
                >
                    {displayName}
                </div>
                <TabBadges badges={badges} flagColor={flagColor} />
                {connection && (
                    <i
                        className="fa fa-solid fa-server"
                        title={`Connection: ${connection}`}
                        style={{ fontSize: "10px", opacity: 0.6, marginLeft: "3px", marginRight: "2px" }}
                    />
                )}
                {hasCompletedBlock && !active && (
                    <span
                        title="A command finished in this tab"
                        style={{
                            display: "inline-block",
                            width: "6px",
                            height: "6px",
                            borderRadius: "50%",
                            backgroundColor: "#22c55e",
                            marginLeft: "3px",
                            marginRight: "1px",
                            flexShrink: 0,
                        }}
                    />
                )}
                <Button
                    className="ghost grey close"
                    onClick={onClose}
                    onMouseDown={handleMouseDownOnClose}
                    title="Close Tab"
                >
                    <i className="fa fa-solid fa-xmark" />
                </Button>
            </div>
        </div>
    );
});

TabV.displayName = "TabV";

interface TabProps {
    id: string;
    active: boolean;
    showDivider: boolean;
    isDragging: boolean;
    tabWidth: number;
    isNew: boolean;
    onSelect: () => void;
    onMouseEnter?: () => void;
    onClose: (event: React.MouseEvent<HTMLButtonElement, MouseEvent> | null) => void;
    onDragStart: (event: React.MouseEvent<HTMLDivElement, MouseEvent>) => void;
    onLoaded: () => void;
}

const TabInner = forwardRef<HTMLDivElement, TabProps>((props, ref) => {
    const { id, active, showDivider, isDragging, tabWidth, isNew, onLoaded, onSelect, onMouseEnter, onClose, onDragStart } = props;
    const env = useWaveEnv<TabEnv>();
    const [tabData, _] = env.wos.useWaveObjectValue<Tab>(makeORef("tab", id));
    const badges = useAtomValue(getTabBadgeAtom(id, env));
    const [hasCompletedBlock, setHasCompletedBlock] = useState(false);

    // Track block completion: subscribe to controllerstatus events for this tab's blocks.
    // Stabilize the dep with a joined string to avoid re-subscribing on every tabData reference change.
    const blockIdsKey = (tabData?.blockids ?? []).join(",");
    useEffect(() => {
        const blockIds = tabData?.blockids ?? [];
        if (blockIds.length === 0) return;
        const unsubs = blockIds.map((blockId) =>
            waveEventSubscribeSingle({
                eventType: "controllerstatus",
                scope: makeORef("block", blockId),
                handler: (event) => {
                    const data = event.data as BlockControllerRuntimeStatus;
                    if (data?.shellprocstatus === "done") {
                        setHasCompletedBlock(true);
                    }
                },
            })
        );
        return () => unsubs.forEach((fn) => fn());
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [blockIdsKey]);

    // Clear the dot when this tab becomes active
    useEffect(() => {
        if (active) {
            setHasCompletedBlock(false);
        }
    }, [active]);

    const rawFlagColor = tabData?.meta?.["tab:flagcolor"];
    let flagColor: string | null = null;
    if (rawFlagColor) {
        try {
            validateCssColor(rawFlagColor);
            flagColor = rawFlagColor;
        } catch {
            flagColor = null;
        }
    }
    const connection = tabData?.meta?.["tab:connection"] ?? null;

    const loadedRef = useRef(false);
    const renameRef = useRef<(() => void) | null>(null);

    useEffect(() => {
        if (!loadedRef.current) {
            onLoaded();
            loadedRef.current = true;
        }
    }, [onLoaded]);

    const handleTabClick = () => {
        onSelect();
    };

    const handleContextMenu = useCallback(
        (e: React.MouseEvent<HTMLDivElement, MouseEvent>) => {
            e.preventDefault();
            const connListPromise = RpcApi.ConnListCommand(TabRpcClient, { timeout: 2000 }).catch(() => [] as string[]);
            connListPromise.then((connList) => {
                const menu = buildTabContextMenu(id, renameRef, onClose, env, connList);
                env.showContextMenu(menu, e);
            });
        },
        [id, onClose, env]
    );

    const handleRename = useCallback(
        (newName: string) => {
            fireAndForget(() => env.rpc.UpdateTabNameCommand(TabRpcClient, id, newName));
            setTimeout(() => refocusNode(null), 10);
        },
        [id, env]
    );

    return (
        <TabV
            ref={ref}
            tabId={id}
            tabName={tabData?.name ?? ""}
            active={active}
            showDivider={showDivider}
            isDragging={isDragging}
            tabWidth={tabWidth}
            isNew={isNew}
            badges={badges}
            flagColor={flagColor}
            connection={connection}
            hasCompletedBlock={hasCompletedBlock}
            onClick={handleTabClick}
            onMouseEnter={onMouseEnter}
            onClose={onClose}
            onDragStart={onDragStart}
            onContextMenu={handleContextMenu}
            onRename={handleRename}
            renameRef={renameRef}
        />
    );
});
const Tab = memo(TabInner);
Tab.displayName = "Tab";

export { Tab, TabV };
