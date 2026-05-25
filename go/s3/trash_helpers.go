// Trash helpers centralize the bucket-level app trash prefix and metadata keys.
package s3

import (
	"encoding/json"
	"fmt"
	"path"
	"strings"
	"time"

	storageconfig "remote-storage/go/config"
)

const trashMetadataSuffix = ".trashinfo.json"

type trashMetadata struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	OriginalKey string `json:"originalKey"`
	TrashKey    string `json:"trashKey"`
	DeletedAt   string `json:"deletedAt"`
	IsDir       bool   `json:"isDir"`
	Size        int64  `json:"size"`
	ObjectCount int    `json:"objectCount"`
}

func trashPrefix(cfg storageconfig.RemoteStorageConfig) string {
	name := strings.Trim(strings.TrimSpace(cfg.TrashDirectoryName), "/")
	if name == "" {
		name = ".trash"
	}
	return ensureRemoteDirSuffix(name)
}

func trashObjectsPrefix(cfg storageconfig.RemoteStorageConfig) string {
	return trashPrefix(cfg) + "objects/"
}

func trashMetadataPrefix(cfg storageconfig.RemoteStorageConfig) string {
	return trashPrefix(cfg) + "entries/"
}

func trashObjectTarget(cfg storageconfig.RemoteStorageConfig, id, originalKey string) string {
	base := strings.Trim(strings.TrimSpace(originalKey), "/")
	if base == "" {
		base = "_root"
	}
	return trashObjectsPrefix(cfg) + id + "/" + base
}

func trashMetadataKey(cfg storageconfig.RemoteStorageConfig, id string) string {
	return trashMetadataPrefix(cfg) + id + trashMetadataSuffix
}

func buildTrashMetadata(
	id string,
	name string,
	originalKey string,
	targetKey string,
	isDir bool,
	size int64,
	objectCount int,
) trashMetadata {
	return trashMetadata{
		ID:          id,
		Name:        name,
		OriginalKey: strings.Trim(strings.TrimSpace(originalKey), "/"),
		TrashKey:    strings.Trim(strings.TrimSpace(targetKey), "/"),
		DeletedAt:   time.Now().UTC().Format(time.RFC3339),
		IsDir:       isDir,
		Size:        size,
		ObjectCount: objectCount,
	}
}

func parseTrashMetadata(data []byte) (trashMetadata, error) {
	var metadata trashMetadata
	if err := json.Unmarshal(data, &metadata); err != nil {
		return trashMetadata{}, err
	}
	metadata.ID = strings.TrimSpace(metadata.ID)
	metadata.Name = strings.TrimSpace(metadata.Name)
	metadata.OriginalKey = strings.Trim(strings.TrimSpace(metadata.OriginalKey), "/")
	metadata.TrashKey = strings.Trim(strings.TrimSpace(metadata.TrashKey), "/")
	return metadata, nil
}

func trashItemFromMetadata(metadata trashMetadata) TrashItem {
	return TrashItem{
		ID:          metadata.ID,
		Name:        metadata.Name,
		OriginalKey: metadata.OriginalKey,
		TrashKey:    metadata.TrashKey,
		DeletedAt:   metadata.DeletedAt,
		IsDir:       metadata.IsDir,
		Size:        metadata.Size,
		ObjectCount: metadata.ObjectCount,
	}
}

func encodeTrashMetadata(metadata trashMetadata) ([]byte, error) {
	payload, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("encode trash metadata: %w", err)
	}
	return payload, nil
}

func isTrashKey(cfg storageconfig.RemoteStorageConfig, key string) bool {
	trimmed := strings.Trim(strings.TrimSpace(key), "/")
	if trimmed == "" {
		return false
	}
	prefix := strings.TrimSuffix(trashPrefix(cfg), "/")
	return trimmed == prefix || strings.HasPrefix(trimmed, prefix+"/")
}

func trashDisplayName(originalKey string) string {
	trimmed := strings.Trim(strings.TrimSpace(originalKey), "/")
	if trimmed == "" {
		return "/"
	}
	return path.Base(trimmed)
}
