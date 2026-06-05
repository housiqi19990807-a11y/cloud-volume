package main

import (
	"encoding/json"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

// Trash bridge methods expose app-level soft delete and recovery flows to Flutter.
type trashListArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
}

type trashMutationArgs struct {
	Config  storageconfig.RemoteStorageConfig `json:"config"`
	Bucket  string                            `json:"bucket"`
	TrashID string                            `json:"trashId"`
}

func listTrash(args json.RawMessage) (any, error) {
	var input trashListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return s3ops.ListTrash(input.Config, input.Bucket)
}

func restoreTrashItem(args json.RawMessage) (any, error) {
	var input trashMutationArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := s3ops.RestoreTrashItem(input.Config, input.Bucket, input.TrashID); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func deleteTrashItem(args json.RawMessage) (any, error) {
	var input trashMutationArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := s3ops.DeleteTrashItem(input.Config, input.Bucket, input.TrashID); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func clearTrash(args json.RawMessage) (any, error) {
	var input trashListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := s3ops.ClearTrash(input.Config, input.Bucket); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}
