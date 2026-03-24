# WaveTerm Custom Widgets

Infrastructure monitoring widgets and context-aware companion tools for WaveTerm.

## Widget Scripts

| Script | Description |
|--------|-------------|
| `ssh-health.ps1` | Live SSH connection health monitor (PowerShell) |
| `docker-manager.sh` | Remote Docker container dashboard via SSH |
| `cf-tunnel-status.sh` | Cloudflare tunnel health dashboard via SSH |
| `mikrotik-dashboard.sh` | MikroTik router dashboard via SSH |
| `git-sync-status.sh` | Multi-machine git repository sync status |
| `quick-connect.sh` | One-key SSH+command bookmark launcher |
| `companion.sh` | Interactive context-aware tool picker |
| `ctx-launch.sh` | Core context-aware launcher (used by aliases) |

## Context-Aware Companion System

The companion system lets you launch tools (btop, lazygit, htop, etc.) that automatically inherit your current SSH connection and working directory.

### Install

```bash
# Deploy to all configured SSH hosts
bash scripts/deploy-companion.sh

# Deploy to a specific host
bash scripts/deploy-companion.sh phenix@dgx
```

### Configure

Add to WaveTerm `settings.json`:
```json
{
  "cmd:initscript.bash": "[ -f ~/.waveterm/companion/aliases.sh ] && source ~/.waveterm/companion/aliases.sh",
  "cmd:initscript.zsh": "[ -f ~/.waveterm/companion/aliases.sh ] && source ~/.waveterm/companion/aliases.sh"
}
```

### Usage

From any WaveTerm terminal (local or SSH):
```bash
cc         # Interactive picker
clg        # lazygit (context-aware)
cbtop      # btop
cdocker    # lazydocker
cgpu       # nvidia-smi watch
```

## GPU Sysinfo Widget (Fork Feature)

This fork extends the native sysinfo widget with NVIDIA GPU monitoring:
- `GPU` — Average GPU utilization graph
- `GPU + Mem` — GPU util + VRAM usage
- `All GPU` — Per-GPU utilization overlay
- `CPU + GPU` — Combined CPU and GPU

Requires `nvidia-smi` on the target machine.
