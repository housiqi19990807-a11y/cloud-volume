// Multipart upload resume helpers keep mount writeback uploads resumable across failures.
package s3

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"

	storageconfig "remote-storage/go/config"
)

const (
	multipartUploadThreshold = 8 << 20
	multipartUploadPartSize  = 8 << 20
)

type resumableUploadState struct {
	Bucket          string              `json:"bucket"`
	Key             string              `json:"key"`
	LocalPath       string              `json:"localPath"`
	FileSize        int64               `json:"fileSize"`
	FileModUnixNano int64               `json:"fileModUnixNano"`
	UploadID        string              `json:"uploadId"`
	CompletedParts  []resumablePartInfo `json:"completedParts"`
}

type resumablePartInfo struct {
	PartNumber int32  `json:"partNumber"`
	ETag       string `json:"etag"`
	Size       int64  `json:"size"`
}

// UploadFileContextResumable uploads a local file with resumable multipart state.
func UploadFileContextResumable(
	ctx context.Context,
	cfg storageconfig.RemoteStorageConfig,
	bucket,
	key,
	localPath,
	taskID string,
) (err error) {
	client := NewClient(cfg)
	file, err := os.Open(localPath)
	if err != nil {
		return fmt.Errorf("open local file: %w", err)
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return fmt.Errorf("stat local file: %w", err)
	}
	if ctx == nil {
		ctx = Ctx()
	}
	if taskID != "" {
		var cancel context.CancelFunc
		ctx, cancel = context.WithCancel(ctx)
		startTransfer(taskID, "upload", bucket, key, localPath, info.Size(), cancel)
		defer func() { finishTransfer(taskID, err) }()
	}

	if info.Size() <= multipartUploadThreshold {
		_ = discardResumableUploadState(context.Background(), client, localPath)
		return uploadWholeObject(ctx, client, bucket, key, localPath, file, info.Size(), taskID)
	}

	state, err := loadOrCreateResumableUploadState(
		ctx,
		client,
		bucket,
		key,
		localPath,
		info,
	)
	if err != nil {
		return err
	}

	if taskID != "" {
		advanceTransfer(taskID, completedUploadBytes(state, info.Size()))
	}

	if err := uploadPendingParts(ctx, client, bucket, key, file, state, taskID); err != nil {
		if errors.Is(err, context.Canceled) {
			_ = abortResumableUpload(context.Background(), client, bucket, key, state.UploadID)
			_ = removeResumableUploadState(localPath)
		}
		return err
	}
	if err := completeResumableUpload(ctx, client, bucket, key, state); err != nil {
		return err
	}
	return removeResumableUploadState(localPath)
}

// DiscardResumableUpload removes local multipart state and aborts any remote multipart upload.
func DiscardResumableUpload(
	cfg storageconfig.RemoteStorageConfig,
	localPath string,
) error {
	return discardResumableUploadState(context.Background(), NewClient(cfg), localPath)
}

func uploadWholeObject(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key,
	localPath string,
	file *os.File,
	totalBytes int64,
	taskID string,
) error {
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return err
	}
	body := io.Reader(file)
	if taskID != "" {
		body = &contextReader{
			ctx:    ctx,
			reader: file,
			onRead: func(n int) { advanceTransfer(taskID, int64(n)) },
		}
	}
	_, err := client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: &bucket,
		Key:    &key,
		Body:   body,
	})
	return err
}

func loadOrCreateResumableUploadState(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key,
	localPath string,
	info os.FileInfo,
) (*resumableUploadState, error) {
	state, err := readResumableUploadState(localPath)
	if err == nil && resumableUploadStateMatches(state, bucket, key, localPath, info) {
		return state, nil
	}
	if err == nil {
		_ = abortResumableUpload(context.Background(), client, state.Bucket, state.Key, state.UploadID)
		_ = removeResumableUploadState(localPath)
	}
	createOut, err := client.CreateMultipartUpload(ctx, &s3.CreateMultipartUploadInput{
		Bucket: &bucket,
		Key:    &key,
	})
	if err != nil {
		return nil, err
	}
	state = &resumableUploadState{
		Bucket:          bucket,
		Key:             key,
		LocalPath:       localPath,
		FileSize:        info.Size(),
		FileModUnixNano: info.ModTime().UnixNano(),
		UploadID:        aws.ToString(createOut.UploadId),
		CompletedParts:  []resumablePartInfo{},
	}
	if err := writeResumableUploadState(localPath, state); err != nil {
		_ = abortResumableUpload(context.Background(), client, bucket, key, state.UploadID)
		return nil, err
	}
	return state, nil
}

