package main

import (
	"context"
	"encoding/json"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	storageops "remote-storage/go/storage"
)

// Object transfer bridge methods expose tracked copy/move operations to Flutter.
type objectTransferArgs struct {
	Config      storageconfig.RemoteStorageConfig `json:"config"`
	Bucket      string                            `json:"bucket"`
	SourceKey   string                            `json:"sourceKey"`
	TargetKey   string                            `json:"targetKey"`
	IsDirectory bool                              `json:"isDirectory"`
	TaskID      string                            `json:"taskId"`
}

func copyObject(args json.RawMessage) (any, error) {
	var input objectTransferArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).CopyObject(
		context.Background(),
		input.Bucket,
		input.SourceKey,
		input.TargetKey,
		input.IsDirectory,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	// Sync mount caches so the new copy at the target key becomes visible.
	bucketmount.NotifyExternalUpload(input.Config, input.Bucket, input.TargetKey, input.IsDirectory)
	return map[string]any{"ok": true}, nil
}

func moveObject(args json.RawMessage) (any, error) {
	var input objectTransferArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).MoveObject(
		context.Background(),
		input.Bucket,
		input.SourceKey,
		input.TargetKey,
		input.IsDirectory,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	// Sync mount caches: source disappears and target appears.
	bucketmount.NotifyExternalRename(input.Config, input.Bucket, input.SourceKey, input.TargetKey, input.IsDirectory)
	return map[string]any{"ok": true}, nil
}
