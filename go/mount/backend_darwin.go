//go:build darwin

// macOS backend keeps the current WebDAV-based Finder mount behavior.
package mount

import (
	"path/filepath"
	"strings"
)

const managedMountPrefix = "云卷-"

type macOSWebDAVBackend struct{}

func newPlatformMountBackend() (mountBackend, error) {
	return &macOSWebDAVBackend{}, nil
}

func (b *macOSWebDAVBackend) Initialize(session *mountSession) error {
	session.mountName = managedMountPrefix + session.bucket
	session.mountPath = filepath.Join("/Volumes", session.mountName)
	session.mountTarget = session.mountPath
	return nil
}

func (b *macOSWebDAVBackend) Start(session *mountSession) error {
	return session.start()
}

func (b *macOSWebDAVBackend) Stop(session *mountSession) error {
	return session.stop()
}

func (b *macOSWebDAVBackend) IsActive(session *mountSession) (bool, error) {
	return isWebDAVMountActive(session.mountTarget)
}

func (b *macOSWebDAVBackend) CleanupStale(session *mountSession) error {
	paths, err := listWebDAVMountPaths()
	if err != nil {
		return err
	}
	for _, mountPath := range matchingBucketMountPaths(paths, session.mountName) {
		if err := unmountWebDAV(mountPath); err != nil {
			return err
		}
	}
	return nil
}

func cleanupAllManagedMounts() error {
	paths, err := listWebDAVMountPaths()
	if err != nil {
		return err
	}
	for _, mountPath := range matchingManagedMountPaths(paths) {
		if err := unmountWebDAV(mountPath); err != nil {
			return err
		}
	}
	return nil
}

func matchingBucketMountPaths(paths []string, mountName string) []string {
	basePath := filepath.Join("/Volumes", mountName)
	matches := make([]string, 0, len(paths))
	for _, mountPath := range paths {
		clean := filepath.Clean(strings.TrimSpace(mountPath))
		if clean == basePath || strings.HasPrefix(clean, basePath+"-") {
			matches = append(matches, clean)
		}
	}
	return matches
}

func matchingManagedMountPaths(paths []string) []string {
	basePrefix := filepath.Join("/Volumes", managedMountPrefix)
	matches := make([]string, 0, len(paths))
	for _, mountPath := range paths {
		clean := filepath.Clean(strings.TrimSpace(mountPath))
		if strings.HasPrefix(clean, basePrefix) {
			matches = append(matches, clean)
		}
	}
	return matches
}
