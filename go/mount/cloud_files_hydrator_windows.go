//go:build windows && cgo

// Cloud Files hydration translates placeholder callbacks into direct S3 reads.
package mount

import (
	"context"
	"fmt"
	"strings"
	"sync"
)

type cloudFilesHydrator struct {
	syncRoot string
	access   *bucketAccess
	provider *cloudFilesProvider
	watcher  *windowsSyncWatcher

	cancelMu sync.Mutex
	cancels  map[string]context.CancelFunc
}

func newCloudFilesHydrator(
	syncRoot string,
	access *bucketAccess,
	provider *cloudFilesProvider,
	watcher *windowsSyncWatcher,
) *cloudFilesHydrator {
	return &cloudFilesHydrator{
		syncRoot: syncRoot,
		access:   access,
		provider: provider,
		watcher:  watcher,
		cancels:  map[string]context.CancelFunc{},
	}
}

func (h *cloudFilesHydrator) OnFetchData(req cloudFilesFetchRequest) error {
	ctx, cancel := context.WithCancel(context.Background())
	h.cancelMu.Lock()
	h.cancels[req.LocalPath] = cancel
	h.cancelMu.Unlock()
	defer func() {
		cancel()
		h.cancelMu.Lock()
		delete(h.cancels, req.LocalPath)
		h.cancelMu.Unlock()
	}()

	virtualPath := cloudFilesLocalPathToVirtual(h.syncRoot, req.LocalPath)
	if virtualPath == "" {
		return fmt.Errorf("resolve Cloud Files fetch path")
	}
	h.watcher.MarkHydrating(req.LocalPath)

	data, err := h.access.readRemoteRange(ctx, virtualPath, req.Offset, req.Length)
	if err != nil {
		_ = h.provider.ReportError(req, err)
		return fmt.Errorf("read remote range %q: %w", virtualPath, err)
	}
	if err := h.provider.ExecuteTransfer(req, data); err != nil {
		_ = h.provider.ReportError(req, err)
		return fmt.Errorf("execute Cloud Files transfer %q: %w", virtualPath, err)
	}
	_ = h.provider.ReportProgress(req, req.Length, int64(len(data)))
	h.watcher.MarkHydrated(req.LocalPath)
	_ = h.provider.SetInSync(req.LocalPath, true)
	return nil
}

func (h *cloudFilesHydrator) OnCancelFetch(req cloudFilesFetchRequest) {
	h.cancelMu.Lock()
	cancel := h.cancels[req.LocalPath]
	h.cancelMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (h *cloudFilesHydrator) OnFetchPlaceholders(localPath string) error {
	virtualPath := cloudFilesLocalPathToVirtual(h.syncRoot, localPath)
	items, err := h.access.listRemoteDirectory(context.Background(), virtualPath)
	if err != nil {
		return fmt.Errorf("list remote directory %q: %w", virtualPath, err)
	}

	placeholders := make([]cloudPlaceholderInfo, 0, len(items))
	for _, item := range items {
		relativeName := strings.TrimSuffix(baseName(item.Key), "/")
		if relativeName == "" {
			continue
		}
		placeholder := cloudFilesPlaceholderInfo(item)
		placeholder.RelativePath = relativeName
		placeholders = append(placeholders, placeholder)
	}
	if err := h.provider.CreatePlaceholders(localPath, placeholders); err != nil {
		return err
	}
	h.watcher.RememberPlaceholders(localPath, placeholders)
	return nil
}
