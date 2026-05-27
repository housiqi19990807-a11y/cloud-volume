// Trash purge scheduling keeps retention cleanup off the foreground listing path.
package s3

import (
	"context"
	"fmt"
	"sync"
	"time"

	storageconfig "remote-storage/go/config"
)

const trashPurgeCooldown = 10 * time.Minute

var trashPurgeStateStore = struct {
	mu     sync.Mutex
	states map[string]trashPurgeState
}{
	states: map[string]trashPurgeState{},
}

type trashPurgeState struct {
	running   bool
	lastStart time.Time
}

func scheduleExpiredTrashPurge(cfg storageconfig.RemoteStorageConfig, bucket string) {
	if cfg.TrashRetentionDays < 0 {
		return
	}

	key := trashPurgeStateKey(cfg, bucket)
	now := time.Now()

	trashPurgeStateStore.mu.Lock()
	state := trashPurgeStateStore.states[key]
	if state.running || now.Sub(state.lastStart) < trashPurgeCooldown {
		trashPurgeStateStore.mu.Unlock()
		return
	}
	trashPurgeStateStore.states[key] = trashPurgeState{
		running:   true,
		lastStart: now,
	}
	trashPurgeStateStore.mu.Unlock()

	go func() {
		defer markTrashPurgeFinished(key)

		ctx, cancel := context.WithTimeout(Ctx(), 30*time.Minute)
		defer cancel()

		client := NewClient(cfg)
		_ = purgeExpiredTrash(ctx, client, cfg, bucket)
	}()
}

func markTrashPurgeFinished(key string) {
	trashPurgeStateStore.mu.Lock()
	defer trashPurgeStateStore.mu.Unlock()

	state := trashPurgeStateStore.states[key]
	state.running = false
	trashPurgeStateStore.states[key] = state
}

func trashPurgeStateKey(cfg storageconfig.RemoteStorageConfig, bucket string) string {
	return fmt.Sprintf(
		"%s|%s|%s|%d",
		cfg.Endpoint,
		bucket,
		cfg.TrashDirectoryName,
		cfg.TrashRetentionDays,
	)
}
