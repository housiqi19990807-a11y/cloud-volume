package main

import (
	"encoding/json"

	storageconfig "remote-storage/go/config"
	shareops "remote-storage/go/share"
)

// Share bridge methods expose local share-record management backed by presigned URLs.
type createShareArgs struct {
	Config      storageconfig.RemoteStorageConfig `json:"config"`
	Bucket      string                            `json:"bucket"`
	Key         string                            `json:"key"`
	Name        string                            `json:"name"`
	DurationSec int                               `json:"durationSec"`
}

type shareListArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

type updateShareArgs struct {
	Config      storageconfig.RemoteStorageConfig `json:"config"`
	ID          string                            `json:"id"`
	DurationSec int                               `json:"durationSec"`
}

type deleteShareArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	ID     string                            `json:"id"`
}

func createShare(args json.RawMessage) (any, error) {
	var input createShareArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return shareops.Create(
		input.Config,
		input.Bucket,
		input.Key,
		input.Name,
		input.DurationSec,
	)
}

func listShares(args json.RawMessage) (any, error) {
	var input shareListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return shareops.List(input.Config)
}

func refreshShare(args json.RawMessage) (any, error) {
	var input updateShareArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return shareops.Refresh(input.Config, input.ID, input.DurationSec)
}

func deleteShare(args json.RawMessage) (any, error) {
	var input deleteShareArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := shareops.Delete(input.Config, input.ID); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}
