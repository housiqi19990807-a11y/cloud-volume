// Move plan tests pin that the post-copy source cleanup uses the exact key set
// captured at plan build time, so no source object is left behind on moves.
package s3

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"

	storageconfig "remote-storage/go/config"
)

func TestTransferEntryKeysKeepsEveryPlannedKey(t *testing.T) {
	t.Parallel()

	entries := []types.Object{
		{Key: aws.String("dir/")},
		{Key: aws.String("dir/a.txt")},
		{Key: nil},
		{Key: aws.String("dir/sub/b.txt")},
	}
	got := transferEntryKeys(entries)
	want := []string{"dir/", "dir/a.txt", "dir/sub/b.txt"}
	if len(got) != len(want) {
		t.Fatalf("transferEntryKeys returned %d keys, want %d (%v)", len(got), len(want), got)
	}
	for index, key := range want {
		if got[index] != key {
			t.Fatalf("transferEntryKeys[%d] = %q, want %q", index, got[index], key)
		}
	}
}

func TestMutationEntriesAddsOmittedDirectoryRootMarker(t *testing.T) {
	t.Parallel()

	const bucket = "bucket"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet ||
			!strings.HasPrefix(r.URL.Path, "/"+bucket) ||
			r.URL.Query().Get("list-type") != "2" {
			http.Error(w, "unexpected request", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/xml")
		_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult>
  <Name>bucket</Name>
  <Prefix>docs/</Prefix>
  <KeyCount>1</KeyCount>
  <MaxKeys>1000</MaxKeys>
  <IsTruncated>false</IsTruncated>
  <Contents><Key>docs/readme.txt</Key><Size>4</Size></Contents>
</ListBucketResult>`)
	}))
	defer server.Close()

	cfg := storageconfig.RemoteStorageConfig{
		Endpoint:        server.URL,
		Region:          "us-east-1",
		AccessKeyID:     "test",
		SecretAccessKey: "test",
		UsePathStyle:    true,
	}
	entries, err := mutationEntries(
		context.Background(),
		NewClient(cfg),
		bucket,
		"docs",
		true,
	)
	if err != nil {
		t.Fatalf("mutationEntries: %v", err)
	}

	got := transferEntryKeys(entries)
	want := []string{"docs/readme.txt", "docs/"}
	if len(got) != len(want) {
		t.Fatalf("mutation entries = %v, want %v", got, want)
	}
	for index, key := range want {
		if got[index] != key {
			t.Fatalf("mutation entries[%d] = %q, want %q", index, got[index], key)
		}
	}
}
