// Object move helpers support tracked full-path moves across directories.
package s3

import (
	"context"
	"strings"

	storageconfig "remote-storage/go/config"
)

// MoveObject copies a file or prefix to a new full target key and removes the source.
func MoveObject(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
) error {
	return MoveObjectWithTask(
		cfg,
		bucket,
		sourceKey,
		targetKey,
		isDirectory,
		"",
	)
}

// MoveObjectWithTask moves an object tree while reporting progress to the transfer monitor.
func MoveObjectWithTask(
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
	taskID string,
) error {
	return MoveObjectContextWithTask(
		Ctx(),
		cfg,
		bucket,
		sourceKey,
		targetKey,
		isDirectory,
		taskID,
	)
}

// MoveObjectContext copies a file or prefix to a new full target key with caller context.
func MoveObjectContext(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
) error {
	return MoveObjectContextWithTask(
		ctx,
		cfg,
		bucket,
		sourceKey,
		targetKey,
		isDirectory,
		"",
	)
}

// MoveObjectContextWithTask copies and deletes through a tracked task-aware path.
// Item totals for the copy phase are reported up front so delete sweeps that
// reuse the same task keep a single consistent item bar across both phases.
func MoveObjectContextWithTask(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
	taskID string,
) (err error) {
	client := NewClient(cfg)
	if taskID != "" {
		if _, planErr := mutationEntriesWithProgress(ctx, client, bucket, sourceKey, isDirectory, taskID); planErr != nil {
			return planErr
		}
	}
	plan, err := buildObjectTransferPlan(
		ctx,
		client,
		bucket,
		sourceKey,
		targetKey,
		isDirectory,
	)
	if err != nil || len(plan.entries) == 0 {
		return err
	}
	runCtx, task := beginObjectTransferTask(
		ctx,
		taskID,
		"move",
		bucket,
		sourceKey,
		targetKey,
		plan.totalBytes,
	)
	defer func() { task.finish(err) }()
	if err = executeObjectCopyPlan(
		runCtx,
		client,
		bucket,
		plan,
		task,
		isDirectory,
	); err != nil {
		return err
	}
	return deleteEntriesHardWithTask(runCtx, client, bucket, plan.entries, taskID)
}

func ensureRemoteDirSuffix(value string) string {
	trimmed := strings.TrimSuffix(strings.TrimSpace(value), "/")
	if trimmed == "" {
		return ""
	}
	return trimmed + "/"
}
