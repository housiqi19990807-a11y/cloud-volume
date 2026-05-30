//go:build linux

// Linux mount lifecycle keeps the cross-platform bucket manager wired to FUSE.
package mount

import (
	"fmt"
	"os"
	"time"

	gofusefs "github.com/hanwen/go-fuse/v2/fs"
	"github.com/hanwen/go-fuse/v2/fuse"

	storageconfig "remote-storage/go/config"
)

const linuxFuseAttrTTL = time.Second

type linuxFUSEBackend struct {
	server *fuse.Server
}

func newPlatformMountBackend(_ storageconfig.RemoteStorageConfig) (mountBackend, error) {
	return &linuxFUSEBackend{}, nil
}

func (b *linuxFUSEBackend) Initialize(session *mountSession) error {
	session.mountName = safeSegment(session.bucket)
	mountPath, err := linuxMountPath(session.bucket)
	if err != nil {
		return err
	}
	session.mountPath = mountPath
	session.mountTarget = mountPath
	return nil
}

func (b *linuxFUSEBackend) Start(session *mountSession) error {
	if err := os.RemoveAll(session.mountPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("prepare linux mount path: %w", err)
	}
	if err := os.MkdirAll(session.mountPath, 0o755); err != nil {
		return fmt.Errorf("create linux mount path: %w", err)
	}

	root := newLinuxFuseNode(session.access, true)
	server, err := gofusefs.Mount(session.mountPath, root, &gofusefs.Options{
		EntryTimeout: ptrDuration(linuxFuseAttrTTL),
		AttrTimeout:  ptrDuration(linuxFuseAttrTTL),
		MountOptions: fuse.MountOptions{
			Name:          "cloud-volume",
			FsName:        "cloud-volume:" + session.bucket,
			DisableXAttrs: true,
		},
	})
	if err != nil {
		return fmt.Errorf("mount bucket with linux fuse: %w", err)
	}

	b.server = server
	session.mounted = true
	return nil
}

func (b *linuxFUSEBackend) Stop(session *mountSession) error {
	session.mounted = false

	var firstErr error
	if b.server != nil {
		if err := b.server.Unmount(); err != nil && firstErr == nil {
			firstErr = fmt.Errorf("unmount linux fuse: %w", err)
		}
		b.server = nil
	} else if active, err := linuxMountActive(session.mountPath); err == nil && active {
		if err := linuxUnmountPath(session.mountPath); err != nil && firstErr == nil {
			firstErr = err
		}
	}

	if err := session.access.close(); err != nil && firstErr == nil {
		firstErr = err
	}
	if err := os.RemoveAll(session.mountPath); err != nil && !os.IsNotExist(err) && firstErr == nil {
		firstErr = err
	}
	return firstErr
}

func (b *linuxFUSEBackend) IsActive(session *mountSession) (bool, error) {
	return linuxMountActive(session.mountPath)
}

func (b *linuxFUSEBackend) CleanupStale(session *mountSession) error {
	paths, err := listLinuxManagedMountPaths()
	if err != nil {
		return err
	}
	for _, mountPath := range paths {
		if mountPath == session.mountPath {
			if err := linuxUnmountPath(mountPath); err != nil {
				return err
			}
		}
	}
	if err := os.RemoveAll(session.mountPath); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}

func cleanupAllManagedMounts() error {
	paths, err := listLinuxManagedMountPaths()
	if err != nil {
		return err
	}
	for _, mountPath := range paths {
		if err := linuxUnmountPath(mountPath); err != nil {
			return err
		}
		_ = os.RemoveAll(mountPath)
	}
	return nil
}

func ptrDuration(value time.Duration) *time.Duration {
	return &value
}