func uploadPendingParts(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	file *os.File,
	state *resumableUploadState,
	taskID string,
) error {
	completed := completedPartMap(state)
	totalParts := partCount(state.FileSize)
	for index := int32(1); index <= totalParts; index++ {
		expectedSize := partSizeFor(index, state.FileSize)
		if part, ok := completed[index]; ok && part.Size == expectedSize {
			continue
		}
		offset := int64(index-1) * multipartUploadPartSize
		section := io.NewSectionReader(file, offset, expectedSize)
		body := io.ReadSeeker(section)
		if taskID != "" {
			body = &contextReadSeeker{
				ctx:    ctx,
				reader: section,
				onRead: func(n int) { advanceTransfer(taskID, int64(n)) },
			}
		}
		partOut, err := client.UploadPart(ctx, &s3.UploadPartInput{
			Bucket:        &bucket,
			Key:           &key,
			UploadId:      &state.UploadID,
			PartNumber:    aws.Int32(index),
			Body:          body,
			ContentLength: aws.Int64(expectedSize),
		})
		if err != nil {
			return err
		}
		upsertCompletedPart(state, resumablePartInfo{
			PartNumber: index,
			ETag:       aws.ToString(partOut.ETag),
			Size:       expectedSize,
		})
		if err := writeResumableUploadState(state.LocalPath, state); err != nil {
			return err
		}
	}
	return nil
}

func completeResumableUpload(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key string,
	state *resumableUploadState,
) error {
	parts := make([]types.CompletedPart, 0, len(state.CompletedParts))
	sort.Slice(state.CompletedParts, func(i, j int) bool {
		return state.CompletedParts[i].PartNumber < state.CompletedParts[j].PartNumber
	})
	for _, part := range state.CompletedParts {
		etag := part.ETag
		partNumber := part.PartNumber
		parts = append(parts, types.CompletedPart{
			ETag:       &etag,
			PartNumber: &partNumber,
		})
	}
	_, err := client.CompleteMultipartUpload(ctx, &s3.CompleteMultipartUploadInput{
		Bucket:   &bucket,
		Key:      &key,
		UploadId: &state.UploadID,
		MultipartUpload: &types.CompletedMultipartUpload{
			Parts: parts,
		},
	})
	return err
}

func discardResumableUploadState(
	ctx context.Context,
	client *s3.Client,
	localPath string,
) error {
	state, err := readResumableUploadState(localPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	_ = abortResumableUpload(ctx, client, state.Bucket, state.Key, state.UploadID)
	return removeResumableUploadState(localPath)
}

func abortResumableUpload(
	ctx context.Context,
	client *s3.Client,
	bucket,
	key,
	uploadID string,
) error {
	if uploadID == "" {
		return nil
	}
	_, err := client.AbortMultipartUpload(ctx, &s3.AbortMultipartUploadInput{
		Bucket:   &bucket,
		Key:      &key,
		UploadId: &uploadID,
	})
	return err
}

func completedUploadBytes(state *resumableUploadState, totalSize int64) int64 {
	var total int64
	for _, part := range state.CompletedParts {
		total += part.Size
	}
	if total > totalSize {
		return totalSize
	}
	return total
}

func completedPartMap(state *resumableUploadState) map[int32]resumablePartInfo {
	result := make(map[int32]resumablePartInfo, len(state.CompletedParts))
	for _, part := range state.CompletedParts {
		result[part.PartNumber] = part
	}
	return result
}

func upsertCompletedPart(state *resumableUploadState, next resumablePartInfo) {
	for index, part := range state.CompletedParts {
		if part.PartNumber != next.PartNumber {
			continue
		}
		state.CompletedParts[index] = next
		return
	}
	state.CompletedParts = append(state.CompletedParts, next)
}

func resumableUploadStateMatches(
	state *resumableUploadState,
	bucket,
	key,
	localPath string,
	info os.FileInfo,
) bool {
	return state != nil &&
		state.Bucket == bucket &&
		state.Key == key &&
		state.LocalPath == localPath &&
		state.FileSize == info.Size() &&
		state.FileModUnixNano == info.ModTime().UnixNano() &&
		state.UploadID != ""
}

func readResumableUploadState(localPath string) (*resumableUploadState, error) {
	data, err := os.ReadFile(uploadStatePath(localPath))
	if err != nil {
		return nil, err
	}
	var state resumableUploadState
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, err
	}
	return &state, nil
}

func writeResumableUploadState(localPath string, state *resumableUploadState) error {
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	return os.WriteFile(uploadStatePath(localPath), data, 0o644)
}

func removeResumableUploadState(localPath string) error {
	err := os.Remove(uploadStatePath(localPath))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func uploadStatePath(localPath string) string {
	return localPath + ".uploading.json"
}

func partCount(totalSize int64) int32 {
	if totalSize <= 0 {
		return 0
	}
	count := totalSize / multipartUploadPartSize
	if totalSize%multipartUploadPartSize != 0 {
		count++
	}
	return int32(count)
}

func partSizeFor(partNumber int32, totalSize int64) int64 {
	offset := int64(partNumber-1) * multipartUploadPartSize
	remaining := totalSize - offset
	if remaining > multipartUploadPartSize {
		return multipartUploadPartSize
	}
	return remaining
}
