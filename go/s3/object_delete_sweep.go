// Sweep deletion helpers route hard deletes through the resilient single-key
// delete wrapper used by copy/move cleanup phases.
package s3

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// deleteObjectKeysHard removes each key with per-key retries so one transient
// gateway failure does not leave a half-moved object tree behind.
func deleteObjectKeysHard(
	ctx context.Context,
	client *s3.Client,
	bucket string,
	keys []string,
) error {
	return deleteObjectKeysHardWithTask(ctx, client, bucket, keys, "")
}

