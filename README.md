<p align="center">
  <img src="public/logos/terminolgy-logo-256.png" alt="Terminolgy" width="96" />
  <h1 align="center">Terminolgy</h1>
  <p align="center">Sleek AI-powered terminal. Cross-platform. Intelligent.</p>
</p>

<p align="center">
  <a href="https://github.com/PhenixStar/terminolgy/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="License: Apache-2.0" /></a>
  <a href="#install"><img src="https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg" alt="Platform: Windows / macOS / Linux" /></a>
  <a href="https://github.com/PhenixStar/terminolgy/releases"><img src="https://img.shields.io/github/v/release/PhenixStar/terminolgy" alt="Latest Release" /></a>
</p>

<p align="center">
  <a href="https://terminolgy.io">Website</a> ·
  <a href="https://docs.terminolgy.io">Docs</a> ·
  <a href="https://github.com/PhenixStar/terminolgy/releases">Download</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="SECURITY.md">Security</a> ·
  <a href="docs/roadmap.md">Roadmap</a>
</p>

---

## What is Terminolgy?

Terminolgy is an AI-native terminal for macOS, Linux, and Windows. Built on Electron + Go, it combines traditional terminal power with modern features:

- **GPU/Disk/Net Sysinfo** — native system monitoring graphs (not just CPU/memory)
- **AI Error Analysis** — failed commands automatically trigger AI-powered fix suggestions
- **NL-to-Command Ghost Text** — type natural language, AI completes the shell command inline
- **Command Palette** — VS Code-style `Ctrl+Shift+P` for instant access to any action
- **Compact Headers** — auto-hide block chrome to maximize screen space
- **Multi-Machine Dashboard** — monitor your entire infrastructure from one terminal
- **Docker Panel** — manage containers across hosts with interactive web UI
- **Network Topology** — visualize your network with live status
- **Built-in Browser** — web views inside terminal blocks
- **SSH Integration** — persistent sessions, wsh/tsh shell helper, remote file browsing
- **Workspace System** — organize widgets by context (Ops, Dev, Network)
- **ProcessViewer** — built-in task manager with live process list, CPU/memory sorting, and signal support
- **Mouse Back/Forward** — browser-style navigation in web views via mouse buttons
- **Widgets Sidebar Toggle** — show/hide the widget launcher without losing your layout
- **Custom New Tab Layouts** — define default block arrangements for new tabs
- **Dynamic Tab Titles** — tabs auto-rename based on active block content
- **Auto OS Theme Switching** — follows system light/dark mode automatically
- **MiniMax AI Preset** — one-click MiniMax model configuration in AI settings
- **Reveal in Explorer/Finder** — right-click any file path to open it in the system file manager
- **Session Restore** — reopen Terminolgy exactly where you left off (tabs, blocks, connections)
- **Cross-Block AI Context** — AI assistant reads output from multiple terminal blocks simultaneously
- **MCP Host** — built-in Model Context Protocol server; connect any MCP-compatible AI tool
- **Block Output Sharing** — pipe a block's live output directly into an AI or another block
- **Global Show/Hide Hotkey** — `CommandOrControl+Shift+Space` to summon/dismiss the window system-wide

## Install

### Windows

Download the latest [MSI installer](https://github.com/PhenixStar/terminolgy/releases/latest) or portable ZIP.

### macOS / Linux

Build from source — see [BUILD.md](BUILD.md) for full instructions.

## Building from Source

### Prerequisites

- Go 1.22+
- Node.js 20+
- npm
- go-task (`task`)

### Build

```bash
git clone https://github.com/PhenixStar/terminolgy.git
cd terminolgy
task package
```

Output in `make/`:
- `Terminolgy-win32-x64-{version}.exe` (NSIS installer)
- `Terminolgy-win32-x64-{version}.msi` (MSI)
- `Terminolgy-win32-x64-{version}.zip` (portable)

For detailed build instructions see [BUILD.md](BUILD.md).

## Key Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl+Shift+P` | Command palette |
| `Ctrl+Shift+F` | AI fix for failed command |
| `Ctrl+Shift+B` | Toggle compact headers |
| `Tab` | Accept NL-to-command ghost text suggestion |
| `Ctrl+Shift+Space` | Global show/hide (system-wide hotkey) |

## Architecture

Terminolgy is an Electron app with a Go backend (`terminolgy-srv`). The frontend uses React + TypeScript. Terminal rendering via xterm.js. SSH via `tsh` (terminolgy shell helper).

## Configuration

Settings at `~/.config/terminolgy/settings.json` (Linux/macOS) or `%LOCALAPPDATA%\terminolgy\` (Windows).

Custom widgets via `widgets.json`. See [docs](https://docs.terminolgy.io/customwidgets).

## License

Apache-2.0 — based on [Wave Terminal](https://github.com/wavetermdev/waveterm) with significant enhancements.

## Credits

Built by [Nulled AI](https://nulled.ai). Originally forked from Wave Terminal by Command Line Inc.
