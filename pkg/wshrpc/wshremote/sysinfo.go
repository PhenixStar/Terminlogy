// Copyright 2025, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

package wshremote

import (
	"log"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/disk"
	"github.com/shirou/gopsutil/v4/mem"
	gopsnet "github.com/shirou/gopsutil/v4/net"
	"github.com/wavetermdev/waveterm/pkg/wps"
	"github.com/wavetermdev/waveterm/pkg/wshrpc"
	"github.com/wavetermdev/waveterm/pkg/wshrpc/wshclient"
	"github.com/wavetermdev/waveterm/pkg/wshutil"
)

const BYTES_PER_GB = 1073741824
const BYTES_PER_MB = 1048576

// delta state for disk/net I/O rates + GPU tick counter
var (
	diskMu        sync.Mutex
	prevDiskRead  uint64
	prevDiskWrite uint64
	prevNetRx     uint64
	prevNetTx     uint64
	prevTs        time.Time
	gpuTickCount  int
)

func getCpuData(values map[string]float64) {
	percentArr, err := cpu.Percent(0, false)
	if err != nil {
		return
	}
	if len(percentArr) > 0 {
		values[wshrpc.TimeSeries_Cpu] = percentArr[0]
	}
	percentArr, err = cpu.Percent(0, true)
	if err != nil {
		return
	}
	for idx, percent := range percentArr {
		values[wshrpc.TimeSeries_Cpu+":"+strconv.Itoa(idx)] = percent
	}
}

func getMemData(values map[string]float64) {
	memData, err := mem.VirtualMemory()
	if err != nil {
		return
	}
	values["mem:total"] = float64(memData.Total) / BYTES_PER_GB
	values["mem:available"] = float64(memData.Available) / BYTES_PER_GB
	values["mem:used"] = float64(memData.Used) / BYTES_PER_GB
	values["mem:free"] = float64(memData.Free) / BYTES_PER_GB
}

func getDiskData(values map[string]float64) {
	counters, err := disk.IOCounters()
	if err == nil {
		var totalRead, totalWrite uint64
		for _, c := range counters {
			totalRead += c.ReadBytes
			totalWrite += c.WriteBytes
		}
		diskMu.Lock()
		if !prevTs.IsZero() && totalRead >= prevDiskRead && totalWrite >= prevDiskWrite {
			elapsed := time.Since(prevTs).Seconds()
			if elapsed > 0 {
				values[wshrpc.TimeSeries_Disk+":read"] = float64(totalRead-prevDiskRead) / elapsed / BYTES_PER_MB
				values[wshrpc.TimeSeries_Disk+":write"] = float64(totalWrite-prevDiskWrite) / elapsed / BYTES_PER_MB
			}
		}
		prevDiskRead = totalRead
		prevDiskWrite = totalWrite
		diskMu.Unlock()
	}
	usage, err := disk.Usage("/")
	if err == nil {
		values[wshrpc.TimeSeries_Disk+":used"] = float64(usage.Used) / BYTES_PER_GB
		values[wshrpc.TimeSeries_Disk+":total"] = float64(usage.Total) / BYTES_PER_GB
	}
}

func getNetData(values map[string]float64) {
	counters, err := gopsnet.IOCounters(false)
	if err != nil || len(counters) == 0 {
		return
	}
	agg := counters[0]
	diskMu.Lock()
	if !prevTs.IsZero() && agg.BytesRecv >= prevNetRx && agg.BytesSent >= prevNetTx {
		elapsed := time.Since(prevTs).Seconds()
		if elapsed > 0 {
			values[wshrpc.TimeSeries_Net+":rx"] = float64(agg.BytesRecv-prevNetRx) / elapsed / BYTES_PER_MB
			values[wshrpc.TimeSeries_Net+":tx"] = float64(agg.BytesSent-prevNetTx) / elapsed / BYTES_PER_MB
		}
	}
	prevNetRx = agg.BytesRecv
	prevNetTx = agg.BytesSent
	diskMu.Unlock()
	values[wshrpc.TimeSeries_Net+":rx:total"] = float64(agg.BytesRecv) / BYTES_PER_GB
	values[wshrpc.TimeSeries_Net+":tx:total"] = float64(agg.BytesSent) / BYTES_PER_GB
}

func getGpuData(values map[string]float64) {
	out, err := exec.Command("nvidia-smi",
		"--query-gpu=utilization.gpu,memory.used,memory.total",
		"--format=csv,noheader,nounits").Output()
	if err != nil {
		return
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	var totalUtil, totalMemUsed, totalMemTotal float64
	gpuCount := 0
	for idx, line := range lines {
		parts := strings.Split(line, ", ")
		if len(parts) < 3 {
			continue
		}
		util, err1 := strconv.ParseFloat(strings.TrimSpace(parts[0]), 64)
		memUsed, err2 := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
		memTotal, err3 := strconv.ParseFloat(strings.TrimSpace(parts[2]), 64)
		if err1 != nil || err2 != nil || err3 != nil {
			continue
		}
		values[wshrpc.TimeSeries_Gpu+":"+strconv.Itoa(idx)] = util
		values[wshrpc.TimeSeries_GpuMem+":"+strconv.Itoa(idx)+":used"] = memUsed / 1024 // MiB to GiB
		values[wshrpc.TimeSeries_GpuMem+":"+strconv.Itoa(idx)+":total"] = memTotal / 1024
		totalUtil += util
		totalMemUsed += memUsed
		totalMemTotal += memTotal
		gpuCount++
	}
	if gpuCount > 0 {
		values[wshrpc.TimeSeries_Gpu] = totalUtil / float64(gpuCount)
		values[wshrpc.TimeSeries_GpuMem+":used"] = totalMemUsed / 1024
		values[wshrpc.TimeSeries_GpuMem+":total"] = totalMemTotal / 1024
	}
}

func generateSingleServerData(client *wshutil.WshRpc, connName string) {
	now := time.Now()
	values := make(map[string]float64)
	getCpuData(values)
	getMemData(values)
	getDiskData(values)
	getNetData(values)
	// GPU data is expensive (exec nvidia-smi) — collect every 5 ticks instead of every tick
	diskMu.Lock()
	gpuTickCount++
	prevTs = now
	diskMu.Unlock()
	if gpuTickCount%5 == 1 {
		getGpuData(values)
	}
	tsData := wshrpc.TimeSeriesData{Ts: now.UnixMilli(), Values: values}
	event := wps.WaveEvent{
		Event:   wps.Event_SysInfo,
		Scopes:  []string{connName},
		Data:    tsData,
		Persist: 1024,
	}
	wshclient.EventPublishCommand(client, event, &wshrpc.RpcOpts{NoResponse: true})
}

func RunSysInfoLoop(client *wshutil.WshRpc, connName string) {
	defer func() {
		log.Printf("sysinfo loop ended conn:%s\n", connName)
	}()
	for {
		generateSingleServerData(client, connName)
		time.Sleep(1 * time.Second)
	}
}
