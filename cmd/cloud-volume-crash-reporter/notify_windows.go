//go:build windows

package main

import (
	"fmt"
	"os/exec"

	"golang.org/x/sys/windows"
)

const (
	messageBoxYesNo         = 0x00000004
	messageBoxIconError     = 0x00000010
	messageBoxSetForeground = 0x00010000
	messageBoxTopmost       = 0x00040000
	messageBoxResultYes     = 6
)

func platformSystemDescription() string {
	version := windows.RtlGetVersion()
	return fmt.Sprintf("Windows %d.%d build %d",
		version.MajorVersion, version.MinorVersion, version.BuildNumber)
}

func notifyCrashReport(reportPath string, context crashContext) {
	detail := "云卷未能正常启动或已异常退出。"
	if context.LaunchError != 0 {
		detail = "Windows 未能创建云卷主进程。"
	}
	message := fmt.Sprintf(
		"%s\n\n崩溃报告已保存到：\n%s\n\n报告可能包含本地文件路径，请检查后提交给开发者。\n\n是否打开报告所在位置？",
		detail, reportPath)
	result, _ := windows.MessageBox(
		0,
		windows.StringToUTF16Ptr(message),
		windows.StringToUTF16Ptr("云卷启动失败"),
		messageBoxYesNo|messageBoxIconError|messageBoxSetForeground|messageBoxTopmost,
	)
	if result == messageBoxResultYes {
		_ = exec.Command("explorer.exe", "/select,"+reportPath).Start()
	}
}

func notifyReportFailure(message string) {
	_, _ = windows.MessageBox(
		0,
		windows.StringToUTF16Ptr(message),
		windows.StringToUTF16Ptr("云卷启动失败"),
		messageBoxIconError|messageBoxSetForeground|messageBoxTopmost,
	)
}
