//go:build windows

// Windows mount actions open the sync-root folder in Explorer.
package mount

import (
	"fmt"
	"os/exec"
)

func openMountPath(mountPath string) error {
	output, err := exec.Command("explorer.exe", mountPath).CombinedOutput()
	if err != nil {
		return fmt.Errorf("open mount path: %w: %s", err, string(output))
	}
	return nil
}
