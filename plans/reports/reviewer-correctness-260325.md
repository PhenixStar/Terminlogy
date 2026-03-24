# Correctness Review — PhenixStar/waveterm Fork
**Date:** 2026-03-25
**Reviewer:** code-reviewer
**Scope:** keymodel.ts, sysinfo-dial.tsx, sysinfo.go, tabcontextmenu.ts, wshrpctypes.go

---

## Findings

---

### [IMPORTANT] `getDefaultNewBlockDef` connection inheritance is term-only — silent no-op for sysinfo/preview/web blocks

**Evidence:** `keymodel.ts:366-373`
```ts
if (blockData?.meta?.view == "term") {
    if (blockData?.meta?.["cmd:cwd"] != null) {
        termBlockDef.meta["cmd:cwd"] = blockData.meta["cmd:cwd"];
    }
}
if (blockData?.meta?.connection != null) {
    termBlockDef.meta.connection = blockData.meta.connection;
}
```
The `cmd:cwd` inheritance is correctly gated to `view == "term"`. The `connection` inheritance (lines 371-373) is NOT gated — it applies to any focused block type (sysinfo, preview, web, etc.). This is intentional and works correctly for propagating connections.

**However**, the code path is only reached when `focusedNode != null` (line 363). If no node is focused (e.g., all blocks closed, empty layout), it falls through to the tab-level connection fallback at lines 376-383. That fallback path reads `atoms.staticTabId` — see next finding.

**Recommendation:** No bug, but the comment at line 375 ("if not set by focused block") implies `connection` can only be inherited from a term block, which is misleading. Clarify with a comment that connection is inherited from any focused block type.

---

### [MODERATE] `atoms.staticTabId` is always populated — but tab atom lookup can silently return null

**Evidence:** `global-atoms.ts:79` — `staticTabIdAtom` is initialized with `initOpts.tabId` at construction time and never changes. The atom always has a valid string value.

**BUT:** At `keymodel.ts:378-383`:
```ts
const activeTabId = globalStore.get(atoms.staticTabId);
const tabAtom = WOS.getWaveObjectAtom<Tab>(WOS.makeORef("tab", activeTabId));
const tabData = globalStore.get(tabAtom);
if (tabData?.meta?.["tab:connection"] != null) {
    termBlockDef.meta.connection = tabData.meta["tab:connection"];
}
```
If the tab object is not yet loaded in the wave object store (e.g., during startup or after tab switch), `tabData` will be null and the fallback silently does nothing. The `?.` operators protect against a crash but the block opens without the intended connection. This is a silent failure — no error is surfaced to the user.

**Recommendation:** Low risk in practice since `getDefaultNewBlockDef` is only called from keyboard handlers which run after the tab is fully loaded. No code change required, but add a comment documenting the assumption.

---

### [IMPORTANT] Race condition: tab meta can change between `getDefaultNewBlockDef` read and `createBlock` call

**Evidence:** `keymodel.ts:387-390`
```ts
async function handleCmdN() {
    const blockDef = getDefaultNewBlockDef();   // reads tab meta synchronously
    await createBlock(blockDef);                 // async — yields to event loop
}
```
Between the synchronous `getDefaultNewBlockDef()` call and the `await createBlock()`, the tab's `tab:connection` meta could be changed by the user (e.g., via the tab context menu). The new block would then inherit a stale connection value.

**Severity assessment:** IMPORTANT but low-frequency. The window is a single async yield (~microseconds). In practice, a user cannot change tab connection between pressing Cmd+N and the block creation completing. Acceptable risk.

**Recommendation:** No immediate fix required. Document the assumption if this becomes an issue.

---

### [IMPORTANT] SVG arc math: 100% value produces degenerate path (coincident start/end points)

**Evidence:** `sysinfo-dial.tsx:43-45`
```ts
const endAngle = START_ANGLE + (ARC_DEGREES * pct) / 100;
// At pct=100: endAngle = 135 + 270 = 405
const fgPath = pct > 0 ? arcPath(CENTER, CENTER, RADIUS, START_ANGLE, endAngle) : null;
```
At `pct = 100`, `endAngle = 405`. Inside `arcPath`:
- `startDeg = 135`, `endDeg = 405`
- `x1 = cx + r * cos(135°)`, `x2 = cx + r * cos(405°)` → `cos(405°) = cos(45°)`, `cos(135°) = -cos(45°)` — these are NOT coincident, so the path is valid.
- `largeArc = (405 - 135) > 180 ? 1 : 0` → `270 > 180` → `1` ✓

