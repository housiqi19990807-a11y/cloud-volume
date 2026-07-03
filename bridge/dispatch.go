package main

import (
	"context"
	"encoding/json"
	"fmt"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	s3ops "remote-storage/go/s3"
	storageops "remote-storage/go/storage"
)

// invokeBridgeMethod translates JSON RPC-like method names into typed Go operations.
func invokeBridgeMethod(method string, args json.RawMessage) (any, error) {
	switch method {
	case "get_build_info":
		return getBuildInfo()
	case "load_bootstrap_state":
		return loadBootstrapState()
	case "save_config":
		return saveConfig(args)
	case "update_proxy_settings":
		return updateProxySettings(args)
	case "migrate_default":
		return migrateAndBootstrap()
	// Profile management.
	case "list_profiles":
		return listProfiles()
	case "load_profile":
		return loadProfile(args)
	case "save_profile":
		return saveProfile(args)
	case "start_baidu_pan_authorization":
		return startBaiduPanAuthorization()
	case "authorize_baidu_pan":
		return authorizeBaiduPan(args)
	case "delete_profile":
		return deleteProfile(args)
	case "reset_user_config":
		return resetUserConfig(args)
	case "set_active_profile":
		return setActiveProfile(args)
	// Storage operations.
	case "list_buckets":
		return listBuckets(args)
	case "list_objects":
		return listObjects(args)
	case "list_object_page":
		return listObjectPage(args)
	case "head_object":
		return headObject(args)
	case "directory_access":
		return directoryAccess(args)
	case "create_directory":
		return createDirectory(args)
	case "delete_object":
		return deleteObject(args)
	case "list_trash":
		return listTrash(args)
	case "list_trash_page":
		return listTrashPage(args)
	case "restore_trash_item":
		return restoreTrashItem(args)
	case "delete_trash_item":
		return deleteTrashItem(args)
	case "clear_trash":
		return clearTrash(args)
	case "create_share":
		return createShare(args)
	case "list_shares":
		return listShares(args)
	case "refresh_share":
		return refreshShare(args)
	case "delete_share":
		return deleteShare(args)
	case "rename_object":
		return renameObject(args)
	case "copy_object":
		return copyObject(args)
	case "move_object":
		return moveObject(args)
	case "upload_file":
		return uploadFile(args)
	case "upload_directory":
		return uploadDirectory(args)
	case "download_file":
		return downloadFile(args)
	case "list_transfer_jobs":
		return listTransferJobs()
	case "cancel_transfer":
		return cancelTransfer(args)
	case "trigger_transfer":
		return triggerTransfer(args)
	// Bucket mounts.
	case "mount_bucket":
		return mountBucket(args)
	case "unmount_bucket":
		return unmountBucket(args)
	case "get_bucket_mount_status":
		return getBucketMountStatus(args)
	case "open_bucket_mount":
		return openBucketMount(args)
	case "cleanup_mounts":
		return cleanupMounts()
	case "cleanup_stale_windows_processes":
		return cleanupStaleWindowsProcesses()
	case "get_cache_stats":
		return getCacheStats(args)
	case "open_cache_directory":
		return openCacheDirectory(args)
	case "clean_cache":
		return cleanCache(args)
	// Directory sync profiles.
	case "list_sync_profiles":
		return listSyncProfiles(args)
	case "save_sync_profile":
		return saveSyncProfile(args)
	case "delete_sync_profile":
		return deleteSyncProfile(args)
	case "trigger_sync_profile":
		return triggerSyncProfile(args)
	case "write_flutter_log":
		return writeFlutterLog(args)
	// In-app update (download + install + relaunch).
	case "install_app":
		return installApp(args)
	default:
		return nil, fmt.Errorf("unsupported bridge method %q", method)
	}
}

// --- Storage operations ---

type bucketArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

type objectListArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
	Prefix string                            `json:"prefix"`
}

type objectHeadArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
	Key    string                            `json:"key"`
}

type directoryAccessArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
	Prefix string                            `json:"prefix"`
}

type createDirectoryArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
	Prefix string                            `json:"prefix"`
	Name   string                            `json:"name"`
}

