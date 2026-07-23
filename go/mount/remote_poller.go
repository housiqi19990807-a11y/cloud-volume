// Remote directory polling is the P0 cross-client change-discovery fallback.
package mount

import (
	"context"
	"log"
	"sort"
	"sync"
	"time"
)

const (
	remotePollActiveWindow = 45 * time.Second
	remotePollWarmWindow   = 3 * time.Minute
	remotePollActiveDelay  = 5 * time.Second
	remotePollWarmDelay    = 30 * time.Second
	remotePollIdleDelay    = 2 * time.Minute
	remotePollDirectoryCap = 12
)

// directoryActivityTracker records the small working set of directories the
// user has actually opened. P0 never enumerates a whole bucket in the
// background, which keeps idle mounts cheap even for large object stores.
type directoryActivityTracker struct {
	mu   sync.Mutex
	dirs map[string]time.Time
}

func newDirectoryActivityTracker() *directoryActivityTracker {
	return &directoryActivityTracker{dirs: make(map[string]time.Time)}
}

func (t *directoryActivityTracker) note(prefix string) {
	if t == nil {
		return
	}
	t.noteAt(prefix, time.Now())
}

func (t *directoryActivityTracker) noteAt(prefix string, at time.Time) {
	if t == nil {
		return
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.dirs == nil {
		t.dirs = make(map[string]time.Time)
	}
	t.dirs[cleanVirtualPath(prefix)] = at
	if len(t.dirs) <= remotePollDirectoryCap {
		return
	}
	oldestPrefix := ""
	var oldest time.Time
	for candidate, seenAt := range t.dirs {
		if oldestPrefix == "" || seenAt.Before(oldest) {
			oldestPrefix, oldest = candidate, seenAt
		}
	}
	delete(t.dirs, oldestPrefix)
}

func (t *directoryActivityTracker) recent(now time.Time) []string {
	if t == nil {
		return nil
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	prefixes := make([]string, 0, len(t.dirs))
	for prefix, seenAt := range t.dirs {
		if now.Sub(seenAt) > remotePollWarmWindow {
			delete(t.dirs, prefix)
			continue
		}
		prefixes = append(prefixes, prefix)
	}
	sort.Strings(prefixes)
	return prefixes
}

func (t *directoryActivityTracker) nextDelay(now time.Time) time.Duration {
	if t == nil {
		return remotePollIdleDelay
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	mostRecent := time.Time{}
	for prefix, seenAt := range t.dirs {
		if now.Sub(seenAt) > remotePollWarmWindow {
			delete(t.dirs, prefix)
			continue
		}
		if seenAt.After(mostRecent) {
			mostRecent = seenAt
		}
	}
	if mostRecent.IsZero() {
		return remotePollIdleDelay
	}
	if now.Sub(mostRecent) <= remotePollActiveWindow {
		return remotePollActiveDelay
	}
	return remotePollWarmDelay
}

func (a *bucketAccess) noteDirectoryActivity(prefix string) {
	if a != nil {
		a.directoryActivity.note(prefix)
	}
}

func (a *bucketAccess) pollRemoteDirectory(
	ctx context.Context,
	virtualPrefix string,
) error {
	if a == nil {
		return nil
	}
	items, err := a.fetchDirectory(ctx, virtualPrefix)
	if err != nil {
		return err
	}
	a.cache.storeList(virtualPrefix, items)
	if a.externalDirectoryRefresh != nil {
		if err := a.externalDirectoryRefresh(cleanVirtualPath(virtualPrefix), items); err != nil {
			return err
		}
	}
	return nil
}

// remoteDirectoryPoller ties the active-directory tracker to a mount session.
// It is deliberately a cache refresh mechanism, not a second sync engine: the
// remote object store remains authoritative and local writeback is never pruned.
type remoteDirectoryPoller struct {
	access *bucketAccess
	bucket string
	ctx    context.Context
	cancel context.CancelFunc
	stopCh chan struct{}
	doneCh chan struct{}
	once   sync.Once
}

func newRemoteDirectoryPoller(session *mountSession) *remoteDirectoryPoller {
	if session == nil {
		return nil
	}
	ctx, cancel := context.WithCancel(context.Background())
	return &remoteDirectoryPoller{
		access: session.access,
		bucket: session.bucket,
		ctx:    ctx,
		cancel: cancel,
		stopCh: make(chan struct{}),
		doneCh: make(chan struct{}),
	}
}

func (p *remoteDirectoryPoller) Start() {
	if p == nil || p.access == nil {
		return
	}
	go p.run()
}

func (p *remoteDirectoryPoller) Stop() {
	if p == nil {
		return
	}
	if p.cancel != nil {
		p.cancel()
	}
	p.once.Do(func() { close(p.stopCh) })
	<-p.doneCh
}

func (p *remoteDirectoryPoller) run() {
	defer close(p.doneCh)
	for {
		delay := p.access.directoryActivity.nextDelay(time.Now())
		timer := time.NewTimer(delay)
		select {
		case <-p.stopCh:
			timer.Stop()
			return
		case <-timer.C:
			p.pollOnce(p.ctx)
		}
	}
}

func (p *remoteDirectoryPoller) pollOnce(ctx context.Context) {
	if p == nil || p.access == nil {
		return
	}
	for _, prefix := range p.access.directoryActivity.recent(time.Now()) {
		if err := p.access.pollRemoteDirectory(ctx, prefix); err != nil {
			log.Printf("[mount/poll] refresh-error bucket=%q prefix=%q err=%v", p.bucket, prefix, err)
			continue
		}
		log.Printf("[mount/poll] refresh-done bucket=%q prefix=%q", p.bucket, prefix)
	}
}
