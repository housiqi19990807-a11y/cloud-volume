//go:build darwin

// macOS mount helpers wrap system WebDAV mounting, unmounting, and Finder opening.
package mount

import (
	"fmt"
	"log"
	"net/url"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type unmountCommand struct {
	name string
	args []string
}

// macosOpenLaunchTimeout bounds how long openMountPath waits for the Finder
// open call to fire before returning. macOS LaunchServices may block for
// ~90s on a freshly mounted webdav volume's first statfs; we never want
// to hold a goroutine that long, and the gate only needs to know the
// request was dispatched.
const macosOpenLaunchTimeout = 3 * time.Second

var (
	probeWebDAVMountActive = isWebDAVMountActive
	executeUnmountWebDAV   = unmountWebDAV
)

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
	// Pre-warm macOS webdavfs so the first user-visible access doesn't
	// pay the ~90s statfs initialization penalty. A background filesystem
	// stat forces webdavfs_agent to start its handshake immediately after
	// the volume appears, rather than waiting for Finder to trigger it.
	go prewarmWebDAVMount(mountPath)
	return nil
}

// prewarmWebDAVMount triggers webdavfs_agent initialization without
// blocking the mount path. It does a single os.Stat on the mount root
// (which forces the VFS layer to query the WebDAV server), then a
// ReadDir to populate the directory cache. Both calls are bounded so
// a hung webdavfs cannot leak a goroutine indefinitely.
func prewarmWebDAVMount(mountPath string) {
	startedAt := time.Now()
	// os.Stat is the cheapest VFS probe that still forces webdavfs_agent
	// to connect and run its initial statfs.
	info, err := os.Stat(mountPath)
	if err != nil {
		log.Printf("[mount/macos] prewarm-stat-error path=%q err=%v duration=%s", mountPath, err, time.Since(startedAt).Round(time.Millisecond))
		return
	}
	log.Printf("[mount/macos] prewarm-stat-done path=%q duration=%s size=%d", mountPath, time.Since(startedAt).Round(time.Millisecond), info.Size())
	// Read one directory entry to populate the webdavfs dirent cache.
	// This is non-blocking to the caller and makes the first Finder
	// window significantly faster.
	entries, err := os.ReadDir(mountPath)
	if err != nil {
		log.Printf("[mount/macos] prewarm-readdir-error path=%q err=%v duration=%s", mountPath, err, time.Since(startedAt).Round(time.Millisecond))
		return
	}
	log.Printf("[mount/macos] prewarm-done path=%q entries=%d duration=%s", mountPath, len(entries), time.Since(startedAt).Round(time.Millisecond))
}

func (s *mountSession) stop() error {
	log.Printf(
		"[mount/session] stop bucket=%q mounted=%t target=%q",
		s.bucket,
		s.mounted,
		s.mountTarget,
	)
	var mountErr error
	if s.mounted && s.mountTarget != "" {
		active, err := probeWebDAVMountActive(s.mountTarget)
		if err != nil {
			mountErr = err
		} else if active {
			mountErr = executeUnmountWebDAV(s.mountTarget)
		}
		if mountErr != nil {
			s.lastError = mountErr.Error()
			s.stopping = false
			log.Printf(
				"[mount/session] keep-webdav-after-unmount-error bucket=%q err=%v",
				s.bucket,
				mountErr,
			)
			return mountErr
		}
		s.mounted = false
	}
	serverErr := error(nil)
	if s.server != nil {
		log.Printf("[mount/session] stop-webdav bucket=%q", s.bucket)
		serverErr = s.server.stop()
		s.server = nil
	}
	accessErr := error(nil)
	if s.access != nil {
		log.Printf("[mount/session] close-access bucket=%q", s.bucket)
		accessErr = s.access.close()
		s.access = nil
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
		output, recovered, err := runLoggedCommandUntilSuccess(
			macosMountCommandTimeout,
			100*time.Millisecond,
			"mount-webdav-path",
			func() (string, bool) {
				mounted := probeMountedWebDAVPath(serverURL, mountPath)
				return mounted, mounted != ""
			},
			"/sbin/mount_webdav",
			serverURL,
			mountPath,
		)
		if recovered != "" {
			return recovered, nil
		}
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
	output, recovered, err := runLoggedCommandUntilSuccess(
		macosMountCommandTimeout,
		100*time.Millisecond,
		"mount-volume",
		func() (string, bool) {
			mounted := probeMountedWebDAVPath(serverURL, "")
			return mounted, mounted != ""
		},
		"osascript",
		"-e",
		script,
	)
	if recovered != "" {
		return recovered, nil
	}
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
		if recovered := probeMountedWebDAVPath(serverURL, requestedPath); recovered != "" {
			return recovered
		}
		if time.Now().After(deadline) {
			return ""
		}
		time.Sleep(100 * time.Millisecond)
	}
}

