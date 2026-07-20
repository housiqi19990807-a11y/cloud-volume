// Bucket quota dispatch keeps optional provider capacity off the initial list path.
package main

import (
	"context"
	"encoding/json"

	storageconfig "remote-storage/go/config"
	bridgelog "remote-storage/go/logging"
	storageops "remote-storage/go/storage"
)

type bucketQuotaArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
	Bucket string                            `json:"bucket"`
}

func getBucketQuota(args json.RawMessage) (any, error) {
	var input bucketQuotaArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	bridgelog.Infof(
		"[bridge/storage] get_bucket_quota storage_type=%q profile=%q bucket=%q",
		input.Config.StorageType,
		input.Config.DisplayName,
		input.Bucket,
	)
	return storageops.GetBucketQuota(
		context.Background(),
		input.Config,
		input.Bucket,
	)
}
