// Copyright 2025, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

package wshremote

import (
	"log"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/mem"
	"github.com/wavetermdev/waveterm/pkg/wps"
	"github.com/wavetermdev/waveterm/pkg/wshrpc"
	"github.com/wavetermdev/waveterm/pkg/wshrpc/wshclient"
	"github.com/wavetermdev/waveterm/pkg/wshutil"
)

const BYTES_PER_GB = 1073741824

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
	getGpuData(values)
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
