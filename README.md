<p align="center">
  <h1 align="center">Terminolgy</h1>
  <p align="center">Sleek AI-powered terminal. Cross-platform. Intelligent.</p>
</p>

<p align="center">
  <a href="https://terminolgy.io">Website</a> ·
  <a href="https://docs.terminolgy.io">Docs</a> ·
  <a href="https://github.com/PhenixStar/terminolgy/releases">Download</a>
</p>

---

## What is Terminolgy?

Terminolgy is an AI-native terminal for macOS, Linux, and Windows. Built on Electron + Go, it combines traditional terminal power with modern features:

- **GPU/Disk/Net Sysinfo** — native system monitoring graphs (not just CPU/memory)
- **AI Error Analysis** — failed commands automatically trigger AI-powered fix suggestions
- **Command Palette** — VS Code-style `Ctrl+Shift+P` for instant access to any action
- **Compact Headers** — auto-hide block chrome to maximize screen space
- **Multi-Machine Dashboard** — monitor your entire infrastructure from one terminal
- **Docker Panel** — manage containers across hosts with interactive web UI
- **Network Topology** — visualize your network with live status
- **Built-in Browser** — web views inside terminal blocks
- **SSH Integration** — persistent sessions, wsh/tsh shell helper, remote file browsing
- **Workspace System** — organize widgets by context (Ops, Dev, Network)

## Install

### Windows

Download the latest [MSI installer](https://github.com/PhenixStar/terminolgy/releases/latest) or portable ZIP.

### macOS / Linux

Coming soon — build from source (see [Building](#building-from-source)).

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

## Architecture

Terminolgy is an Electron app with a Go backend (`terminolgy-srv`). The frontend uses React + TypeScript. Terminal rendering via xterm.js. SSH via `tsh` (terminolgy shell helper).

## Configuration

Settings at `~/.config/terminolgy/settings.json` (Linux/macOS) or `%LOCALAPPDATA%\terminolgy\` (Windows).

Custom widgets via `widgets.json`. See [docs](https://docs.terminolgy.io/customwidgets).

## License

Apache-2.0 — based on [Wave Terminal](https://github.com/wavetermdev/waveterm) with significant enhancements.

## Credits

Built by [Nulled AI](https://nulled.ai). Originally forked from Wave Terminal by Command Line Inc.
