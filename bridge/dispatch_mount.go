package main

import (
	"encoding/json"
	"log"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
)

type mountBucketArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
}

type bucketMountArgs struct {
	Bucket string `json:"bucket"`
}

// Mount bridge methods keep the Flutter layer thin while the Go session owns lifecycle state.
func mountBucket(args json.RawMessage) (any, error) {
	var input mountBucketArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	log.Printf("[bridge/mount] mount bucket=%q", input.Bucket)
	return bucketmount.MountBucket(input.Config, input.Bucket)
}

func unmountBucket(args json.RawMessage) (any, error) {
	var input bucketMountArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	log.Printf("[bridge/mount] unmount bucket=%q", input.Bucket)
	return bucketmount.UnmountBucket(input.Bucket)
}

func getBucketMountStatus(args json.RawMessage) (any, error) {
	var input bucketMountArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return bucketmount.GetBucketMountStatus(input.Bucket)
}

func openBucketMount(args json.RawMessage) (any, error) {
	var input bucketMountArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	log.Printf("[bridge/mount] open bucket=%q", input.Bucket)
	return bucketmount.OpenBucketMount(input.Bucket)
}

func cleanupMounts() (any, error) {
	log.Printf("[bridge/mount] cleanup")
	if err := bucketmount.CleanupMounts(); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}
