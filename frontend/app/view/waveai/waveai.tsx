// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

import { Button } from "@/app/element/button";
import { WorkspaceLayoutModel } from "@/app/workspace/workspace-layout-model";
import { atom } from "jotai";
import { useCallback } from "react";

export class WaveAiModel implements ViewModel {
    viewType = "waveai";
    viewIcon = atom("sparkles");
    viewName = atom("Terminolgy AI");
    noPadding = atom(true);
    viewComponent = WaveAiDeprecatedView;

    constructor({ blockId, nodeModel, tabModel }: ViewModelInitType) {
        this.blockId = blockId;
        this.nodeModel = nodeModel;
        this.tabModel = tabModel;
        this.aiWshClient = new AiWshClient(blockId, this);
        DefaultRouter.registerRoute(makeFeBlockRouteId(blockId), this.aiWshClient);
        this.locked = atom(false);
        this.cancel = false;
        this.viewType = "waveai";
        this.blockAtom = WOS.getWaveObjectAtom<Block>(`block:${blockId}`);
        this.viewIcon = atom("sparkles");
        this.viewName = atom("Terminolgy AI");
        this.messagesAtom = atom([]);
        this.messagesSplitAtom = splitAtom(this.messagesAtom);
        this.latestMessageAtom = atom((get) => get(this.messagesAtom).slice(-1)[0]);
        this.presetKey = atom((get) => {
            const metaPresetKey = get(this.blockAtom).meta["ai:preset"];
            const globalPresetKey = get(atoms.settingsAtom)["ai:preset"];
            return metaPresetKey ?? globalPresetKey;
        });
        this.presetMap = atom((get) => {
            const fullConfig = get(atoms.fullConfigAtom);
            const presets = fullConfig.presets;
            const settings = fullConfig.settings;
            return Object.fromEntries(
                Object.entries(presets)
                    .filter(([k]) => k.startsWith("ai@"))
                    .map(([k, v]) => {
                        const aiPresetKeys = Object.keys(v).filter((k) => k.startsWith("ai:"));
                        const newV = { ...v };
                        newV["display:name"] =
                            aiPresetKeys.length == 1 && aiPresetKeys.includes("ai:*")
                                ? `${newV["display:name"] ?? "Default"} (${settings["ai:model"]})`
                                : newV["display:name"];
                        return [k, newV];
                    })
            );
        });

        this.addMessageAtom = atom(null, (get, set, message: ChatMessageType) => {
            const messages = get(this.messagesAtom);
            set(this.messagesAtom, [...messages, message]);
        });

        this.updateLastMessageAtom = atom(null, (get, set, text: string, isUpdating: boolean) => {
            const messages = get(this.messagesAtom);
            const lastMessage = messages[messages.length - 1];
            if (lastMessage.user == "assistant") {
                const updatedMessage = { ...lastMessage, text: lastMessage.text + text, isUpdating };
                set(this.messagesAtom, [...messages.slice(0, -1), updatedMessage]);
            }
        });
        this.removeLastMessageAtom = atom(null, (get, set) => {
            const messages = get(this.messagesAtom);
            messages.pop();
            set(this.messagesAtom, [...messages]);
        });
        this.simulateAssistantResponseAtom = atom(null, async (_, set, userMessage: ChatMessageType) => {
            // unused at the moment. can replace the temp() function in the future
            const typingMessage: ChatMessageType = {
                id: crypto.randomUUID(),
                user: "assistant",
                text: "",
            };

            // Add a typing indicator
            set(this.addMessageAtom, typingMessage);
            const parts = userMessage.text.split(" ");
            let currentPart = 0;
            while (currentPart < parts.length) {
                const part = parts[currentPart] + " ";
                set(this.updateLastMessageAtom, part, true);
                currentPart++;
            }
            set(this.updateLastMessageAtom, "", false);
        });

        this.mergedPresets = atom((get) => {
            const meta = get(this.blockAtom).meta;
            let settings = get(atoms.settingsAtom);
            let presetKey = get(this.presetKey);
            let presets = get(atoms.fullConfigAtom).presets;
            let selectedPresets = presets?.[presetKey] ?? {};

            let mergedPresets: MetaType = {};
            mergedPresets = mergeMeta(settings, selectedPresets, "ai");
            mergedPresets = mergeMeta(mergedPresets, meta, "ai");

            return mergedPresets;
        });

        this.aiOpts = atom((get) => {
            const mergedPresets = get(this.mergedPresets);

            const opts: WaveAIOptsType = {
                model: mergedPresets["ai:model"] ?? null,
                apitype: mergedPresets["ai:apitype"] ?? null,
                orgid: mergedPresets["ai:orgid"] ?? null,
                apitoken: mergedPresets["ai:apitoken"] ?? null,
                apiversion: mergedPresets["ai:apiversion"] ?? null,
                maxtokens: mergedPresets["ai:maxtokens"] ?? null,
                timeoutms: mergedPresets["ai:timeoutms"] ?? 60000,
                baseurl: mergedPresets["ai:baseurl"] ?? null,
                proxyurl: mergedPresets["ai:proxyurl"] ?? null,
            };
            return opts;
        });

        this.viewText = atom((get) => {
            const viewTextChildren: HeaderElem[] = [];
            const aiOpts = get(this.aiOpts);
            const presets = get(this.presetMap);
            const presetKey = get(this.presetKey);
            const presetName = presets[presetKey]?.["display:name"] ?? "";
            const isCloud = isBlank(aiOpts.apitoken) && isBlank(aiOpts.baseurl);

            // Handle known API providers
            switch (aiOpts?.apitype) {
                case "anthropic":
                    viewTextChildren.push({
                        elemtype: "iconbutton",
                        icon: "globe",
                        title: `Using Remote Anthropic API (${aiOpts.model})`,
                        noAction: true,
                    });
                    break;
                case "perplexity":
                    viewTextChildren.push({
                        elemtype: "iconbutton",
                        icon: "globe",
                        title: `Using Remote Perplexity API (${aiOpts.model})`,
                        noAction: true,
                    });
                    break;
                default:
                    if (isCloud) {
                        viewTextChildren.push({
                            elemtype: "iconbutton",
                            icon: "cloud",
                            title: "Using Wave's AI Proxy (gpt-5-mini)",
                            noAction: true,
                        });
                    } else {
                        const baseUrl = aiOpts.baseurl ?? "OpenAI Default Endpoint";
                        const modelName = aiOpts.model;
                        if (baseUrl.startsWith("http://localhost") || baseUrl.startsWith("http://127.0.0.1")) {
                            viewTextChildren.push({
                                elemtype: "iconbutton",
                                icon: "location-dot",
                                title: `Using Local Model @ ${baseUrl} (${modelName})`,
                                noAction: true,
                            });
                        } else {
                            viewTextChildren.push({
                                elemtype: "iconbutton",
                                icon: "globe",
                                title: `Using Remote Model @ ${baseUrl} (${modelName})`,
                                noAction: true,
                            });
                        }
                    }
            }

            const dropdownItems = Object.entries(presets)
                .sort((a, b) => ((a[1]["display:order"] ?? 0) > (b[1]["display:order"] ?? 0) ? 1 : -1))
                .map(
                    (preset) =>
                        ({
                            label: preset[1]["display:name"],
                            onClick: () =>
                                fireAndForget(() =>
                                    ObjectService.UpdateObjectMeta(WOS.makeORef("block", this.blockId), {
                                        "ai:preset": preset[0],
                                    })
                                ),
                        }) as MenuItem
                );
            dropdownItems.push({
                label: "Add AI preset...",
                onClick: () => {
                    fireAndForget(async () => {
                        const path = `${getApi().getConfigDir()}/presets/ai.json`;
                        const blockDef: BlockDef = {
                            meta: {
                                view: "preview",
                                file: path,
                            },
                        };
                        await createBlock(blockDef, false, true);
                    });
                },
            });
            viewTextChildren.push({
                elemtype: "menubutton",
                text: presetName,
                title: "Select AI Configuration",
                items: dropdownItems,
            });
            return viewTextChildren;
        });
        this.endIconButtons = atom((_) => {
            let clearButton: IconButtonDecl = {
                elemtype: "iconbutton",
                icon: "delete-left",
                title: "Clear Chat History",
                click: this.clearMessages.bind(this),
            };
            return [clearButton];
        });
    }

