//go:build windows && cgo

// Cloud Files placeholder callback gating avoids Explorer-triggered refresh loops.
package mount

import (
	"path/filepath"
	"time"
)

const windowsCloudFilesPlaceholderRefreshTTL = 3 * time.Second

type cloudFilesPlaceholderFetch struct {
	done chan struct{}
	err  error
}

func (h *cloudFilesHydrator) beginPlaceholderFetch(
	localPath string,
) (bool, *cloudFilesPlaceholderFetch) {
	h.placeholderMu.Lock()
	defer h.placeholderMu.Unlock()

	cleanLocalPath := filepath.Clean(localPath)
	if wait, ok := h.placeholderInflight[cleanLocalPath]; ok {
		return false, wait
	}
	if lastFetch, ok := h.placeholderFetched[cleanLocalPath]; ok &&
		time.Since(lastFetch) < windowsCloudFilesPlaceholderRefreshTTL {
		return false, nil
	}
	flight := &cloudFilesPlaceholderFetch{done: make(chan struct{})}
	h.placeholderInflight[cleanLocalPath] = flight
	return true, nil
}

func (h *cloudFilesHydrator) finishPlaceholderFetch(localPath string, fetchErr error) {
	h.placeholderMu.Lock()
	defer h.placeholderMu.Unlock()

	cleanLocalPath := filepath.Clean(localPath)
	if flight, ok := h.placeholderInflight[cleanLocalPath]; ok {
		flight.err = fetchErr
		close(flight.done)
		delete(h.placeholderInflight, cleanLocalPath)
	}
	if fetchErr == nil {
		h.placeholderFetched[cleanLocalPath] = time.Now()
	} else {
		delete(h.placeholderFetched, cleanLocalPath)
	}
}
