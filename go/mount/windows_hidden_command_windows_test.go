//go:build windows

// Windows hidden-command tests keep mount lifecycle helpers free of console flashes.
package mount

import (
	"testing"

	"golang.org/x/sys/windows"
)

func TestHiddenWindowsCommandDisablesConsoleWindow(t *testing.T) {
	cmd := hiddenWindowsCommand("cmd.exe", "/d", "/c", "exit", "0")
	attrs := cmd.SysProcAttr
	if attrs == nil || !attrs.HideWindow {
		t.Fatal("hidden command must set HideWindow")
	}
	if attrs.CreationFlags&windows.CREATE_NO_WINDOW == 0 {
		t.Fatal("hidden command must set CREATE_NO_WINDOW")
	}
	if err := cmd.Run(); err != nil {
		t.Fatalf("run hidden command: %v", err)
	}
}
