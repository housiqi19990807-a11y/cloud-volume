package main

import (
	"encoding/json"
	"fmt"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

type saveConfigArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

// invokeBridgeMethod translates JSON RPC-like method names into typed Go operations.
func invokeBridgeMethod(method string, args json.RawMessage) (any, error) {
	switch method {
	case "load_bootstrap_state":
		return loadBootstrapState()
	case "save_config":
		return saveConfig(args)
	case "list_buckets":
		return listBuckets(args)
	case "list_objects":
		return listObjects(args)
	case "upload_file":
		return uploadFile(args)
	case "download_file":
		return downloadFile(args)
	default:
		return nil, fmt.Errorf("unsupported bridge method %q", method)
	}
}

func loadBootstrapState() (storageconfig.BootstrapState, error) {
	store, err := storageconfig.NewDefaultStore()
	if err != nil {
		return storageconfig.BootstrapState{}, err
	}
	return store.LoadBootstrapState()
}

func saveConfig(args json.RawMessage) (storageconfig.BootstrapState, error) {
	store, err := storageconfig.NewDefaultStore()
	if err != nil {
		return storageconfig.BootstrapState{}, err
	}
	var input saveConfigArgs
	if err := decodeArgs(args, &input); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	if err := store.Save(input.Config); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	return store.LoadBootstrapState()
}

// --- S3 operations ---

type configArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

type bucketArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

type objectListArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                           `json:"bucket"`
	Prefix string                           `json:"prefix"`
}

type uploadArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                           `json:"bucket"`
	Key       string                           `json:"key"`
	LocalPath string                           `json:"localPath"`
}

type downloadArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                           `json:"bucket"`
	Key       string                           `json:"key"`
	LocalPath string                           `json:"localPath"`
}

func listBuckets(args json.RawMessage) (any, error) {
	var input bucketArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return s3ops.ListBuckets(input.Config)
}

func listObjects(args json.RawMessage) (any, error) {
	var input objectListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return s3ops.ListObjects(input.Config, input.Bucket, input.Prefix)
}

func uploadFile(args json.RawMessage) (any, error) {
	var input uploadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := s3ops.UploadFile(input.Config, input.Bucket, input.Key, input.LocalPath); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func downloadFile(args json.RawMessage) (any, error) {
	var input downloadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := s3ops.DownloadFile(input.Config, input.Bucket, input.Key, input.LocalPath); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}
