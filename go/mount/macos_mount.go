// macOS mount helpers wrap system WebDAV mounting, unmounting, and Finder opening.
package mount

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type unmountCommand struct {
	name string
	args []string
}

func (s *mountSession) start() error {
	server, serverURL, port, err := startWebDAVServer(s.access, s.mountName)
	if err != nil {
		return err
	}
	s.server = server
	s.serverURL = serverURL
	s.port = port

	mountPath, err := mountWebDAV(serverURL)
	if err != nil {
		s.lastError = err.Error()
		return err
	}
	s.mountPath = mountPath
	s.mountTarget = mountPath
	s.mounted = true
	return nil
}

func (s *mountSession) stop() error {
	var mountErr error
	if s.mounted && s.mountTarget != "" {
		active, err := isWebDAVMountActive(s.mountTarget)
		if err != nil {
			mountErr = err
		} else if active {
			mountErr = unmountWebDAV(s.mountTarget)
		}
		s.mounted = false
	}
	serverErr := error(nil)
	if s.server != nil {
		serverErr = s.server.stop()
	}
	accessErr := error(nil)
	if s.access != nil {
		accessErr = s.access.close()
	}
	if mountErr != nil {
		s.lastError = mountErr.Error()
		return mountErr
	}
	if serverErr != nil {
		s.lastError = serverErr.Error()
		return serverErr
	}
	if accessErr != nil {
		s.lastError = accessErr.Error()
		return accessErr
	}
	return nil
}

func mountWebDAV(serverURL string) (string, error) {
	script := fmt.Sprintf(
		"POSIX path of (mount volume %s)",
		appleScriptStringLiteral(serverURL),
	)
	cmd := exec.Command("osascript", "-e", script)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("mount bucket with macOS mount volume: %w: %s", err, string(output))
	}
	mountPath := strings.TrimSpace(string(output))
	if mountPath == "" {
		return "", fmt.Errorf("mount bucket with macOS mount volume: empty mount path")
	}
	return filepath.Clean(mountPath), nil
}

func unmountWebDAV(mountPath string) error {
	var lastErr error
	var lastOutput string
	for _, candidate := range unmountCommands(mountPath) {
		cmd := exec.Command(candidate.name, candidate.args...)
		output, err := cmd.CombinedOutput()
		if err == nil {
			return nil
		}
		if _, statErr := os.Stat(mountPath); statErr != nil && os.IsNotExist(statErr) {
			return nil
		}
		lastErr = err
		lastOutput = strings.TrimSpace(string(output))
	}
	if lastErr == nil {
		return nil
	}
	return fmt.Errorf("unmount bucket: %w: %s", lastErr, lastOutput)
}

func openMountPath(mountPath string) error {
	cmd := exec.Command("open", mountPath)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("open mount path: %w: %s", err, string(output))
	}
	return nil
}

func appleScriptStringLiteral(value string) string {
	escaped := strings.ReplaceAll(value, "\\", "\\\\")
	escaped = strings.ReplaceAll(escaped, "\"", "\\\"")
	return fmt.Sprintf("\"%s\"", escaped)
}

// unmountCommands prefers plain umount first, then diskutil fallbacks for busy Finder-held volumes.
func unmountCommands(mountPath string) []unmountCommand {
	return []unmountCommand{
		{name: "/sbin/umount", args: []string{mountPath}},
		{name: "/usr/sbin/diskutil", args: []string{"unmount", mountPath}},
		{name: "/usr/sbin/diskutil", args: []string{"unmount", "force", mountPath}},
	}
}
