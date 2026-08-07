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

func TestRenameDirectoryDeletesPlannedKeysWithoutRelistingSource(t *testing.T) {
	const bucket = "bucket"
	var listCalls int
	var deletedKeys []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && r.URL.Query().Get("list-type") == "2":
			listCalls++
			w.Header().Set("Content-Type", "application/xml")
			_, _ = fmt.Fprint(w, `<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult><Name>bucket</Name><Prefix>old/</Prefix><KeyCount>2</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>
<Contents><Key>old/</Key><Size>0</Size></Contents>
<Contents><Key>old/readme.txt</Key><Size>4</Size></Contents>
</ListBucketResult>`)
		case r.Method == http.MethodPut:
			w.Header().Set("Content-Type", "application/xml")
			if r.Header.Get("X-Amz-Copy-Source") != "" {
				_, _ = fmt.Fprint(w, `<CopyObjectResult><LastModified>2026-08-07T00:00:00.000Z</LastModified><ETag>"etag"</ETag></CopyObjectResult>`)
			}
		case r.Method == http.MethodDelete:
			deletedKeys = append(deletedKeys, strings.TrimPrefix(r.URL.Path, "/"+bucket+"/"))
			w.WriteHeader(http.StatusNoContent)
		default:
			http.Error(w, "unexpected request", http.StatusBadRequest)
		}
	}))
	defer server.Close()

	cfg := storageconfig.RemoteStorageConfig{
		Endpoint:        server.URL,
		Region:          "us-east-1",
		AccessKeyID:     "test",
		SecretAccessKey: "test",
		UsePathStyle:    true,
	}
	if err := RenameObjectContext(context.Background(), cfg, bucket, "old/", true, "new"); err != nil {
		t.Fatalf("RenameObjectContext: %v", err)
	}
	if listCalls != 1 {
		t.Fatalf("source listings = %d, want exactly the planning listing", listCalls)
	}
	if len(deletedKeys) != 2 || deletedKeys[0] != "old/" || deletedKeys[1] != "old/readme.txt" {
		t.Fatalf("deleted keys = %v, want planned source keys", deletedKeys)
	}
}
