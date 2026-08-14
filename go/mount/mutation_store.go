// Mutation store owns crash-tolerant append-only JSONL logs under the session root.
package mount

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// mutationStoreDirName is the directory under the session runtime root.
const mutationStoreDirName = "mutations"

// mutationStore appends one versioned event per line, flushes and fsyncs every
// append, and compacts live records after recovery so stale process logs can be
// removed without losing pending work.
type mutationStore struct {
	dirPath  string
	filePath string
}

func openMutationStore(dirPath string) (*mutationStore, error) {
	if err := os.MkdirAll(dirPath, 0o755); err != nil {
		return nil, fmt.Errorf("create mutation store dir: %w", err)
	}
	filePath := filepath.Join(dirPath, fmt.Sprintf("queue-%d.jsonl", os.Getpid()))
	file, err := os.OpenFile(filePath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open mutation store %q: %w", filePath, err)
	}
	// An empty per-process log is fine; creating it up front marks ownership.
	if err := file.Close(); err != nil {
		return nil, fmt.Errorf("close new mutation store: %w", err)
	}
	return &mutationStore{dirPath: dirPath, filePath: filePath}, nil
}

func encodeMutationEvent(event mutationEvent) (string, error) {
	payload, err := json.Marshal(event)
	if err != nil {
		return "", fmt.Errorf("encode mutation event: %w", err)
	}
	return string(payload), nil
}

// Upsert appends the current record state and syncs it to disk.
func (s *mutationStore) Upsert(record mutationRecord) error {
	return s.appendEvent(mutationEvent{Kind: mutationEventUpsert, Record: record})
}

// Complete appends a verified-success tombstone for one mutation ID.
func (s *mutationStore) Complete(id string) error {
	return s.appendEvent(mutationEvent{
		Kind:   mutationEventComplete,
		Record: mutationRecord{ID: id},
	})
}

func (s *mutationStore) appendEvent(event mutationEvent) error {
	if s == nil {
		return nil
	}
	line, err := encodeMutationEvent(event)
	if err != nil {
		return err
	}
	file, err := os.OpenFile(s.filePath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return fmt.Errorf("open mutation store %q: %w", s.filePath, err)
	}
	defer file.Close()
	if _, err := file.WriteString(line + "\n"); err != nil {
		return fmt.Errorf("append mutation event: %w", err)
	}
	if err := file.Sync(); err != nil {
		return fmt.Errorf("sync mutation event: %w", err)
	}
	return nil
}

// Restore replays every queue-*.jsonl log in file order, tolerating exactly one
// unterminated final line per file (a crash mid-append). Interior malformed
// data and unsupported versions are hard errors: silently skipping them could
// resurrect or drop a pending remote move.
func (s *mutationStore) Restore() (map[string]mutationRecord, error) {
	if s == nil {
		return map[string]mutationRecord{}, nil
	}
	files, err := filepath.Glob(filepath.Join(s.dirPath, "queue-*.jsonl"))
	if err != nil {
		return nil, fmt.Errorf("glob mutation stores: %w", err)
	}
	sort.Strings(files)
	live := map[string]mutationRecord{}
	for _, filePath := range files {
		if err := restoreMutationFile(filePath, live); err != nil {
			return nil, err
		}
	}
	return live, nil
}

func restoreMutationFile(filePath string, live map[string]mutationRecord) error {
	file, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("open mutation store %q: %w", filePath, err)
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 64*1024), 4*1024*1024)
	pendingLine := ""
	for scanner.Scan() {
		line := scanner.Text()
		if pendingLine != "" {
			// The previous line had no trailing newline only if it was last;
			// reaching here means it was interior data after all.
			if err := applyMutationLine(pendingLine, live); err != nil {
				return fmt.Errorf("mutation store %q: %w", filePath, err)
			}
		}
		pendingLine = line
	}
	if err := scanner.Err(); err != nil {
		return fmt.Errorf("read mutation store %q: %w", filePath, err)
	}
	if pendingLine != "" {
		if err := applyMutationLine(pendingLine, live); err != nil {
			// A torn final append is the only tolerable corruption. Detect it
			// by checking whether the file ends without a newline; the scanner
			// cannot report that, so stat the file size versus scanned bytes.
			if mutationFileEndsWithNewline(filePath) {
				return fmt.Errorf("mutation store %q: %w", filePath, err)
			}
			// Ignore the torn tail; it carries no committed event.
		}
	}
	return nil
}

