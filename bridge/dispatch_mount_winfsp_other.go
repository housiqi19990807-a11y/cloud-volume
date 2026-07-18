//go:build !windows

// Non-Windows bridge builds do not expose WinFsp-specific methods.
package main

func invokeWindowsWinFspBridgeMethod(string) (any, bool, error) {
	return nil, false, nil
}
