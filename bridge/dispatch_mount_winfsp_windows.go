//go:build windows

// Windows-only WinFsp bridge dispatch keeps driver APIs out of other desktop builds.
package main

import (
	"log"

	bucketmount "remote-storage/go/mount"
)

func invokeWindowsWinFspBridgeMethod(method string) (any, bool, error) {
	switch method {
	case "list_windows_winfsp_available":
		return map[string]any{
			"available": bucketmount.WindowsWinFspAvailable(),
		}, true, nil
	case "install_windows_winfsp":
		log.Printf("[bridge/mount] install windows winfsp")
		if err := bucketmount.InstallWindowsWinFsp(); err != nil {
			return nil, true, err
		}
		return map[string]any{
			"ok":        true,
			"available": bucketmount.WindowsWinFspAvailable(),
		}, true, nil
	default:
		return nil, false, nil
	}
}