**100% is actually fine.** The background arc (bgPath) uses the same `START_ANGLE` to `START_ANGLE + 270`, which has the same calculation and is always shown as a reference track. No degenerate path.

**Edge case at exactly 50%:** `endAngle = 135 + 135 = 270`. `largeArc = (270 - 135) > 180 ? 1 : 0` → `135 > 180` → `0`. This is correct — a 135-degree arc is a minor arc (< 180°), so `largeArc = 0` is right.

**Edge case at 0%:** `fgPath` is explicitly set to `null` at line 45 (`pct > 0`), so no zero-length arc is rendered. Correct.

**Verdict:** Arc math is correct for all standard cases. No bug.

---

### [MODERATE] SVG arc math: `degToRad` uses standard math convention — SVG Y-axis is inverted

**Evidence:** `sysinfo-dial.tsx:15-17, 19-28`
```ts
function degToRad(deg: number): number {
    return (deg * Math.PI) / 180;
}
// x1 = cx + r * Math.cos(start)
// y1 = cy + r * Math.sin(start)
```
In SVG, the Y-axis points **downward**. Standard math sin/cos assumes Y points upward. This means the arc rotates **clockwise** as angles increase (because positive Y is down). For a dial starting at 135° (bottom-left): the arc sweeps clockwise through the bottom, which is the typical gauge direction.

**This is actually the intended behavior** for a progress dial. The visual result is correct: 0% starts at bottom-left (135°), fills clockwise, ends at bottom-right (405°/45°).

**Verdict:** No bug — inverted Y-axis is expected in SVG arc path usage.

---

### [IMPORTANT] `thresholdColor` does not guard against NaN/undefined/negative inputs

**Evidence:** `sysinfo-dial.tsx:30-34`
```ts
function thresholdColor(pct: number): string {
    if (pct >= 80) return "#ef4444";
    if (pct >= 50) return "#eab308";
    return "#10b981";
}
```
- `NaN >= 80` → `false`, `NaN >= 50` → `false` → returns `"#10b981"` (green). Silent wrong color.
- Negative values: `-1 >= 80` → `false` → returns green. Visually neutral, acceptable.
- `undefined` coerced to number: same as NaN.

**However**, `thresholdColor` is only called at `sysinfo-dial.tsx:46`:
```ts
const color = thresholdColor(pct);
```
And `pct` is computed at line 42:
```ts
const pct = value != null ? Math.min(100, Math.max(0, value)) : 0;
```
The `Math.min(100, Math.max(0, value))` call clamps to `[0, 100]` **only if `value` is a finite number**. If `value` is `NaN` (possible if the server sends a NaN float), `Math.max(0, NaN)` → `NaN`, `Math.min(100, NaN)` → `NaN`. Then `pct = NaN`, and `thresholdColor(NaN)` silently returns green.

**More critically**, `displayVal` at line 47:
```ts
const displayVal = value != null ? `${Math.round(pct)}%` : "--";
```
If `value = NaN`, `value != null` is `true`, so `displayVal = "NaN%"` — this is **visible to the user**.

**Recommendation:** Add NaN guard in `Dial`:
```ts
const pct = value != null && isFinite(value) ? Math.min(100, Math.max(0, value)) : 0;
const displayVal = value != null && isFinite(value) ? `${Math.round(pct)}%` : "--";
```

---

### [IMPORTANT] `sysinfo.go`: `getDiskData` and `getNetData` use the SAME `diskMu` mutex and read `prevTs` independently — introduces a stale-read window

**Evidence:** `sysinfo.go:73-84` (getDiskData) and `sysinfo.go:99-110` (getNetData)

Both functions:
1. Lock `diskMu`
2. Read `prevTs`
3. Compute their delta using `now.Sub(prevTs).Seconds()`
4. Update their own prev-counters
5. Unlock `diskMu`

