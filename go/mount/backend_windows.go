//go:build windows && cgo

// Windows backend exposes one bucket as a native Cloud Files sync-root folder.
package mount

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
)

const windowsMountFolderName = "Cloud Volume"

type windowsCloudFilesBackend struct {
	provider *cloudFilesProvider
	hydrator *cloudFilesHydrator
	watcher  *windowsSyncWatcher
}

type windowsCloudMount = windowsCloudFilesBackend

func newPlatformMountBackend() (mountBackend, error) {
	return &windowsCloudFilesBackend{}, nil
}

func (b *windowsCloudFilesBackend) Initialize(session *mountSession) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("resolve user home: %w", err)
	}
	session.mountName = session.bucket
	session.mountPath = filepath.Join(homeDir, windowsMountFolderName, safeSegment(session.bucket))
	session.mountTarget = session.mountPath
	return nil
}

func (b *windowsCloudFilesBackend) Start(session *mountSession) error {
	if err := os.MkdirAll(session.mountPath, 0o755); err != nil {
		return fmt.Errorf("create sync-root directory: %w", err)
	}

	watcher, err := newWindowsSyncWatcher(session.mountPath, session.access)
	if err != nil {
		return fmt.Errorf("create sync-root watcher: %w", err)
	}
	provider := newCloudFilesProvider(
		session.mountPath,
		windowsCFProviderID,
		"Cloud Volume "+session.bucket,
	)
	_ = provider.Deregister()
	if err := provider.Register(); err != nil {
		_ = watcher.Close()
		return err
	}

	hydrator := newCloudFilesHydrator(session.mountPath, session.access, provider, watcher)
	if err := provider.Connect(cloudFilesCallbacks{
		OnFetchData:         hydrator.OnFetchData,
		OnCancelFetch:       hydrator.OnCancelFetch,
		OnFetchPlaceholders: hydrator.OnFetchPlaceholders,
		OnDeleteCompletion:  b.handleDelete(session, watcher),
		OnRenameCompletion:  b.handleRename(session, watcher),
	}); err != nil {
		_ = provider.Deregister()
		_ = watcher.Close()
		return err
	}
	if err := watcher.Start(); err != nil {
		_ = provider.Disconnect()
		_ = provider.Deregister()
		_ = watcher.Close()
		return err
	}
	if err := hydrator.OnFetchPlaceholders(session.mountPath); err != nil {
		_ = watcher.Close()
		_ = provider.Disconnect()
		_ = provider.Deregister()
		return err
	}

	b.provider = provider
	b.hydrator = hydrator
	b.watcher = watcher
	session.mounted = true
	return nil
}

func (b *windowsCloudFilesBackend) Stop(session *mountSession) error {
	session.mounted = false

	var firstErr error
	if b.watcher != nil {
		if err := b.watcher.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	if b.provider != nil {
		if err := b.provider.Disconnect(); err != nil && firstErr == nil {
			firstErr = err
		}
		if err := b.provider.Deregister(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	if session.access != nil {
		if err := session.access.close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}

	b.provider = nil
	b.hydrator = nil
	b.watcher = nil
	return firstErr
}

func (b *windowsCloudFilesBackend) IsActive(session *mountSession) (bool, error) {
	if b.provider == nil {
		return false, nil
	}
	if _, err := os.Stat(session.mountPath); err != nil {
		return false, nil
	}
	return b.provider.IsConnected(), nil
}

func (b *windowsCloudFilesBackend) CleanupStale(session *mountSession) error {
	_ = session
	return nil
}

func cleanupAllManagedMounts() error {
	return nil
}

func (b *windowsCloudFilesBackend) handleDelete(
	session *mountSession,
	watcher *windowsSyncWatcher,
) func(localPath string) {
	return func(localPath string) {
		virtualPath := cloudFilesLocalPathToVirtual(session.mountPath, localPath)
		if isWindowsLocalOnlyPath(virtualPath) {
			return
		}
		isDir := watcher.IsDir(localPath)
		watcher.Forget(localPath)
		if err := session.access.deletePath(context.Background(), virtualPath, isDir); err != nil {
			session.lastError = err.Error()
		}
	}
}

func (b *windowsCloudFilesBackend) handleRename(
	session *mountSession,
	watcher *windowsSyncWatcher,
) func(oldPath, newPath string) {
	return func(oldPath, newPath string) {
		oldVirtual := cloudFilesLocalPathToVirtual(session.mountPath, oldPath)
		newVirtual := cloudFilesLocalPathToVirtual(session.mountPath, newPath)
		if isWindowsLocalOnlyPath(oldVirtual) || isWindowsLocalOnlyPath(newVirtual) {
			return
		}
		isDir := watcher.IsDir(newPath)
		watcher.MarkHydrating(oldPath)
		watcher.MarkHydrating(newPath)
		watcher.Rebase(oldPath, newPath, isDir)
		if err := session.access.renamePath(context.Background(), oldVirtual, newVirtual, isDir); err != nil {
			session.lastError = err.Error()
		}
	}
}

func (b *windowsCloudFilesBackend) isActive() (bool, error) {
	if b.provider == nil {
		return false, nil
	}
	return b.provider.IsConnected(), nil
}