type objectMutationArgs struct {
	Config      storageconfig.RemoteStorageConfig `json:"config"`
	Bucket      string                            `json:"bucket"`
	Key         string                            `json:"key"`
	IsDirectory bool                              `json:"isDirectory"`
	TaskID      string                            `json:"taskId"`
}

type renameObjectArgs struct {
	Config      storageconfig.RemoteStorageConfig `json:"config"`
	Bucket      string                            `json:"bucket"`
	Key         string                            `json:"key"`
	IsDirectory bool                              `json:"isDirectory"`
	NewName     string                            `json:"newName"`
}

type uploadArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                            `json:"bucket"`
	Key       string                            `json:"key"`
	LocalPath string                            `json:"localPath"`
	TaskID    string                            `json:"taskId"`
}

type downloadArgs struct {
	Config    storageconfig.RemoteStorageConfig `json:"config"`
	Bucket    string                            `json:"bucket"`
	Key       string                            `json:"key"`
	LocalPath string                            `json:"localPath"`
	TaskID    string                            `json:"taskId"`
}

type transferTaskArgs struct {
	TaskID string `json:"taskId"`
}

func listBuckets(args json.RawMessage) (any, error) {
	var input bucketArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageops.ForConfig(input.Config).ListBuckets(context.Background())
}

func listObjects(args json.RawMessage) (any, error) {
	var input objectListArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	page, err := storageops.ForConfig(input.Config).ListObjectsPage(
		context.Background(),
		input.Bucket,
		input.Prefix,
		"",
		1000,
	)
	if err != nil {
		return nil, err
	}
	return page.Items, nil
}

func headObject(args json.RawMessage) (any, error) {
	var input objectHeadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageops.ForConfig(input.Config).HeadObject(context.Background(), input.Bucket, input.Key)
}

func directoryAccess(args json.RawMessage) (any, error) {
	var input directoryAccessArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageops.ForConfig(input.Config).DirectoryAccess(context.Background(), input.Bucket, input.Prefix)
}

func createDirectory(args json.RawMessage) (any, error) {
	var input createDirectoryArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).CreateDirectory(
		context.Background(),
		input.Bucket,
		input.Prefix,
		input.Name,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func deleteObject(args json.RawMessage) (any, error) {
	var input objectMutationArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).DeleteObject(
		context.Background(),
		input.Bucket,
		input.Key,
		input.IsDirectory,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func renameObject(args json.RawMessage) (any, error) {
	var input renameObjectArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).RenameObject(
		context.Background(),
		input.Bucket,
		input.Key,
		input.IsDirectory,
		input.NewName,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func uploadFile(args json.RawMessage) (any, error) {
	var input uploadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).UploadFile(
		context.Background(),
		input.Bucket,
		input.Key,
		input.LocalPath,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func uploadDirectory(args json.RawMessage) (any, error) {
	var input uploadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	backend := storageops.ForConfig(input.Config)
	go func() {
		_ = storageops.UploadDirectory(
			context.Background(),
			backend,
			input.Bucket,
			input.Key,
			input.LocalPath,
			input.TaskID,
		)
	}()
	return map[string]any{"ok": true}, nil
}

func downloadFile(args json.RawMessage) (any, error) {
	var input downloadArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageops.ForConfig(input.Config).DownloadFile(
		context.Background(),
		input.Bucket,
		input.Key,
		input.LocalPath,
		input.TaskID,
	); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func listTransferJobs() (any, error) {
	return s3ops.ListTransferSnapshots(), nil
}

func cancelTransfer(args json.RawMessage) (any, error) {
	var input transferTaskArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if input.TaskID == "" {
		return nil, fmt.Errorf("missing transfer task id")
	}
	if bucketmount.CancelQueuedTransfer(input.TaskID) {
		return map[string]any{"ok": true}, nil
	}
	return map[string]any{"ok": s3ops.CancelTransfer(input.TaskID)}, nil
}

func triggerTransfer(args json.RawMessage) (any, error) {
	var input transferTaskArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if input.TaskID == "" {
		return nil, fmt.Errorf("missing transfer task id")
	}
	return map[string]any{"ok": bucketmount.TriggerQueuedTransfer(input.TaskID)}, nil
}
