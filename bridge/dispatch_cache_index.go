package main

import (
	"encoding/json"

	storageconfig "remote-storage/go/config"
)

// Preview-cache index bridge handlers keep Dart away from local DB details.

type cacheIndexKeyArgs struct {
	Bucket    string `json:"bucket"`
	ObjectKey string `json:"objectKey"`
}

type cacheIndexPrefixArgs struct {
	Bucket          string `json:"bucket"`
	ObjectKeyPrefix string `json:"objectKeyPrefix"`
}

type cacheIndexUpsertArgs struct {
	Record storageconfig.CacheIndexRecord `json:"record"`
}

func cacheIndexFind(args json.RawMessage) (any, error) {
	var input cacheIndexKeyArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageconfig.FindCacheIndexRecord(input.Bucket, input.ObjectKey)
}

func cacheIndexUpsert(args json.RawMessage) (any, error) {
	var input cacheIndexUpsertArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.UpsertCacheIndexRecord(input.Record); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func cacheIndexRemove(args json.RawMessage) (any, error) {
	var input cacheIndexKeyArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.RemoveCacheIndexRecord(input.Bucket, input.ObjectKey); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func cacheIndexRemovePrefix(args json.RawMessage) (any, error) {
	var input cacheIndexPrefixArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageconfig.RemoveCacheIndexPrefix(input.Bucket, input.ObjectKeyPrefix)
}
