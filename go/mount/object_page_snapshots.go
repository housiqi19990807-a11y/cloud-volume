// Mounted directory snapshots keep multi-page file-manager reads stable across mutations.
package mount

import (
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	s3ops "remote-storage/go/s3"
)

const (
	mountedDirectorySnapshotTTL  = 2 * time.Minute
	maxMountedDirectorySnapshots = 16
)

type mountedDirectoryPageSnapshot struct {
	id        uint64
	prefix    string
	items     []s3ops.ObjectInfo
	createdAt time.Time
	expiresAt time.Time
}

// mountedDirectoryPageSnapshots retains immutable list snapshots for opaque
// continuation tokens. A new first-page request always creates a new snapshot,
// while an in-flight pagination sequence keeps reading its original view.
type mountedDirectoryPageSnapshots struct {
	mu     sync.Mutex
	nextID uint64
	byID   map[uint64]mountedDirectoryPageSnapshot
}

func newMountedDirectoryPageSnapshots() *mountedDirectoryPageSnapshots {
	return &mountedDirectoryPageSnapshots{
		byID: make(map[uint64]mountedDirectoryPageSnapshot),
	}
}

func (s *mountedDirectoryPageSnapshots) page(
	prefix, token string,
	pageSize int32,
) (s3ops.ObjectPage, bool) {
	id, offset, ok := parseMountedDirectorySnapshotToken(token)
	if s == nil || !ok {
		return s3ops.ObjectPage{}, false
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneLocked(time.Now())
	snapshot, ok := s.byID[id]
	if !ok || snapshot.prefix != cleanVirtualPath(prefix) {
		return s3ops.ObjectPage{}, false
	}
	return paginateMountedSnapshot(snapshot, offset, pageSize), true
}

func (s *mountedDirectoryPageSnapshots) start(
	prefix string,
	items []s3ops.ObjectInfo,
	requestedToken string,
	pageSize int32,
) s3ops.ObjectPage {
	if s == nil {
		return paginateObjectInfos(items, requestedToken, pageSize)
	}
	now := time.Now()
	s.mu.Lock()
	defer s.mu.Unlock()
	s.pruneLocked(now)
	s.nextID++
	snapshot := mountedDirectoryPageSnapshot{
		id:        s.nextID,
		prefix:    cleanVirtualPath(prefix),
		items:     cloneObjects(items),
		createdAt: now,
		expiresAt: now.Add(mountedDirectorySnapshotTTL),
	}
	s.byID[snapshot.id] = snapshot
	s.evictOldestLocked()
	return paginateMountedSnapshot(snapshot, mountedDirectoryTokenOffset(requestedToken), pageSize)
}

func (s *mountedDirectoryPageSnapshots) pruneLocked(now time.Time) {
	for id, snapshot := range s.byID {
		if now.After(snapshot.expiresAt) {
			delete(s.byID, id)
		}
	}
}

func (s *mountedDirectoryPageSnapshots) evictOldestLocked() {
	for len(s.byID) > maxMountedDirectorySnapshots {
		var oldest mountedDirectoryPageSnapshot
		for _, snapshot := range s.byID {
			if oldest.id == 0 || snapshot.createdAt.Before(oldest.createdAt) {
				oldest = snapshot
			}
		}
		delete(s.byID, oldest.id)
	}
}

func paginateMountedSnapshot(
	snapshot mountedDirectoryPageSnapshot,
	offset int,
	pageSize int32,
) s3ops.ObjectPage {
	if pageSize <= 0 {
		pageSize = 200
	}
	if offset < 0 || offset >= len(snapshot.items) {
		return s3ops.ObjectPage{Items: []s3ops.ObjectInfo{}, NextToken: ""}
	}
	end := offset + int(pageSize)
	if end > len(snapshot.items) {
		end = len(snapshot.items)
	}
	page := s3ops.ObjectPage{Items: cloneObjects(snapshot.items[offset:end])}
	if end < len(snapshot.items) {
		page.NextToken = fmt.Sprintf("m:%d:%d", snapshot.id, end)
	}
	return page
}

func parseMountedDirectorySnapshotToken(token string) (uint64, int, bool) {
	parts := strings.Split(strings.TrimSpace(token), ":")
	if len(parts) != 3 || parts[0] != "m" {
		return 0, 0, false
	}
	id, idErr := strconv.ParseUint(parts[1], 10, 64)
	offset, offsetErr := strconv.Atoi(parts[2])
	if idErr != nil || offsetErr != nil || id == 0 || offset < 0 {
		return 0, 0, false
	}
	return id, offset, true
}

func mountedDirectoryTokenOffset(token string) int {
	if _, offset, ok := parseMountedDirectorySnapshotToken(token); ok {
		return offset
	}
	offset, err := strconv.Atoi(strings.TrimSpace(token))
	if err != nil || offset < 0 {
		return 0
	}
	return offset
}
