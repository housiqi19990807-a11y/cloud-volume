// scheduler.go runs periodic reconcile passes for each enabled profile and
// dispatches the resulting ops into the shared transfer monitor. Each profile
// gets its own goroutine and ticker, with quiet-period debouncing so hot files
// (actively being written) are skipped until they settle.
package sync

import (
	"context"
	"fmt"
	"log"
	"sync"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

// Scheduler owns the lifecycle of all sync-profile goroutines.
type Scheduler struct {
	store       Store
	runtimeRoot string
	mu          sync.Mutex
	running     map[string]*profileRunner // profileID -> runner
	ctx         context.Context
	cancel      context.CancelFunc
}

// NewScheduler creates a scheduler that is not yet running any profiles.
func NewScheduler(store Store, runtimeRoot string) *Scheduler {
	return &Scheduler{
		store:       store,
		runtimeRoot: runtimeRoot,
		running:     map[string]*profileRunner{},
	}
}

// Start loads all enabled profiles and begins scheduling them.
// It is safe to call multiple times; existing runners are left in place.
func (s *Scheduler) Start() {
	s.mu.Lock()
	if s.ctx == nil {
		s.ctx, s.cancel = context.WithCancel(context.Background())
	}
	ctx := s.ctx
	s.mu.Unlock()

	profiles, err := s.store.LoadAll()
	if err != nil {
		log.Printf("[sync/scheduler] load profiles: %v", err)
		return
	}
	for _, profile := range profiles {
		if !profile.Enabled {
			continue
		}
		s.startProfile(ctx, profile)
	}
}

// Stop cancels all runners and waits for them to exit.
func (s *Scheduler) Stop() {
	s.mu.Lock()
	if s.cancel != nil {
		s.cancel()
	}
	runners := s.running
	s.mu.Unlock()
	for _, r := range runners {
		r.wait()
	}
}

// Reload re-reads profiles and reconciles the running set: starts new enabled
// profiles, stops removed/disabled ones, and restarts changed ones.
func (s *Scheduler) Reload() {
	s.mu.Lock()
	ctx := s.ctx
	if ctx == nil {
		s.mu.Unlock()
		s.Start()
		s.mu.Lock()
		ctx = s.ctx
	}
	s.mu.Unlock()

	profiles, err := s.store.LoadAll()
	if err != nil {
		log.Printf("[sync/scheduler] reload: %v", err)
		return
	}
	wanted := map[string]SyncProfile{}
	for _, p := range profiles {
		if p.Enabled {
			wanted[p.ID] = p
		}
	}

	s.mu.Lock()
	for id, runner := range s.running {
		if _, ok := wanted[id]; !ok {
			runner.stop()
			delete(s.running, id)
		}
	}
	s.mu.Unlock()

	for id, profile := range wanted {
		s.mu.Lock()
		existing, exists := s.running[id]
		s.mu.Unlock()
		if exists && existing.profileHash() == profileHash(profile) {
			continue
		}
		if exists {
			existing.stop()
		}
		s.startProfile(ctx, profile)
	}
}

// TriggerSync forces an immediate reconcile for one profile, returning the
// op count. It does not wait for completion.
func (s *Scheduler) TriggerSync(profileID string) (int, error) {
	s.mu.Lock()
	runner, ok := s.running[profileID]
	s.mu.Unlock()
	if !ok {
		// Load on demand for ad-hoc sync even when disabled.
		profiles, err := s.store.LoadAll()
		if err != nil {
			return 0, err
		}
		var found SyncProfile
		match := false
		for _, p := range profiles {
			if p.ID == profileID {
				found = p
				match = true
				break
			}
		}
		if !match {
			return 0, fmt.Errorf("sync profile %q not found", profileID)
		}
		return s.runOnce(context.Background(), found)
	}
	return runner.trigger()
}

// RuntimeStates returns the live status of all profiles for the Flutter layer.
func (s *Scheduler) RuntimeStates() []SyncProfileRuntime {
	profiles, err := s.store.LoadAll()
	if err != nil {
		return nil
	}
	out := make([]SyncProfileRuntime, 0, len(profiles))
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, p := range profiles {
		rt := SyncProfileRuntime{SyncProfile: p}
		if runner, ok := s.running[p.ID]; ok {
			rt.Status = runner.status()
			rt.LastSyncAt = runner.lastSyncAt()
			rt.LastError = runner.lastError()
			rt.PendingOps = runner.pendingOps()
			rt.LastOpsCount = runner.lastOpsCount()
		} else if !p.Enabled {
			rt.Status = StatusPaused
		} else {
			rt.Status = StatusIdle
		}
		out = append(out, rt)
	}
	return out
}

// startProfile spawns (or replaces) a runner goroutine for one profile.
func (s *Scheduler) startProfile(ctx context.Context, profile SyncProfile) {
	runner := newProfileRunner(profile, s.store, s.runtimeRoot, s.dispatchOp)
	s.mu.Lock()
	s.running[profile.ID] = runner
	s.mu.Unlock()
	go runner.loop(ctx)
}

// runOnce executes a single reconcile + dispatch synchronously for ad-hoc sync.
func (s *Scheduler) runOnce(ctx context.Context, profile SyncProfile) (int, error) {
	backend := storageops.ForConfig(profileConfig(profile))
	reconciler := NewReconciler(profile, backend, s.runtimeRoot)
	result, err := reconciler.Run(ctx)
	if err != nil {
		return 0, err
	}
	for _, op := range result.Ops {
		s.dispatchOp(ctx, profile, backend, op)
	}
	return len(result.Ops), nil
}

// dispatchOp enqueues a single op into the transfer monitor and executes it.
func (s *Scheduler) dispatchOp(ctx context.Context, profile SyncProfile, backend storageops.Backend, op Op) {
	executor := newOpExecutor(profile, backend, s.runtimeRoot)
	taskID := fmt.Sprintf("sync-%s-%s", profile.ID, op.RelPath)
	if op.Kind == OpRename {
		taskID = fmt.Sprintf("sync-%s-rename-%s", profile.ID, op.RelPath)
	}
	executor.run(ctx, taskID, op)
}

// profileConfig builds a minimal RemoteStorageConfig for backend construction.
// The sync feature references an account profile name to resolve credentials.
func profileConfig(profile SyncProfile) storageconfig.RemoteStorageConfig {
	cfg, err := storageconfig.LoadProfile(profile.AccountProfile)
	if err != nil || cfg.Bucket == "" {
		cfg.Bucket = profile.Bucket
	} else {
		if profile.Bucket != "" {
			cfg.Bucket = profile.Bucket
		}
	}
	return cfg
}

// profileHash produces a compact signature of the schedule-affecting fields.
func profileHash(p SyncProfile) string {
	return fmt.Sprintf("%s|%s|%s|%s|%d|%d|%v",
		p.LocalPath, p.Bucket, p.RemotePrefix, p.Direction,
		p.IntervalSeconds, p.QuietSeconds, p.Enabled)
}

// SaveProfile persists a profile via the store, used by the bridge layer.
func (s *Scheduler) SaveProfile(profile SyncProfile) error {
	return s.store.Upsert(profile)
}

// DeleteProfile removes a profile via the store, used by the bridge layer.
func (s *Scheduler) DeleteProfile(id string) error {
	return s.store.Delete(id)
}
