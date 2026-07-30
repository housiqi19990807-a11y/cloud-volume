//go:build darwin

// macOS mount helpers wrap system WebDAV mounting, unmounting, and Finder opening.
package mount

import (
	"fmt"
	"log"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

type unmountCommand struct {
	name string
	args []string
}

func (s *mountSession) start() error {
	log.Printf("[mount/session] start bucket=%q mount_name=%q", s.bucket, s.mountName)
	server, serverURL, port, err := startWebDAVServer(s.access, s.mountName)
	if err != nil {
		return err
	}
	s.server = server
	s.serverURL = serverURL
	s.port = port
	log.Printf(
		"[mount/session] webdav-ready bucket=%q mount_name=%q url=%q port=%d",
		s.bucket,
		s.mountName,
		serverURL,
		port,
	)

	mountPath, err := mountWebDAV(serverURL, s.requestedPath)
	if err != nil {
		s.lastError = err.Error()
		return err
	}
	s.mountPath = mountPath
	s.mountTarget = mountPath
	s.mounted = true
	log.Printf("[mount/session] mounted bucket=%q path=%q", s.bucket, mountPath)
	return nil
}

func (s *mountSession) stop() error {
	log.Printf(
		"[mount/session] stop bucket=%q mounted=%t target=%q",
		s.bucket,
		s.mounted,
		s.mountTarget,
	)
	serverErr := error(nil)
	if s.server != nil {
		log.Printf("[mount/session] stop-webdav bucket=%q", s.bucket)
		serverErr = s.server.stop()
	}
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
	accessErr := error(nil)
	if s.access != nil {
		log.Printf("[mount/session] close-access bucket=%q", s.bucket)
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
	log.Printf("[mount/session] stop-done bucket=%q", s.bucket)
	return nil
}

func mountWebDAV(serverURL, requestedPath string) (string, error) {
	if strings.TrimSpace(requestedPath) != "" {
		mountPath := filepath.Clean(requestedPath)
		if err := os.MkdirAll(mountPath, 0o755); err != nil {
			return "", err
		}
		output, err := runLoggedCommand(
			macosMountCommandTimeout,
			"mount-webdav-path",
			"/sbin/mount_webdav",
			serverURL,
			mountPath,
		)
		if err != nil {
			if recovered := recoverMountedWebDAVPath(serverURL, mountPath); recovered != "" {
				return recovered, nil
			}
			return "", fmt.Errorf("mount bucket with macOS mount_webdav: %w: %s", err, string(output))
		}
		return mountPath, nil
	}
	script := fmt.Sprintf(
		"POSIX path of (mount volume %s)",
		appleScriptStringLiteral(serverURL),
	)
	output, err := runLoggedCommand(
		macosMountCommandTimeout,
		"mount-volume",
		"osascript",
		"-e",
		script,
	)
	if err != nil {
		if recovered := recoverMountedWebDAVPath(serverURL, ""); recovered != "" {
			return recovered, nil
		}
		return "", fmt.Errorf("mount bucket with macOS mount volume: %w: %s", err, string(output))
	}
	mountPath := strings.TrimSpace(string(output))
	if mountPath == "" {
		if recovered := recoverMountedWebDAVPath(serverURL, ""); recovered != "" {
			return recovered, nil
		}
		return "", fmt.Errorf("mount bucket with macOS mount volume: empty mount path")
	}
	return filepath.Clean(mountPath), nil
}

func recoverMountedWebDAVPath(serverURL, requestedPath string) string {
	deadline := time.Now().Add(2 * time.Second)
	for {
		paths, err := listWebDAVMountPaths()
		if err == nil {
			if recovered := findMountedWebDAVPath(serverURL, requestedPath, paths); recovered != "" {
				log.Printf(
					"[mount/macos] mount-command-recovered url=%q requested_path=%q actual_path=%q",
					serverURL,
					requestedPath,
					recovered,
				)
				return recovered
			}
		}
		if time.Now().After(deadline) {
			return ""
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func findMountedWebDAVPath(serverURL, requestedPath string, paths []string) string {
	if strings.TrimSpace(requestedPath) != "" {
		requested := filepath.Clean(requestedPath)
		for _, current := range paths {
			if filepath.Clean(current) == requested {
				return requested
			}
		}
		return ""
	}
	parsed, err := url.Parse(serverURL)
	if err != nil {
		return ""
	}
	mountName := path.Base(strings.TrimSuffix(parsed.Path, "/"))
	if mountName == "." || mountName == "/" || mountName == "" {
		return ""
	}
	matches := matchingBucketMountPaths(paths, mountName)
	if len(matches) == 0 {
		return ""
	}
	return matches[0]
}

func unmountWebDAV(mountPath string) error {
	var lastErr error
	var lastOutput string
	for _, candidate := range unmountCommands(mountPath) {
		phase := fmt.Sprintf("unmount cmd=%s path=%s", filepath.Base(candidate.name), mountPath)
		output, err := runLoggedCommand(
			macosUnmountCommandTimeout,
			phase,
			candidate.name,
			candidate.args...,
		)
		if err == nil {
			return nil
		}
		gone, probeErr := mountPathInactive(mountPath)
		if probeErr == nil {
			if gone {
				log.Printf("[mount/macos] unmount-confirmed-inactive path=%q", mountPath)
				return nil
			}
			lastErr = err
			lastOutput = strings.TrimSpace(string(output))
			continue
		}
		if _, statErr := os.Stat(mountPath); statErr != nil && os.IsNotExist(statErr) {
			log.Printf("[mount/macos] unmount-path-gone path=%q", mountPath)
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

func mountPathInactive(mountPath string) (bool, error) {
	active, err := isWebDAVMountActive(mountPath)
	if err != nil {
		return false, err
	}
	return !active, nil
}

func openMountPath(mountPath string) error {
	output, err := runLoggedCommand(macosOpenCommandTimeout, "open-mount-path", "open", mountPath)
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
