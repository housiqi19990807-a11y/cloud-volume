// Object entry helpers enumerate concrete S3 objects for copy/move/delete-style operations.
package s3

import (
	"context"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

func mutationEntries(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	isDirectory bool,
) ([]types.Object, error) {
	return mutationEntriesWithProgress(ctx, client, bucket, key, isDirectory, "")
}

// mutationEntriesWithProgress enumerates objects like mutationEntries and, when
// taskID is set, reports TotalItems immediately so the UI can render a
// determinate item bar while the sweep runs.
func mutationEntriesWithProgress(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	isDirectory bool,
	taskID string,
) ([]types.Object, error) {
	entries, err := listMutationEntries(ctx, client, bucket, key, isDirectory)
	if err != nil {
		return nil, err
	}
	if taskID != "" && len(entries) > 0 {
		AddTransferItems(taskID, int64(len(entries)))
	}
	return entries, nil
}

func listMutationEntries(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	isDirectory bool,
) ([]types.Object, error) {
	if !isDirectory {
		return []types.Object{{Key: aws.String(key)}}, nil
	}

	prefix := key
	if prefix != "" && !strings.HasSuffix(prefix, "/") {
		prefix += "/"
	}
	pager := s3.NewListObjectsV2Paginator(client, &s3.ListObjectsV2Input{
		Bucket: &bucket,
		Prefix: aws.String(prefix),
	})

	entries := make([]types.Object, 0)
	for pager.HasMorePages() {
		page, err := pager.NextPage(ctx)
		if err != nil {
			return nil, err
		}
		entries = append(entries, page.Contents...)
	}

	if len(entries) == 0 {
		entries = append(entries, types.Object{Key: aws.String(prefix)})
	}
	return entries, nil
}

// transferEntryKeys flattens entry keys once at plan time for the post-copy
// source cleanup sweep.
func transferEntryKeys(entries []types.Object) []string {
	keys := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.Key == nil {
			continue
		}
		keys = append(keys, *entry.Key)
	}
	return keys
}

func mutationKeys(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	isDirectory bool,
) ([]string, error) {
	entries, err := mutationEntries(ctx, client, bucket, key, isDirectory)
	if err != nil {
		return nil, err
	}
	return transferEntryKeys(entries), nil
}
