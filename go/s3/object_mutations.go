// Object mutation helpers cover delete and rename flows for files and prefixes.

package s3

import (
	"context"
	"fmt"
	"strings"

	storageconfig "remote-storage/go/config"
)

// DeleteObject soft-deletes either a single object or all objects under a prefix.
func DeleteObject(cfg storageconfig.RemoteStorageConfig, bucket, key string, isDirectory bool) error {
	return MoveObjectToTrashContext(Ctx(), cfg, bucket, key, isDirectory)
}

// DeleteObjectContext soft-deletes either a single object or all objects under a prefix.
func DeleteObjectContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
) error {
	return MoveObjectToTrashContext(ctx, cfg, bucket, key, isDirectory)
}

// DeleteObjectContextWithTask soft-deletes an object tree while reporting task status.
func DeleteObjectContextWithTask(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
	taskID string,
) (err error) {
	if taskID == "" {
		return DeleteObjectContext(ctx, cfg, bucket, key, isDirectory)
	}
	if ctx == nil {
		ctx = Ctx()
	}
	var cancel context.CancelFunc
	ctx, cancel = context.WithCancel(ctx)
	startTransfer(taskID, "delete", bucket, key, "", 0, cancel)
	defer func() { finishTransfer(taskID, err) }()
	return MoveObjectToTrashContext(ctx, cfg, bucket, key, isDirectory)
}

// DeleteObjectHard permanently removes either a single object or all objects under a prefix.
func DeleteObjectHard(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
) error {
	return DeleteObjectHardContext(Ctx(), cfg, bucket, key, isDirectory)
}

// DeleteObjectHardContext permanently removes either a single object or all objects under a prefix.
func DeleteObjectHardContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
) error {
	client := NewClient(cfg)
	keys, err := mutationKeys(ctx, client, bucket, key, isDirectory)
	if err != nil {
		return err
	}
	if len(keys) == 0 {
		return nil
	}
	return deleteObjectKeysHard(ctx, client, bucket, keys)
}

// DeleteObjectHardContextWithTask permanently removes an object tree while reporting task status.
func DeleteObjectHardContextWithTask(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
	taskID string,
) (err error) {
	if taskID == "" {
		return DeleteObjectHardContext(ctx, cfg, bucket, key, isDirectory)
	}
	if ctx == nil {
		ctx = Ctx()
	}
	var cancel context.CancelFunc
	ctx, cancel = context.WithCancel(ctx)
	startTransfer(taskID, "delete", bucket, key, "", 0, cancel)
	defer func() { finishTransfer(taskID, err) }()
	return DeleteObjectHardContext(ctx, cfg, bucket, key, isDirectory)
}

// RenameObject emulates rename by copying to a sibling key and removing the source.
func RenameObject(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
	newName string,
) error {
	return RenameObjectContext(Ctx(), cfg, bucket, key, isDirectory, newName)
}

// RenameObjectContext emulates rename with a caller-supplied context.
func RenameObjectContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key string,
	isDirectory bool,
	newName string,
) error {
	client := NewClient(cfg)
	trimmedName := strings.Trim(strings.TrimSpace(newName), "/")
	if trimmedName == "" {
		return fmt.Errorf("new name is required")
	}

	targetPrefix, err := renamedKeyTarget(key, isDirectory, trimmedName)
	if err != nil {
		return err
	}
	plan, err := buildObjectTransferPlan(
		ctx,
		client,
		bucket,
		key,
		targetPrefix,
		isDirectory,
	)
	if err != nil || len(plan.entries) == 0 {
		return err
	}
	if err := executeObjectCopyPlan(
		ctx,
		client,
		bucket,
		plan,
		objectTransferTask{},
		isDirectory,
	); err != nil {
		return err
	}
	return DeleteObjectHardContext(ctx, cfg, bucket, key, isDirectory)
}

func renamedKeyTarget(key string, isDirectory bool, newName string) (string, error) {
	if !isDirectory {
		index := strings.LastIndex(key, "/")
		if index < 0 {
			return newName, nil
		}
		return key[:index+1] + newName, nil
	}

	trimmed := strings.TrimSuffix(key, "/")
	index := strings.LastIndex(trimmed, "/")
	if index < 0 {
		return newName + "/", nil
	}
	return trimmed[:index+1] + newName + "/", nil
}
