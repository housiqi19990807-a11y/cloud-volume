// dispatch_sync.go wires directory-sync profile management and control into the
// bridge. It owns a single process-wide scheduler started lazily on first use.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"

	storageconfig "remote-storage/go/config"
	syncpkg "remote-storage/go/sync"
)

var (
	schedulerOnce   sync.Once
	globalScheduler *syncpkg.Scheduler
)

// syncStore returns the process-wide scheduler, initializing it on first call.
// The store root is the app data directory so profiles persist next to config.
func syncStore() (*syncpkg.Scheduler, error) {
	var initErr error
	schedulerOnce.Do(func() {
		root, err := storageconfig.AppDataRoot()
		if err != nil {
			initErr = err
			return
		}
		runtime, err := storageconfig.RuntimeDir()
		if err != nil {
			initErr = err
			return
		}
		store := syncpkg.NewStore(root)
		globalScheduler = syncpkg.NewScheduler(store, runtime)
		globalScheduler.Start()
		log.Printf("[bridge/sync] scheduler started")
	})
	if initErr != nil {
		return nil, initErr
	}
	return globalScheduler, nil
}

// syncProfileArgs carries a full profile payload for add/update operations.
type syncProfileArgs struct {
	Profile syncpkg.SyncProfile `json:"profile"`
}

// syncProfileIDArgs identifies a profile by ID for delete/trigger operations.
type syncProfileIDArgs struct {
	ID string `json:"id"`
}

func listSyncProfiles(json.RawMessage) (any, error) {
	s, err := syncStore()
	if err != nil {
		return nil, err
	}
	return s.RuntimeStates(), nil
}

func saveSyncProfile(args json.RawMessage) (any, error) {
	var input syncProfileArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	profile := input.Profile
	if profile.ID == "" {
		profile.ID = syncpkg.NewProfileID()
	}
	if err := profile.Validate(); err != nil {
		return nil, err
	}
	s, err := syncStore()
	if err != nil {
		return nil, err
	}
	if err := s.SaveProfile(profile); err != nil {
		return nil, err
	}
	s.Reload()
	return map[string]any{"ok": true, "id": profile.ID}, nil
}

func deleteSyncProfile(args json.RawMessage) (any, error) {
	var input syncProfileIDArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if input.ID == "" {
		return nil, fmt.Errorf("missing sync profile id")
	}
	s, err := syncStore()
	if err != nil {
		return nil, err
	}
	if err := s.DeleteProfile(input.ID); err != nil {
		return nil, err
	}
	s.Reload()
	return map[string]any{"ok": true}, nil
}

func triggerSyncProfile(args json.RawMessage) (any, error) {
	var input syncProfileIDArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if input.ID == "" {
		return nil, fmt.Errorf("missing sync profile id")
	}
	s, err := syncStore()
	if err != nil {
		return nil, err
	}
	count, err := s.TriggerSync(input.ID)
	if err != nil {
		return nil, err
	}
	return map[string]any{"ok": true, "ops": count}, nil
}
