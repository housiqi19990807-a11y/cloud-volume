// macOS mount helpers wrap mount_webdav, umount, and Finder opening.
package mount

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

func (s *mountSession) start() error {
	server, serverURL, port, err := startWebDAVServer(s.access)
	if err != nil {
		return err
	}
	s.server = server
	s.serverURL = serverURL
	s.port = port

	if err := os.MkdirAll(s.mountTarget, 0o755); err != nil {
		return fmt.Errorf("create mount target: %w", err)
	}
	if err := mountWebDAV(serverURL, s.mountTarget, s.mountName); err != nil {
		s.lastError = err.Error()
		return err
	}
	if err := ensureDesktopMountLink(s.mountPath, s.mountTarget); err != nil {
		s.lastError = err.Error()
		_ = unmountWebDAV(s.mountTarget)
		return err
	}
	s.mounted = true
	return nil
}

func (s *mountSession) stop() error {
	desktopErr := removeDesktopMountLink(s.mountPath)
	var mountErr error
	if s.mounted && s.mountTarget != "" {
		mountErr = unmountWebDAV(s.mountTarget)
		s.mounted = false
	}
	serverErr := error(nil)
	if s.server != nil {
		serverErr = s.server.stop()
	}
	if desktopErr != nil {
		s.lastError = desktopErr.Error()
		return desktopErr
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

// The Desktop entry stays user-visible while the real mounted filesystem lives
// under the app runtime directory, which avoids iCloud/Desktop sync conflicts.
func ensureDesktopMountLink(linkPath, targetPath string) error {
	info, err := os.Lstat(linkPath)
	switch {
	case err == nil:
		if info.Mode()&os.ModeSymlink != 0 {
			resolved, readErr := os.Readlink(linkPath)
			if readErr == nil && resolved == targetPath {
				return nil
			}
			if removeErr := os.Remove(linkPath); removeErr != nil {
				return fmt.Errorf("replace desktop mount link: %w", removeErr)
			}
			return os.Symlink(targetPath, linkPath)
		}
		if info.IsDir() {
			entries, readErr := os.ReadDir(linkPath)
			if readErr != nil {
				return fmt.Errorf("inspect desktop mount path: %w", readErr)
			}
			if len(entries) > 0 {
				return fmt.Errorf("desktop mount path %q already exists and is not empty", linkPath)
			}
			if removeErr := os.Remove(linkPath); removeErr != nil {
				return fmt.Errorf("replace desktop mount directory: %w", removeErr)
			}
			return os.Symlink(targetPath, linkPath)
		}
		return fmt.Errorf("desktop mount path %q already exists", linkPath)
	case os.IsNotExist(err):
		if err := os.MkdirAll(filepath.Dir(linkPath), 0o755); err != nil {
			return fmt.Errorf("create desktop mount parent: %w", err)
		}
		return os.Symlink(targetPath, linkPath)
	default:
		return fmt.Errorf("inspect desktop mount path: %w", err)
	}
}

func removeDesktopMountLink(linkPath string) error {
	info, err := os.Lstat(linkPath)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("stat desktop mount link: %w", err)
	}
	if info.Mode()&os.ModeSymlink == 0 {
		return nil
	}
	if err := os.Remove(linkPath); err != nil {
		return fmt.Errorf("remove desktop mount link: %w", err)
	}
	return nil
}
