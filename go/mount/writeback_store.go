// Persistent writeback storage keeps mounted uploads resumable across unmounts.
package mount

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	bolt "go.etcd.io/bbolt"

	"github.com/panjf2000/ants/v2"
)

var globalWritebackRegistry = &writebackRegistry{
	queues: map[string]*writebackQueue{},
}

var writebackBucketName = []byte("writebacks")

type writebackRegistry struct {
	mu     sync.Mutex
	queues map[string]*writebackQueue
}

type writebackStore struct {
	db *bolt.DB
}

type writebackRecord struct {
	TaskID          string `json:"taskId"`
	VirtualPath     string `json:"virtualPath"`
	LocalPath       string `json:"localPath"`
	Size            int64  `json:"size"`
	ModTimeUnixNano int64  `json:"modTimeUnixNano"`
	DueAtUnixNano   int64  `json:"dueAtUnixNano"`
	RetryCount      int    `json:"retryCount"`
}

func acquireWritebackQueue(access *bucketAccess) (*writebackQueue, error) {
	storePath := filepath.Join(access.sessionRoot, "writeback.db")

	globalWritebackRegistry.mu.Lock()
	if existing, ok := globalWritebackRegistry.queues[storePath]; ok {
		globalWritebackRegistry.mu.Unlock()
		existing.attach(access)
		return existing, nil
	}
	globalWritebackRegistry.mu.Unlock()

	store, err := openWritebackStore(storePath)
	if err != nil {
		return nil, err
	}
	pool, err := ants.NewPool(access.config.WindowsWritebackConcurrency)
	if err != nil {
		_ = store.close()
		return nil, fmt.Errorf("create writeback worker pool: %w", err)
	}
	q := &writebackQueue{
		store:    store,
		storeKey: storePath,
		entries:  map[string]*pendingWriteback{},
		running:  map[string]*pendingWriteback{},
		queue:    make(chan *pendingWriteback, 512),
		pool:     pool,
	}
	q.attach(access)
	if err := q.restorePersistedEntries(); err != nil {
		q.closeResources()
		return nil, err
	}
	q.wg.Add(1)
	go q.dispatch()

	globalWritebackRegistry.mu.Lock()
	globalWritebackRegistry.queues[storePath] = q
	globalWritebackRegistry.mu.Unlock()
	return q, nil
}

func openWritebackStore(path string) (*writebackStore, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("create writeback store dir: %w", err)
	}
	db, err := bolt.Open(path, 0o600, &bolt.Options{Timeout: 2 * time.Second})
	if err != nil {
		return nil, fmt.Errorf("open writeback store %q: %w", path, err)
	}
	store := &writebackStore{db: db}
	if err := db.Update(func(tx *bolt.Tx) error {
		_, err := tx.CreateBucketIfNotExists(writebackBucketName)
		return err
	}); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("init writeback store %q: %w", path, err)
	}
	return store, nil
}

func (q *writebackQueue) attach(access *bucketAccess) {
	if access == nil {
		return
	}
	q.accessMu.Lock()
	q.access = access
	q.accessMu.Unlock()

	paths := q.pendingPaths()
	for _, path := range paths {
		access.projectSyncState(path, false)
	}
}

func (q *writebackQueue) currentAccess() *bucketAccess {
	q.accessMu.RLock()
	defer q.accessMu.RUnlock()
	return q.access
}

func (q *writebackQueue) restorePersistedEntries() error {
	records, err := q.store.list()
	if err != nil {
		return err
	}
	now := time.Now()
	for _, record := range records {
		entry := record.toPendingWriteback()
		if entry.virtualPath == "" || entry.taskID == "" {
			continue
		}
		q.entries[entry.virtualPath] = entry
		s3opsQueueTransferForEntry(q.currentAccess(), entry)
		delay := time.Until(entry.dueAt)
		if entry.dueAt.IsZero() || delay < 0 {
			delay = 0
			entry.dueAt = now
		}
		q.armTimerLocked(entry, delay)
	}
	return nil
}

func (q *writebackQueue) pendingPaths() []string {
	q.mu.Lock()
	defer q.mu.Unlock()

	paths := make([]string, 0, len(q.entries)+len(q.running))
	for path := range q.entries {
		paths = append(paths, path)
	}
	for _, entry := range q.running {
		paths = append(paths, entry.virtualPath)
	}
	return paths
}

func (q *writebackQueue) unregister() {
	globalWritebackRegistry.mu.Lock()
	defer globalWritebackRegistry.mu.Unlock()
	delete(globalWritebackRegistry.queues, q.storeKey)
}

func (q *writebackQueue) closeResources() {
	if q.pool != nil {
		q.pool.Release()
	}
	if q.store != nil {
		_ = q.store.close()
	}
	q.unregister()
}

func (s *writebackStore) upsert(entry *pendingWriteback) error {
	if s == nil || entry == nil {
		return nil
	}
	record := writebackRecord{
		TaskID:          entry.taskID,
		VirtualPath:     entry.virtualPath,
		LocalPath:       entry.localPath,
		Size:            entry.size,
		ModTimeUnixNano: entry.modTimeUnixNano,
		DueAtUnixNano:   entry.dueAt.UnixNano(),
		RetryCount:      entry.retryCount,
	}
	payload, err := json.Marshal(record)
	if err != nil {
		return err
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(writebackBucketName).Put([]byte(entry.virtualPath), payload)
	})
}

func (s *writebackStore) delete(virtualPath string) error {
	if s == nil || virtualPath == "" {
		return nil
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		return tx.Bucket(writebackBucketName).Delete([]byte(virtualPath))
	})
}

func (s *writebackStore) list() ([]writebackRecord, error) {
	if s == nil {
		return nil, nil
	}
	records := []writebackRecord{}
	err := s.db.View(func(tx *bolt.Tx) error {
		return tx.Bucket(writebackBucketName).ForEach(func(_, value []byte) error {
			record := writebackRecord{}
			if err := json.Unmarshal(value, &record); err != nil {
				return err
			}
			records = append(records, record)
			return nil
		})
	})
	return records, err
}

func (s *writebackStore) close() error {
	if s == nil || s.db == nil {
		return nil
	}
	return s.db.Close()
}

func (r writebackRecord) toPendingWriteback() *pendingWriteback {
	return &pendingWriteback{
		taskID:          r.TaskID,
		virtualPath:     cleanVirtualPath(r.VirtualPath),
		localPath:       r.LocalPath,
		size:            r.Size,
		modTimeUnixNano: r.ModTimeUnixNano,
		dueAt:           time.Unix(0, r.DueAtUnixNano),
		retryCount:      r.RetryCount,
	}
}
