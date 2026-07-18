// The crash reporter writes diagnostics after the Windows launcher observes an
// abnormal app exit, then offers to reveal the report for user submission.
package main

import (
	"flag"
	"fmt"
	"os"
)

func main() {
	executable := flag.String("exe", "", "path to the monitored application")
	pid := flag.Int("pid", 0, "process ID of the monitored application")
	exitCode := flag.Uint64("exit-code", 0, "unsigned Windows process exit code")
	launchError := flag.Uint64("launch-error", 0, "Windows CreateProcess error code")
	flag.Parse()

	context := crashContext{
		Executable:  *executable,
		PID:         *pid,
		ExitCode:    uint32(*exitCode),
		LaunchError: uint32(*launchError),
	}
	reportPath, err := writeCrashReport(context)
	if err != nil {
		notifyReportFailure(fmt.Sprintf("生成崩溃报告失败：%v", err))
		os.Exit(1)
	}
	notifyCrashReport(reportPath, context)
}
