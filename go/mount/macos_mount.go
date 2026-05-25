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

	if err := prepareMountTarget(s.mountTarget); err != nil {
		return err
	}
	if err := mountWebDAV(serverURL, s.mountTarget, s.mountName); err != nil {
		s.lastError = err.Error()
		return err
	}
	s.mounted = true
	return nil
}

func (s *mountSession) stop() error {
	var mountErr error
	if s.mounted && s.mountTarget != "" {
		mountErr = unmountWebDAV(s.mountTarget)
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
	_ = os.Remove(s.mountTarget)
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

// The Desktop path itself is the real mount point so Finder and Archive Utility
// see a normal writable volume instead of a symlinked proxy directory.
func prepareMountTarget(mountPath string) error {
	info, err := os.Lstat(mountPath)
	switch {
	case os.IsNotExist(err):
		if err := os.MkdirAll(mountPath, 0o755); err != nil {
			return err
		}
		return markMountPathIgnoredByFileProvider(mountPath)
	case err != nil:
		return fmt.Errorf("inspect mount target: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		if err := os.Remove(mountPath); err != nil {
			return fmt.Errorf("remove legacy mount symlink: %w", err)
		}
		if err := os.MkdirAll(mountPath, 0o755); err != nil {
			return err
		}
		return markMountPathIgnoredByFileProvider(mountPath)
	}
	if !info.IsDir() {
		return fmt.Errorf("mount path %q already exists and is not a directory", mountPath)
	}
	entries, err := os.ReadDir(mountPath)
	if err != nil {
		return fmt.Errorf("inspect mount target entries: %w", err)
	}
	if len(entries) > 0 {
		return fmt.Errorf("mount path %q already exists and is not empty", mountPath)
	}
	return markMountPathIgnoredByFileProvider(mountPath)
}
