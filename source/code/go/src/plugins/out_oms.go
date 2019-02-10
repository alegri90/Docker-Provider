package main

import (
	"github.com/fluent/fluent-bit-go/output"
	"github.com/Microsoft/ApplicationInsights-Go/appinsights"
)
import (
	"C"
	"strings"
	"unsafe"
	"os"
)

//export FLBPluginRegister
func FLBPluginRegister(ctx unsafe.Pointer) int {
	return output.FLBPluginRegister(ctx, "oms", "OMS GO!")
}

//export FLBPluginInit
// (fluentbit will call this)
// ctx (context) pointer to fluentbit context (state/ c code)
func FLBPluginInit(ctx unsafe.Pointer) int {
	Log("Initializing out_oms go plugin for fluentbit")
	agentVersion := os.Getenv("AGENT_VERSION")
	InitializePlugin(ContainerLogPluginConfFilePath, agentVersion)
	enableTelemetry := output.FLBPluginConfigKey(ctx, "EnableTelemetry")
	if strings.Compare(strings.ToLower(enableTelemetry), "true") == 0 {
		telemetryPushInterval := output.FLBPluginConfigKey(ctx, "TelemetryPushIntervalSeconds")
		go SendContainerLogPluginMetrics(telemetryPushInterval)
	} else {
		Log("Telemetry is not enabled for the plugin %s \n", output.FLBPluginConfigKey(ctx, "Name"))
		return output.FLB_OK
	}
	return output.FLB_OK
}

//export FLBPluginFlush
func FLBPluginFlush(data unsafe.Pointer, length C.int, tag *C.char) int {
	var ret int
	var record map[interface{}]interface{}
	var records []map[interface{}]interface{}

	// Create Fluent Bit decoder
	dec := output.NewDecoder(data, int(length))

	// Iterate Records
	for {
		// Extract Record
		ret, _, record = output.GetRecord(dec)
		if ret != 0 {
			break
		}
		records = append(records, record)
	}

	incomingTag := strings.ToLower(C.GoString(tag))
	if strings.Contains(incomingTag, "oms.container.log.flbplugin") {
		return PushToAppInsightsTraces(records, appinsights.Information, incomingTag)
	} else if strings.Contains(incomingTag, "oms.container.log.telegraf.err") {
		return PushToAppInsightsTraces(records, appinsights.Error, incomingTag)
	}

	return PostDataHelper(records)
}

// FLBPluginExit exits the plugin
func FLBPluginExit() int {
	ContainerLogTelemetryTicker.Stop()
	KubeSystemContainersRefreshTicker.Stop()
	ContainerImageNameRefreshTicker.Stop()
	return output.FLB_OK
}

func main() {
}
