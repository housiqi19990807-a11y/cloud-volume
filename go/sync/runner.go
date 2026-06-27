// runner.go contains the per-profile goroutine loop: a ticker for periodic
// reconcile plus a quiet-period gate that skips files still being written.
package sync

import (
	"context"
	"log"
	"os"
	"sync"
	"time"

	storageops "remote-storage/go/storage"
)

// dispatchFunc lets the scheduler inject its op-dispatch callback without
// creating an import cycle between scheduler and executor.
type dispatchFunc func(ctx context.Context, profile SyncProfile, backend storageops.Backend, op Op)

// profileRunner owns the reconcile loop and live state for one profile.
type profileRunner struct {
	profile     SyncProfile
	store       Store
	runtimeRoot string
	dispatch    dispatchFunc

	mu           sync.Mutex
	_status      ProfileStatus
	_lastSyncAt  string
	_lastError   string
	_pendingOps  int
	_lastOpsCount int
	stopOnce     sync.Once
	stopCh       chan struct{}
	doneCh       chan struct{}
}

func newProfileRunner(profile SyncProfile, store Store, runtimeRoot string, dispatch dispatchFunc) *profileRunner {
	return &profileRunner{
		profile:     profile,
		store:       store,
		runtimeRoot: runtimeRoot,
		dispatch:    dispatch,
		_status:     StatusIdle,
		stopCh:      make(chan struct{}),
		doneCh:      make(chan struct{}),
	}
}

// loop runs until the context is canceled or stop() is called.
func (r *profileRunner) loop(parent context.Context) {
	defer close(r.doneCh)
	ctx, cancel := context.WithCancel(parent)
	defer cancel()

	interval := time.Duration(r.profile.IntervalSeconds) * time.Second
	if interval < time.Second {
		interval = time.Duration(defaultIntervalSeconds) * time.Second
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	// Run once immediately on start so enabled profiles sync without waiting.
	r.runCycle(ctx)

	for {
		select {
		case <-ctx.Done():
			return
		case <-r.stopCh:
			return
		case <-ticker.C:
			r.runCycle(ctx)
		}
	}
}

// runCycle performs one reconcile + dispatch pass, updating live state.
func (r *profileRunner) runCycle(ctx context.Context) {
	if ctx.Err() != nil {
		return
	}
	r.setStatus(StatusSyncing)
	backend := storageops.ForConfig(profileConfig(r.profile))
	reconciler := NewReconciler(r.profile, backend, r.runtimeRoot)

	result, err := reconciler.Run(ctx)
	if err != nil {
		r.setError(err.Error())
		log.Printf("[sync/runner] %s reconcile failed: %v", r.profile.Name, err)
		return
	}

	r.setPending(len(result.Ops))
	dispatched := 0
	for _, op := range result.Ops {
		if ctx.Err() != nil {
			break
		}
		// Quiet-period gate: re-stat the local file; if still younger than the
		// quiet window it is being actively written, defer to next cycle.
		if r.isHot(ctx, op) {
			log.Printf("[sync/runner] %s skipping hot file %s", r.profile.Name, op.RelPath)
			continue
		}
		r.dispatch(ctx, r.profile, backend, op)
		dispatched++
		r.decPending()
	}
	r.setDone(dispatched)
}

// isHot returns true when a local file involved in the op was modified within
// the profile's quiet window, indicating it is still being written.
func (r *profileRunner) isHot(ctx context.Context, op Op) bool {
	quiet := r.profile.quietDuration()
	if quiet <= 0 {
		return false
	}
	abs := ""
	switch op.Kind {
	case OpUpload, OpRename, OpDeleteLocal:
		abs = localAbsPath(r.profile, op.RelPath)
		if info, err := os.Stat(abs); err == nil && info.IsDir() {
			return false
		}
	default:
		return false
	}
	if abs == "" {
		return false
	}
	return recentlyModified(abs, quiet)
}

// stop signals the loop to exit; safe to call once.
func (r *profileRunner) stop() {
	r.stopOnce.Do(func() { close(r.stopCh) })
}

// wait blocks until the loop goroutine has exited.
func (r *profileRunner) wait() {
	<-r.doneCh
}

// trigger forces an immediate cycle and returns the op count.
func (r *profileRunner) trigger() (int, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	r.runCycle(ctx)
	r.mu.Lock()
	defer r.mu.Unlock()
	return r._lastOpsCount, nil
}

// --- live-state accessors ---

func (r *profileRunner) status() ProfileStatus {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r._status
}
func (r *profileRunner) lastSyncAt() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r._lastSyncAt
}
func (r *profileRunner) lastError() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r._lastError
}
func (r *profileRunner) pendingOps() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r._pendingOps
}
func (r *profileRunner) lastOpsCount() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r._lastOpsCount
}
func (r *profileRunner) profileHash() string {
	return profileHash(r.profile)
}

func (r *profileRunner) setStatus(s ProfileStatus) {
	r.mu.Lock()
	r._status = s
	r.mu.Unlock()
}
func (r *profileRunner) setError(msg string) {
	r.mu.Lock()
	r._status = StatusError
	r._lastError = msg
	r.mu.Unlock()
}
func (r *profileRunner) setPending(n int) {
	r.mu.Lock()
	r._pendingOps = n
	r.mu.Unlock()
}
func (r *profileRunner) decPending() {
	r.mu.Lock()
	if r._pendingOps > 0 {
		r._pendingOps--
	}
	r.mu.Unlock()
}
func (r *profileRunner) setDone(ops int) {
	r.mu.Lock()
	r._status = StatusIdle
	r._lastSyncAt = time.Now().Format(time.RFC3339)
	r._lastOpsCount = ops
	r.mu.Unlock()
}
