// Share store persists per-config share records inside the app runtime directory.

package share

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	storageconfig "remote-storage/go/config"
)

const sharesDirName = "shares"

func loadRecords(cfg storageconfig.RemoteStorageConfig) ([]Record, error) {
	path, err := recordsPath(cfg)
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return []Record{}, nil
		}
		return nil, fmt.Errorf("read share records: %w", err)
	}
	var records []Record
	if err := json.Unmarshal(data, &records); err != nil {
		return nil, fmt.Errorf("parse share records: %w", err)
	}
	sortRecords(records)
	return records, nil
}

func saveRecords(cfg storageconfig.RemoteStorageConfig, records []Record) error {
	path, err := recordsPath(cfg)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create shares dir: %w", err)
	}
	sortRecords(records)
	payload, err := json.MarshalIndent(records, "", "  ")
	if err != nil {
		return fmt.Errorf("encode share records: %w", err)
	}
	if err := os.WriteFile(path, payload, 0o600); err != nil {
		return fmt.Errorf("write share records: %w", err)
	}
	return nil
}

func recordsPath(cfg storageconfig.RemoteStorageConfig) (string, error) {
	runtimeDir, err := storageconfig.RuntimeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(runtimeDir, sharesDirName, namespaceForConfig(cfg)+".json"), nil
}

func namespaceForConfig(cfg storageconfig.RemoteStorageConfig) string {
	sum := sha1.Sum([]byte(strings.Join([]string{
		strings.TrimSpace(cfg.Endpoint),
		strings.TrimSpace(cfg.Region),
		strings.TrimSpace(cfg.Bucket),
		strings.TrimSpace(cfg.RootPrefix),
		strings.TrimSpace(cfg.AccessKeyID),
	}, "\n")))
	return hex.EncodeToString(sum[:])
}

func sortRecords(records []Record) {
	sort.Slice(records, func(i, j int) bool {
		if records[i].UpdatedAt == records[j].UpdatedAt {
			return records[i].ID < records[j].ID
		}
		return records[i].UpdatedAt > records[j].UpdatedAt
	})
}