func probeMountedWebDAVPath(serverURL, requestedPath string) string {
	paths, err := listWebDAVMountPaths()
	if err != nil {
		return ""
	}
	return findMountedWebDAVPath(serverURL, requestedPath, paths)
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

var macOSMountOpenGate = newMountOpenGate()

type mountOpenGate struct {
	mu      sync.Mutex
	running map[string]struct{}
}

func newMountOpenGate() *mountOpenGate {
	return &mountOpenGate{running: make(map[string]struct{})}
}

func (g *mountOpenGate) tryStart(mountPath string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	if _, exists := g.running[mountPath]; exists {
		return false
	}
	g.running[mountPath] = struct{}{}
	return true
}

func (g *mountOpenGate) finish(mountPath string) {
	g.mu.Lock()
	delete(g.running, mountPath)
	g.mu.Unlock()
}

func openMountPath(mountPath string) error {
	clean := filepath.Clean(mountPath)
	if !macOSMountOpenGate.tryStart(clean) {
		log.Printf("[mount/macos] open-mount-path coalesced path=%q", clean)
		return nil
	}
	go runMacOSFinderOpen(clean)
	return nil
}

// runMacOSFinderOpen launches Finder without inheriting our pipes.
// macOS LaunchServices spawns Finder via XPC; a plain exec inherits
// stdout/stderr which Finder keeps open for ~90s during the first statfs,
// so CombinedOutput blocks far past its context timeout. We detach the
// process: Start it with Stdout/Stderr set to os.DevNull and never Wait,
// logging only whether the launch itself succeeded.
func runMacOSFinderOpen(mountPath string) {
	defer macOSMountOpenGate.finish(mountPath)
	log.Printf("[mount/macos] open-mount-path start path=%q", mountPath)

	startedAt := time.Now()
	cmd := exec.Command("open", mountPath)
	// Detach all standard streams so no descendant (Finder, webdavfs_agent)
	// can hold our goroutine via an inherited pipe.
	devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		log.Printf("[mount/macos] open-mount-path detach-error path=%q err=%v", mountPath, err)
		return
	}
	defer devNull.Close()
	cmd.Stdout = devNull
	cmd.Stderr = devNull
	// Place the child in its own process group so a signal sent to our
	// process tree (e.g. during shutdown) cannot drag Finder with it.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	if err := cmd.Start(); err != nil {
		log.Printf("[mount/macos] open-mount-path start-error path=%q err=%v", mountPath, err)
		return
	}
	// Reap the immediate child (open exits quickly); do NOT wait for
	// descendants, which is exactly what blocks CombinedOutput.
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case <-done:
		log.Printf("[mount/macos] open-mount-path done path=%q duration=%s", mountPath, time.Since(startedAt).Round(time.Millisecond))
	case <-time.After(macosOpenLaunchTimeout):
		log.Printf("[mount/macos] open-mount-path dispatched path=%q duration=%s (open still running, Finder will appear)", mountPath, time.Since(startedAt).Round(time.Millisecond))
	}
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