    get viewComponent(): ViewComponent {
        return WaveAi;
    }

    dispose() {
        DefaultRouter.unregisterRoute(makeFeBlockRouteId(this.blockId));
    }

    async populateMessages(): Promise<void> {
        const history = await this.fetchAiData();
        globalStore.set(this.messagesAtom, history.map(promptToMsg));
    }

    async fetchAiData(): Promise<Array<WaveAIPromptMessageType>> {
        const { data } = await fetchWaveFile(this.blockId, "aidata");
        if (!data) {
            return [];
        }
        const history: Array<WaveAIPromptMessageType> = JSON.parse(new TextDecoder().decode(data));
        return history.slice(Math.max(history.length - slidingWindowSize, 0));
    }

    giveFocus(): boolean {
        if (this?.textAreaRef?.current) {
            this.textAreaRef.current?.focus();
            return true;
        }
        return false;
    }

    getAiName(): string {
        const blockMeta = globalStore.get(this.blockAtom)?.meta ?? {};
        const settings = globalStore.get(atoms.settingsAtom) ?? {};
        const name = blockMeta["ai:name"] ?? settings["ai:name"] ?? null;
        return name;
    }

    setLocked(locked: boolean) {
        globalStore.set(this.locked, locked);
    }

    sendMessage(text: string, user: string = "user") {
        const clientId = ClientModel.getInstance().clientId;
        this.setLocked(true);

        const newMessage: ChatMessageType = {
            id: crypto.randomUUID(),
            user,
            text,
        };
        globalStore.set(this.addMessageAtom, newMessage);
        // send message to backend and get response
        const opts = globalStore.get(this.aiOpts);
        const newPrompt: WaveAIPromptMessageType = {
            role: "user",
            content: text,
        };
        const handleAiStreamingResponse = async () => {
            const typingMessage: ChatMessageType = {
                id: crypto.randomUUID(),
                user: "assistant",
                text: "",
            };

            // Add a typing indicator
            globalStore.set(this.addMessageAtom, typingMessage);
            const history = await this.fetchAiData();
            const beMsg: WaveAIStreamRequest = {
                clientid: clientId,
                opts: opts,
                prompt: [...history, newPrompt],
            };
            let fullMsg = "";
            try {
                const aiGen = RpcApi.StreamWaveAiCommand(TabRpcClient, beMsg, { timeout: opts.timeoutms });
                for await (const msg of aiGen) {
                    fullMsg += msg.text ?? "";
                    globalStore.set(this.updateLastMessageAtom, msg.text ?? "", true);
                    if (this.cancel) {
                        break;
                    }
                }
                if (fullMsg == "") {
                    // remove a message if empty
                    globalStore.set(this.removeLastMessageAtom);
                    // only save the author's prompt
                    await BlockService.SaveWaveAiData(this.blockId, [...history, newPrompt]);
                } else {
                    const responsePrompt: WaveAIPromptMessageType = {
                        role: "assistant",
                        content: fullMsg,
                    };
                    //mark message as complete
                    globalStore.set(this.updateLastMessageAtom, "", false);
                    // save a complete message prompt and response
                    await BlockService.SaveWaveAiData(this.blockId, [...history, newPrompt, responsePrompt]);
                }
            } catch (error) {
                const updatedHist = [...history, newPrompt];
                if (fullMsg == "") {
                    globalStore.set(this.removeLastMessageAtom);
                } else {
                    globalStore.set(this.updateLastMessageAtom, "", false);
                    const responsePrompt: WaveAIPromptMessageType = {
                        role: "assistant",
                        content: fullMsg,
                    };
                    updatedHist.push(responsePrompt);
                }
                const errMsg: string = (error as Error).message;
                const errorMessage: ChatMessageType = {
                    id: crypto.randomUUID(),
                    user: "error",
                    text: errMsg,
                };
                globalStore.set(this.addMessageAtom, errorMessage);
                globalStore.set(this.updateLastMessageAtom, "", false);
                const errorPrompt: WaveAIPromptMessageType = {
                    role: "error",
                    content: errMsg,
                };
                updatedHist.push(errorPrompt);
                await BlockService.SaveWaveAiData(this.blockId, updatedHist);
            }
            this.setLocked(false);
            this.cancel = false;
        };
        fireAndForget(handleAiStreamingResponse);
    }

