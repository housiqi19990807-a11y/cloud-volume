//go:build !windows

// Non-Windows dispatch tests ensure Windows-only WinFsp APIs stay unavailable.
package main

import (
	"strings"
	"testing"
)

func TestWindowsWinFspBridgeMethodsAreNotExposed(t *testing.T) {
	for _, method := range []string{
		"list_windows_winfsp_available",
		"install_windows_winfsp",
	} {
		t.Run(method, func(t *testing.T) {
			_, err := invokeBridgeMethod(method, nil)
			if err == nil || !strings.Contains(err.Error(), "unsupported bridge method") {
				t.Fatalf("invokeBridgeMethod(%q) error = %v, want unsupported method", method, err)
			}
		})
	}
}
