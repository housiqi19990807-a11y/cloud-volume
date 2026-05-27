// Share service creates and refreshes presigned download links plus local records.

package share

import (
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

const (
	minDurationSec = 60
	maxDurationSec = 7 * 24 * 60 * 60
)

// List returns all share records stored for the current config namespace.
func List(cfg storageconfig.RemoteStorageConfig) ([]Record, error) {
	return loadRecords(cfg)
}

// Create creates or replaces a share record for the given file.
func Create(
	cfg storageconfig.RemoteStorageConfig,
	bucket string,
	key string,
	name string,
	durationSec int,
) (Record, error) {
	durationSec = normalizeDuration(durationSec)
	bucket = strings.TrimSpace(bucket)
	key = strings.Trim(strings.TrimSpace(key), "/")
	name = strings.TrimSpace(name)
	if bucket == "" || key == "" {
		return Record{}, fmt.Errorf("bucket and key are required")
	}

	records, err := loadRecords(cfg)
	if err != nil {
		return Record{}, err
	}
	now := time.Now().UTC()
	record := findExistingRecord(records, bucket, key)
	if record.ID == "" {
		record.ID = uuid.NewString()
		record.CreatedAt = now.Format(time.RFC3339)
	}
	record.Bucket = bucket
	record.Key = key
	record.Name = fallbackName(name, key)
	record.DurationSec = durationSec
	record.UpdatedAt = now.Format(time.RFC3339)
	record.ExpiresAt = now.Add(time.Duration(durationSec) * time.Second).Format(time.RFC3339)

	url, err := s3ops.GetPresignedURL(cfg, bucket, key, durationSec)
	if err != nil {
		return Record{}, err
	}
	record.URL = url

	records = upsertRecord(records, record)
	if err := saveRecords(cfg, records); err != nil {
		return Record{}, err
	}
	return record, nil
}

// Refresh recreates the presigned link and expiry for one existing record.
func Refresh(cfg storageconfig.RemoteStorageConfig, id string, durationSec int) (Record, error) {
	records, err := loadRecords(cfg)
	if err != nil {
		return Record{}, err
	}
	record, index := findRecordByID(records, strings.TrimSpace(id))
	if index < 0 {
		return Record{}, fmt.Errorf("share record not found")
	}
	updated, err := Create(cfg, record.Bucket, record.Key, record.Name, durationSec)
	if err != nil {
		return Record{}, err
	}
	records[index] = updated
	if err := saveRecords(cfg, records); err != nil {
		return Record{}, err
	}
	return updated, nil
}

// Delete removes one local share record without touching the remote object.
func Delete(cfg storageconfig.RemoteStorageConfig, id string) error {
	records, err := loadRecords(cfg)
	if err != nil {
		return err
	}
	filtered := records[:0]
	for _, record := range records {
		if record.ID == strings.TrimSpace(id) {
			continue
		}
		filtered = append(filtered, record)
	}
	return saveRecords(cfg, filtered)
}

func normalizeDuration(durationSec int) int {
	switch {
	case durationSec < minDurationSec:
		return minDurationSec
	case durationSec > maxDurationSec:
		return maxDurationSec
	default:
		return durationSec
	}
}

func fallbackName(name string, key string) string {
	if name != "" {
		return name
	}
	parts := strings.Split(strings.Trim(key, "/"), "/")
	return parts[len(parts)-1]
}

func findExistingRecord(records []Record, bucket string, key string) Record {
	for _, record := range records {
		if record.Bucket == bucket && record.Key == key {
			return record
		}
	}
	return Record{}
}

func findRecordByID(records []Record, id string) (Record, int) {
	for index, record := range records {
		if record.ID == id {
			return record, index
		}
	}
	return Record{}, -1
}

func upsertRecord(records []Record, target Record) []Record {
	for index, record := range records {
		if record.ID == target.ID {
			records[index] = target
			return records
		}
	}
	return append(records, target)
}