    useWaveAi() {
        return {
            sendMessage: this.sendMessage.bind(this) as (text: string) => void,
        };
    }

    async clearMessages() {
        await BlockService.SaveWaveAiData(this.blockId, []);
        globalStore.set(this.messagesAtom, []);
    }

    keyDownHandler(waveEvent: WaveKeyboardEvent): boolean {
        if (checkKeyPressed(waveEvent, "Cmd:l")) {
            fireAndForget(this.clearMessages.bind(this));
            return true;
        }
        return false;
    }
}

function WaveAiDeprecatedView() {
    const handleOpenAIPanel = useCallback(() => {
        WorkspaceLayoutModel.getInstance().setAIPanelVisible(true);
    }, []);

    return (
        <div ref={waveaiRef} className="waveai">
            {isUsingProxy && (
                <div className="flex items-start gap-3 px-4 py-2 bg-orange-500/25 border-b border-orange-500/50 text-sm">
                    <i className="fa-sharp fa-solid fa-triangle-exclamation text-orange-300 mt-0.5"></i>
                    <span className="text-primary/90">
                        Terminolgy AI Proxy is deprecated and will be removed. Please use the new{" "}
                        <button
                            onClick={handleOpenAIPanel}
                            className="text-accent hover:text-accent/80 underline cursor-pointer"
                        >
                            Terminolgy AI panel
                        </button>{" "}
                        instead (better model, terminal integration, tool support, image uploads).
                    </span>
                </div>
            )}
            <div className="waveai-chat">
                <ChatWindow ref={osRef} chatWindowRef={chatWindowRef} msgWidths={msgWidths} model={model} />
            </div>
            <div className="waveai-controls">
                <div className="waveai-input-wrapper">
                    <ChatInput
                        ref={inputRef}
                        value={value}
                        model={model}
                        onChange={handleTextAreaChange}
                        onKeyDown={handleTextAreaKeyDown}
                        onMouseDown={handleTextAreaMouseDown}
                        baseFontSize={baseFontSize}
                    />
                </div>
                <Button className={buttonClass} onClick={handleButtonPress}>
                    <i className={buttonIcon} title={buttonTitle} />
                </Button>
            </div>
            <div className="flex-[6]" />
        </div>
    );
}
