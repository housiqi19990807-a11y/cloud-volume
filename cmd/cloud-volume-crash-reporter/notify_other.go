//go:build !windows

package main

import "runtime"

// Portable stubs keep repository-wide tests working on non-Windows hosts.
func platformSystemDescription() string { return runtime.GOOS }

func notifyCrashReport(reportPath string, context crashContext) {}

func notifyReportFailure(message string) {}
