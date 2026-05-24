// Bucket listing operations.

package s3

import (
	"github.com/aws/aws-sdk-go-v2/service/s3"

	storageconfig "remote-storage/go/config"
)

// BucketInfo holds bucket metadata returned to the Flutter layer.
type BucketInfo struct {
	Name string `json:"name"`
}

// ListBuckets returns all buckets accessible by the configured credentials.
func ListBuckets(cfg storageconfig.RemoteStorageConfig) ([]BucketInfo, error) {
	client := NewClient(cfg)
	out, err := client.ListBuckets(Ctx(), &s3.ListBucketsInput{})
	if err != nil {
		return nil, err
	}

	var result []BucketInfo
	for _, b := range out.Buckets {
		result = append(result, BucketInfo{Name: *b.Name})
	}
	if result == nil {
		result = []BucketInfo{}
	}
	return result, nil
}
