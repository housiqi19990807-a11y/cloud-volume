// Delete progress helpers report per-item advancement so directory deletes
// render a determinate progress bar instead of an indeterminate spinner.
package s3

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// deleteObjectKeysHardWithTask removes each key with per-key retries and
// reports per-item progress so directory deletes show a determinate bar.
func deleteObjectKeysHardWithTask(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	keys []string,
	taskID string,
) error {
	if taskID != "" {
		AddTransferItems(taskID, int64(len(keys)))
	}
	for _, objectKey := range keys {
		if err := deleteObjectKeyResilient(ctx, client, bucket, objectKey); err != nil {
			return err
		}
		if taskID != "" {
			AdvanceTransferItems(taskID, 1)
		}
	}
	return nil
}

// deleteEntriesHardWithTask is the entry-based counterpart of
// deleteObjectKeysHardWithTask; item totals are reported by the caller's
// mutationEntriesWithProgress enumeration.
func deleteEntriesHardWithTask(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	entries []types.Object,
	taskID string,
) error {
	for _, entry := range entries {
		if entry.Key == nil {
			continue
		}
		if err := deleteObjectKeyResilient(ctx, client, bucket, *entry.Key); err != nil {
			return err
		}
		AdvanceTransferItems(taskID, 1)
	}
	return nil
}