func mutationFileEndsWithNewline(filePath string) bool {
	file, err := os.Open(filePath)
	if err != nil {
		return false
	}
	defer file.Close()
	offset, err := file.Seek(0, io.SeekEnd)
	if err != nil || offset == 0 {
		return false
	}
	var tail [1]byte
	if _, err := file.ReadAt(tail[:], offset-1); err != nil {
		return false
	}
	return tail[0] == '\n'
}

func applyMutationLine(line string, live map[string]mutationRecord) error {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return nil
	}
	var event mutationEvent
	if err := json.Unmarshal([]byte(trimmed), &event); err != nil {
		return fmt.Errorf("decode line %q: %w", trimmed, err)
	}
	switch event.Kind {
	case mutationEventComplete:
		if event.Record.ID != "" {
			delete(live, event.Record.ID)
		}
		return nil
	case mutationEventUpsert:
		record := event.Record
		if record.ID == "" {
			return fmt.Errorf("upsert without id: %q", trimmed)
		}
		if record.Version > mutationRecordVersion {
			return fmt.Errorf("unsupported mutation record version %d", record.Version)
		}
		live[record.ID] = record
		return nil
	default:
		return fmt.Errorf("unknown mutation event kind %q", event.Kind)
	}
}

// Compact writes live records into one uniquely named file and removes every
// other queue-*.jsonl log. It never renames over an existing file on Windows.
func (s *mutationStore) Compact(live map[string]mutationRecord) error {
	if s == nil {
		return nil
	}
	compactPath := filepath.Join(
		s.dirPath,
		fmt.Sprintf("queue-%d-%d.jsonl", os.Getpid(), time.Now().UnixNano()),
	)
	file, err := os.OpenFile(compactPath, os.O_CREATE|os.O_WRONLY|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("create compacted mutation store %q: %w", compactPath, err)
	}
	writer := bufio.NewWriter(file)
	ids := make([]string, 0, len(live))
	for id := range live {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		line, err := encodeMutationEvent(mutationEvent{
			Kind:   mutationEventUpsert,
			Record: live[id],
		})
		if err != nil {
			_ = file.Close()
			_ = os.Remove(compactPath)
			return err
		}
		if _, err := writer.WriteString(line + "\n"); err != nil {
			_ = file.Close()
			_ = os.Remove(compactPath)
			return fmt.Errorf("write compacted mutation store: %w", err)
		}
	}
	if err := writer.Flush(); err != nil {
		_ = file.Close()
		_ = os.Remove(compactPath)
		return fmt.Errorf("flush compacted mutation store: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		_ = os.Remove(compactPath)
		return fmt.Errorf("sync compacted mutation store: %w", err)
	}
	if err := file.Close(); err != nil {
		_ = os.Remove(compactPath)
		return fmt.Errorf("close compacted mutation store: %w", err)
	}

	s.filePath = compactPath
	files, err := filepath.Glob(filepath.Join(s.dirPath, "queue-*.jsonl"))
	if err != nil {
		return fmt.Errorf("glob mutation stores for cleanup: %w", err)
	}
	for _, stale := range files {
		if filepath.Clean(stale) == filepath.Clean(compactPath) {
			continue
		}
		if err := os.Remove(stale); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("remove stale mutation store %q: %w", stale, err)
		}
	}
	return nil
}

// Close releases the store; every append already opened its own handle.
func (s *mutationStore) Close() error {
	return nil
}
