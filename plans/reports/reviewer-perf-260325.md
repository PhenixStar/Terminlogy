# Performance Review — PhenixStar/waveterm Fork
**Date:** 2026-03-25
**Scope:** sysinfo.go, sysinfo.tsx, sysinfo-dial.tsx, keymodel.ts, tabcontextmenu.ts / tab.tsx

---

## Findings

### [CRITICAL] nvidia-smi spawned as subprocess every 1 second

**Evidence:** `sysinfo.go:116-118` — `exec.Command("nvidia-smi", ...)` called unconditionally inside `getGpuData`, which is called from `generateSingleServerData` on every `RunSysInfoLoop` tick (1s interval, `sysinfo.go:177`).

**Impact:** `exec.Command` forks a new process each tick. Process spawn overhead on Linux is ~2-5ms per call but nvidia-smi itself adds ~50-150ms of NVML initialization latency. On a machine with multiple GPUs this blocks the goroutine for the full duration of the subprocess. Because `generateSingleServerData` is synchronous, the entire sysinfo payload (CPU, mem, disk, net, GPU) is delayed by nvidia-smi's latency every second. Under sustained load (DGX with 8 GPUs) this can drift the 1s cadence to 1.15s+ and cause bursts of delayed events.

**Recommendation:** Run GPU polling in a separate goroutine with its own ticker at a coarser interval (e.g., 2-5s for GPU — utilization is slow-moving). Cache the last result and serve it from memory on 1s ticks. Alternatively, use the NVML Go bindings (e.g., `github.com/NVIDIA/go-nvml`) to avoid process spawning entirely.

---

### [CRITICAL] Race condition: prevTs written outside diskMu after getNetData reads it

**Evidence:** `sysinfo.go:158-161` — `generateSingleServerData` calls `getDiskData` (acquires `diskMu`, reads `prevTs`, releases), then `getNetData` (acquires `diskMu`, reads `prevTs`, releases), then finally writes `prevTs = now` under `diskMu`. This is sequential within one goroutine so there is no data race per se — but the design is fragile: `prevTs` is used as a shared timestamp for **both** disk and net rate calculations, and both functions capture `time.Now()` independently into their own local `now`. This means disk elapsed time is measured from one moment and net elapsed from a slightly later moment, yet both are compared against the same `prevTs`. The computed rates will be subtly incorrect when the two calls are separated by non-trivial time (e.g., when nvidia-smi is slow). If `getGpuData` takes 100ms between the disk and net calls, net rates will use a ~100ms shorter elapsed window than disk rates, overstating net throughput by up to ~10%.

**Recommendation:** Capture `time.Now()` once at the top of `generateSingleServerData` and pass it to both `getDiskData` and `getNetData` as a parameter. This eliminates the skew and also avoids two separate `time.Now()` syscalls.

---

### [IMPORTANT] diskMu guards net state — mutex name is misleading and scope is too broad

**Evidence:** `sysinfo.go:29` — `diskMu` is declared as the mutex for disk delta state, but `getNetData` (`sysinfo.go:99, 110`) also acquires it to protect `prevNetRx`, `prevNetTx`, and `prevTs`. The mutex now serializes disk and net reads unnecessarily. Although `generateSingleServerData` calls them sequentially (so contention is not an issue now), if either function is ever moved to a goroutine the shared mutex will cause disk reads to block net reads and vice versa.

**Recommendation:** Split into two separate mutexes — `diskMu` for disk state and `netMu` for net state. Rename to match their actual scope. `prevTs` should be a single field passed as argument (see above) rather than shared mutable state.

---

### [IMPORTANT] addContinuousDataAtom mutates array before filtering — GC pressure every second

**Evidence:** `sysinfo.tsx:278` — `data.push(newPoint)` mutates the existing array in place before calling `.filter()` which allocates a new array. This pattern runs on every 1s event tick. The original array is the Jotai atom's current value, so mutating it in place breaks Jotai's reference-equality change detection. If `data` happens to already be `targetLen` long, the push grows the array and filter shrinks it — creating two heap allocations per tick. On the hot path this generates continuous GC pressure.

**Recommendation:**
```ts
const newData = [...data, newPoint].filter((item) => item.ts >= cutoffTs);
set(this.dataAtom, newData);
```
Or use a circular buffer / deque with a fixed capacity to avoid allocation entirely on steady-state ticks.

---

### [IMPORTANT] ConnListCommand RPC called on every right-click with 2s timeout blocking menu display

**Evidence:** `tab.tsx:280` — `RpcApi.ConnListCommand(TabRpcClient, { timeout: 2000 })` is fired inside `handleContextMenu` on every right-click. The menu does not appear until this promise resolves. On a slow or unreachable remote host, this adds up to 2 full seconds of latency before the context menu opens. The conn list is only used to populate the "Set Tab Connection" submenu.

**Recommendation:** Cache the connection list with a short TTL (e.g., 30s) at the workspace level and refresh it lazily in the background. On right-click, use the cached value immediately so the menu is instant. The background refresh can update the menu if it's still open. Alternatively, open the menu immediately with a loading spinner in the connection submenu and populate it asynchronously.

---

### [MODERATE] DefaultPlotMeta built via imperative module-level loops — 70+ entries on every module load

**Evidence:** `sysinfo.tsx:123-156` — Three `for` loops run at module load time to populate `DefaultPlotMeta` for 32 CPU cores, 8 GPUs, and associated memory keys (up to 70+ entries). Each iteration allocates a new meta object via `defaultCpuMeta`/`defaultGpuMeta`/`defaultGpuMemMeta`. This runs once at import and the object is static, so the runtime cost is paid only once. However, this creates a large object that is spread into a `Map` on every `SysinfoViewModel` construction (`sysinfo.tsx:285`). With multiple sysinfo blocks open, each spawns its own Map copy of ~70 entries.