Then `generateSingleServerData` calls them sequentially:
```go
getDiskData(values)   // locks/unlocks diskMu, reads prevTs
getNetData(values)    // locks/unlocks diskMu, reads prevTs
diskMu.Lock()
prevTs = now          // updates prevTs AFTER both have run
diskMu.Unlock()
```

**The problem:** `getDiskData` runs, reads `prevTs`, releases the lock. Then `getNetData` runs, reads the **same unchanged `prevTs`** (correct — `prevTs` hasn't been updated yet). Both use `now` captured at the start of `generateSingleServerData` (line 152). This is actually **correct** — both compute deltas relative to the previous tick's timestamp.

**However**, `now` is captured ONCE at the start of `generateSingleServerData` but the actual time when each sub-function runs differs slightly. The disk I/O counters and net I/O counters are read at different wall-clock times but both compute rates using the same `now`. This creates minor inaccuracy in rates (~milliseconds), acceptable in practice.

**Verdict:** Logic is correct. Minor timing imprecision is acceptable.

---

### [CRITICAL] `sysinfo.go`: Integer underflow if `totalRead < prevDiskRead` (counter reset or disk removal)

**Evidence:** `sysinfo.go:78`
```go
values[wshrpc.TimeSeries_Disk+":read"] = float64(totalRead-prevDiskRead) / elapsed / BYTES_PER_MB
```
`totalRead` and `prevDiskRead` are `uint64`. If a disk is removed between ticks, `disk.IOCounters()` returns a different set of disks, so `totalRead` could be less than `prevDiskRead`. `uint64` subtraction wraps around (unsigned underflow), producing a massive positive value (~18 exabytes/s).

Same issue at `sysinfo.go:79` for write, `sysinfo.go:104-105` for net rx/tx.

**The disk set mismatch** is explicitly called out in the review questions: `disk.IOCounters()` returns whatever disks are currently present. If a USB drive is ejected, `totalRead` drops, causing wrap-around.

Network counters (`gopsnet.IOCounters(false)` with `pernic=false`) return an aggregate, so removal of a network interface would reduce the aggregate similarly.

**Recommendation:**
```go
if totalRead >= prevDiskRead {
    values[wshrpc.TimeSeries_Disk+":read"] = float64(totalRead-prevDiskRead) / elapsed / BYTES_PER_MB
}
if totalWrite >= prevDiskWrite {
    values[wshrpc.TimeSeries_Disk+":write"] = float64(totalWrite-prevDiskWrite) / elapsed / BYTES_PER_MB
}
```
Apply the same guard to net rx/tx at lines 104-105.

---

### [IMPORTANT] `sysinfo.go`: `getNetData` incorrectly uses `diskMu` — net state not protected from concurrent access

**Evidence:** `sysinfo.go:99-110`
```go
func getNetData(values map[string]float64) {
    ...
    diskMu.Lock()   // named "diskMu" but guards net state too
    ...
    prevNetRx = agg.BytesRecv
    prevNetTx = agg.BytesSent
    diskMu.Unlock()
```
The mutex is named `diskMu` but is reused to protect `prevNetRx`/`prevNetTx`. This is correct functionally (shared mutex works), but it creates a false impression that net state is unprotected when reading the code. Since `RunSysInfoLoop` is a single goroutine, there is no actual concurrency risk here — this is purely a naming/clarity issue.

**Verdict:** No bug, but rename `diskMu` to `ioMu` or `stateMu` for clarity.

---

### [IMPORTANT] `sysinfo.go`: First tick correctly omits rate values — but `prevTs` is updated to `now` captured BEFORE sub-functions run

**Evidence:** `sysinfo.go:151-161`
```go
func generateSingleServerData(...) {
    now := time.Now()      // captured here
    ...
    getDiskData(values)    // runs later, may take 10-50ms
    getNetData(values)
    diskMu.Lock()
    prevTs = now           // stored as "when this tick started"
    diskMu.Unlock()
```
`prevTs` is set to the timestamp captured at the **beginning** of the function, not when the I/O counters were actually read. If `getCpuData` (which calls `cpu.Percent(0, false)` — a blocking call that returns immediately with cached data) takes time, the `now` value used for the delta is slightly stale.

More precisely: `cpu.Percent(0, false)` with interval=0 returns the cached percent immediately. `getDiskData` and `getNetData` are fast gopsutil calls. This is not a real issue in practice.

**First tick behavior:** On first call, `prevTs.IsZero()` is true, rates are omitted (lines 75-81, 101-107). `prevTs` is set. Second tick computes deltas. This is correct — avoids a giant spike on startup.

**Verdict:** First-tick behavior is correct. Timing imprecision is negligible.

---

### [IMPORTANT] `tabcontextmenu.ts`: `ConnListCommand` is async — context menu shows with stale/empty connection list if promise hasn't resolved

**Evidence:** `tab.tsx:280-284`
```ts
const connListPromise = RpcApi.ConnListCommand(TabRpcClient, { timeout: 2000 }).catch(() => [] as string[]);
connListPromise.then((connList) => {
    const menu = buildTabContextMenu(id, renameRef, onClose, env, connList);
    env.showContextMenu(menu, e);
});
```
The `showContextMenu` call is correctly deferred until the promise resolves — the menu is NOT shown until `connList` is available. **This is correct behavior.** The 2000ms timeout with `.catch(() => [])` ensures the menu always appears even if the RPC fails, just without connection options.

**However**, the `e` (mouse event) object is captured at right-click time. Some implementations of `showContextMenu` use `e.clientX`/`e.clientY` for positioning. If 2 seconds elapse before the menu shows (worst case — timeout), the user has likely moved their mouse. The menu position will be based on the original click coordinates.

**Verdict:** Not a bug — positional stale event is the same as every context menu implementation. The async ordering is correct.

---

### [MODERATE] `tabcontextmenu.ts`: `SetMetaCommand` failures are silently swallowed via `fireAndForget`

**Evidence:** `tabcontextmenu.ts:62-65, 72-74, 85-87, 93-96`
```ts
click: () =>
    fireAndForget(() =>
        env.rpc.SetMetaCommand(TabRpcClient, { oref: tabORef, meta: { "tab:flagcolor": null } })
    ),
```
`fireAndForget` suppresses errors. If `SetMetaCommand` fails (network issue, server error), the UI may show the selection as checked but the backend state is not updated — user sees a stale/incorrect state with no feedback.

**Recommendation:** Accept as a known trade-off for non-critical UI operations, or add a toast notification on error. The pattern is consistent with the rest of the codebase.

---

### [MODERATE] `wshrpctypes.go`: `TimeSeries_Disk` and `TimeSeries_Net` are used via constants — not hardcoded strings

**Evidence:** `wshrpctypes.go:424-428` defines the constants. `sysinfo.go:43, 50, 78-79, 88-89, 104-105, 111-112, 136-138, 145-147` all use `wshrpc.TimeSeries_*` constants, not hardcoded strings.

**Verdict:** No issue. Constants are correctly defined and used throughout.

---

## Summary

| # | Severity | Issue | File:Lines |
|---|----------|-------|-----------|
| 1 | CRITICAL | uint64 underflow on disk/net counter reset (disk removal, interface change) | sysinfo.go:78-79, 104-105 |
| 2 | IMPORTANT | NaN value from server causes "NaN%" display in dial | sysinfo-dial.tsx:42-47 |
| 3 | IMPORTANT | Connection inheritance comment is misleading (non-term blocks DO inherit connection) | keymodel.ts:371-374 |
| 4 | IMPORTANT | diskMu misnamed — guards net state too, misleads future readers | sysinfo.go:29, 99-110 |
| 5 | IMPORTANT | Race between getDefaultNewBlockDef read and createBlock async call (acceptable risk) | keymodel.ts:387-390 |
| 6 | MODERATE | SetMetaCommand failures silently swallowed, no user feedback | tabcontextmenu.ts:62-96 |
| 7 | MODERATE | staticTabId fallback: tabData can be null if object not yet loaded (silent failure) | keymodel.ts:377-383 |

**Arc math (sysinfo-dial.tsx):** Correct for all cases including 0%, 50%, 100%.
**TimeSeries constants:** Correctly used via wshrpctypes.go constants, no hardcoded strings.
**ConnListCommand async ordering:** Correct — menu deferred until promise resolves.
**First-tick delta omission:** Correct — rates skipped when prevTs.IsZero().
