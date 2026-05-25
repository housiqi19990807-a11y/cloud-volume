package main

import (
	"encoding/json"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
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
	if err := s3ops.CopyObject(
		input.Config,
		input.Bucket,
		input.SourceKey,
		input.TargetKey,
		input.IsDirectory,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func moveObject(args json.RawMessage) (any, error) {
	var input objectTransferArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := s3ops.MoveObjectWithTask(
		input.Config,
		input.Bucket,
		input.SourceKey,
		input.TargetKey,
		input.IsDirectory,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}
