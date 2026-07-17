// Object transfer planning centralizes copy/move traversal and progress accounting.
package s3

import (
	"context"
	"fmt"
	"strings"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

type objectTransferPlan struct {
	sourcePrefix string
	targetPrefix string
	entries      []types.Object
	totalBytes   int64
}

func buildObjectTransferPlan(
	ctx context.Context,
	client *s3.Client,
	bucket,
	sourceKey,
	targetKey string,
	isDirectory bool,
) (objectTransferPlan, error) {
	sourceKey = strings.TrimSpace(sourceKey)
	targetKey = strings.TrimSpace(targetKey)
	if sourceKey == "" || targetKey == "" {
		return objectTransferPlan{}, fmt.Errorf("source and target keys are required")
	}
	if sourceKey == targetKey {
		return objectTransferPlan{}, nil
	}

	entries, err := mutationEntries(ctx, client, bucket, sourceKey, isDirectory)
	if err != nil {
		return objectTransferPlan{}, err
	}
	if len(entries) == 0 {
		return objectTransferPlan{}, nil
	}

	plan := objectTransferPlan{
		sourcePrefix: sourceKey,
		targetPrefix: targetKey,
		entries:      entries,
		totalBytes:   sumTransferEntrySizes(entries),
	}
	if isDirectory {
		plan.sourcePrefix = ensureRemoteDirSuffix(sourceKey)
		plan.targetPrefix = ensureRemoteDirSuffix(targetKey)
	}
	if !isDirectory && plan.totalBytes == 0 {
		head, err := headObjectResilient(ctx, client, bucket, sourceKey)
		if err == nil && head.ContentLength != nil && *head.ContentLength > 0 {
			plan.totalBytes = *head.ContentLength
			if len(plan.entries) == 1 {
				plan.entries[0].Size = head.ContentLength
			}
		}
	}
	return plan, nil
}
