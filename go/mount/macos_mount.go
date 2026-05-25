// macOS mount helpers wrap mount_webdav, umount, and Finder opening.
package mount

import (
	"fmt"
	"os"
	"os/exec"
)

func (s *mountSession) start() error {
	server, serverURL, port, err := startWebDAVServer(s.access)
	if err != nil {
		return err
	}
	s.server = server
	s.serverURL = serverURL
	s.port = port

	if err := os.MkdirAll(s.mountPath, 0o755); err != nil {
		return fmt.Errorf("create mount path: %w", err)
	}
	if err := mountWebDAV(serverURL, s.mountPath, s.mountName); err != nil {
		s.lastError = err.Error()
		return err
	}
	s.mounted = true
	return nil
}

func (s *mountSession) stop() error {
	var mountErr error
	if s.mounted && s.mountPath != "" {
		mountErr = unmountWebDAV(s.mountPath)
		s.mounted = false
	}
	serverErr := error(nil)
	if s.server != nil {
		serverErr = s.server.stop()
	}
	if mountErr != nil {
		s.lastError = mountErr.Error()
		return mountErr
	}
	_ = os.Remove(s.mountPath)
	if serverErr != nil {
		s.lastError = serverErr.Error()
		return serverErr
	}
	return nil
}

func mountWebDAV(serverURL, mountPath, volumeName string) error {
	cmd := exec.Command(
		"/sbin/mount_webdav",
		"-S",
		"-v",
		volumeName,
		serverURL,
		mountPath,
	)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("mount bucket with mount_webdav: %w: %s", err, string(output))
	}
	return nil
}

func unmountWebDAV(mountPath string) error {
	cmd := exec.Command("/sbin/umount", mountPath)
	output, err := cmd.CombinedOutput()
	if err == nil {
		return nil
	}
	if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() != 0 {
		if _, statErr := os.Stat(mountPath); statErr != nil && os.IsNotExist(statErr) {
			return nil
		}
	}
	return fmt.Errorf("unmount bucket: %w: %s", err, string(output))
}

func openMountPath(mountPath string) error {
	cmd := exec.Command("open", mountPath)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("open mount path: %w: %s", err, string(output))
	}
	return nil
}