**Recommendation:** The `plotMetaAtom` wrapping `DefaultPlotMeta` as a Map is fine for mutation support, but if the meta is never mutated per-block, a single shared Map at module level avoids redundant Map construction. If per-block customization is needed, initialize lazily on first write.

---

### [MODERATE] SysinfoDials re-renders every second with no memoization of stable values

**Evidence:** `sysinfo-dial.tsx:91-114` — `SysinfoDials` is a plain `React.FC` (no `React.memo`). It receives `dataItem` (a new object reference every second from Jotai atom updates) and `plotMeta` (a Map). On every 1s data push, `SysinfoViewInner` re-renders and passes a new `dataItem` reference down, triggering a full re-render of `SysinfoDials` and all four `Dial` children, even when the values have not changed numerically (e.g., GPU utilization stuck at 0%).

Each `Dial` call recomputes `arcPath` (two trig operations, string construction), `thresholdColor`, and re-renders SVG paths and text. At 1 Hz with 4 dials this is 4 SVG subtree reconciliations per second minimum.

**Recommendation:** Wrap `SysinfoDials` and `Dial` in `React.memo`. For `Dial`, compare `value` numerically. This eliminates re-renders for stable values without changing behavior.

---

### [MODERATE] SingleLinePlot rebuilds full Observable Plot on every dimension or data change

**Evidence:** `sysinfo.tsx:596-608, 610-617` — `Plot.plot(...)` is called unconditionally in the render body, creating a new SVG DOM tree on every render. The `useEffect` removes the old plot and appends the new one. Since `plotData` changes every second (new atom reference), this triggers `Plot.plot()` rebuild every second per chart panel. On "All Metrics" view (7 plots), this is 7 full plot reconstructions per second.

**Recommendation:** Memoize the `Plot.plot()` call with `React.useMemo`, keyed on `plotData`, `plotWidth`, `plotHeight`, `yval`, and domain bounds. Only rebuild when dimensions or data actually change. An incremental approach (update data in place via D3 selections) would be more efficient but requires more invasive changes.

---

### [MODERATE] getDefaultNewBlockDef performs 4 synchronous globalStore.get calls on every Cmd+N / split

**Evidence:** `keymodel.ts:344-385` — The function calls `globalStore.get` 4-6 times synchronously: settings key atom, layout model's focusedNode, block atom, tab atom. Each `globalStore.get` traverses the Jotai atom dependency graph. This is not a hot path (user-triggered action) so the impact is low, but the pattern of reading multiple atoms imperatively instead of composing a single derived atom means there's no caching between the reads and each call pays full traversal cost.

**Recommendation:** Low priority — acceptable for a user-initiated action. If this function is ever called more frequently (e.g., in a tooltip or preview scenario), extract into a derived Jotai atom that Jotai can cache.

---

### [LOW] cpu.Percent called twice per tick with 0 interval — two blocking syscalls

**Evidence:** `sysinfo.go:38-51` — `cpu.Percent(0, false)` is called first for aggregate CPU, then `cpu.Percent(0, true)` for per-core. Both use `interval=0` (return delta since last call) which means the second call's delta is measured from the first call's read, not from the previous tick. This is semantically incorrect: the aggregate and per-core values come from different measurement windows. Additionally, calling the per-core version after the aggregate means the aggregate reading captures a slightly different time window.

**Recommendation:** Call only `cpu.Percent(0, true)` (per-core), then compute the aggregate as the mean of per-core values client-side. This halves the syscall count and uses a consistent measurement window.

---

### [LOW] console.log left in production path

**Evidence:** `sysinfo.tsx:478` — `console.log("subscribe to sysinfo", connName)` fires every time the effect re-runs (on every `connName` change and initial mount). In a multi-block sysinfo scenario, this logs every subscription event to the DevTools console.

**Recommendation:** Remove or gate behind a debug flag.

---

## Summary Table

| Severity | Finding | File:Line |
|---|---|---|
| CRITICAL | nvidia-smi subprocess every 1s | sysinfo.go:116 |
| CRITICAL | prevTs timing skew between disk and net rate calculations | sysinfo.go:73-110 |
| IMPORTANT | diskMu guards net state — misleading scope, fragile if parallelized | sysinfo.go:29,99 |
| IMPORTANT | addContinuousDataAtom mutates atom array in place — GC pressure + broken ref equality | sysinfo.tsx:278 |
| IMPORTANT | ConnListCommand RPC on every right-click, 2s timeout blocks menu | tab.tsx:280 |
| MODERATE | DefaultPlotMeta Map copy per ViewModel instance | sysinfo.tsx:285 |
| MODERATE | SysinfoDials/Dial not memoized — 4 SVG re-renders/sec for unchanged values | sysinfo-dial.tsx:91 |
| MODERATE | SingleLinePlot rebuilds full Plot.plot() every second | sysinfo.tsx:596 |
| MODERATE | getDefaultNewBlockDef: 4+ synchronous globalStore.get traversals | keymodel.ts:344 |
| LOW | cpu.Percent called twice — two syscalls, inconsistent windows | sysinfo.go:38-51 |
| LOW | console.log in sysinfo subscription effect | sysinfo.tsx:478 |

## Priority Fixes

1. **nvidia-smi** — coarser interval + NVML bindings or goroutine cache (eliminates 50-150ms blocking per tick)
2. **ConnListCommand on right-click** — add conn list cache (eliminates 0-2s menu delay)
3. **addContinuousDataAtom array mutation** — fix ref equality bug + GC pressure
4. **prevTs skew** — pass `time.Now()` as parameter to both getDiskData/getNetData
5. **SysinfoDials React.memo** — eliminates 4 unnecessary SVG re-renders/sec at zero cost
