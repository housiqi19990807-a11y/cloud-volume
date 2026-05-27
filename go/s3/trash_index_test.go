// Trash index tests pin key-encoded metadata round-trips and list-page fast paths.
package s3

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestBuildTrashIndexKeysRoundTrip(t *testing.T) {
	t.Parallel()

	cfg := storageconfig.RemoteStorageConfig{TrashDirectoryName: ".trash"}
	metadata := trashMetadata{
		ID:          "trash-123",
		Name:        "photo.png",
		OriginalKey: "albums/2026/photo.png",
		TrashKey:    ".trash/objects/trash-123/albums/2026/photo.png",
		DeletedAt:   "2026-05-27T12:34:56Z",
		IsDir:       false,
		Size:        12345,
		ObjectCount: 1,
	}

	byTimeKey, byIDKey, err := buildTrashIndexKeys(cfg, metadata)
	if err != nil {
		t.Fatalf("buildTrashIndexKeys: %v", err)
	}

	fromTime, err := parseTrashItemFromByTimeIndexKey(cfg, byTimeKey)
	if err != nil {
		t.Fatalf("parseTrashItemFromByTimeIndexKey: %v", err)
	}
	fromID, err := parseTrashItemFromByIDIndexKey(cfg, byIDKey)
	if err != nil {
		t.Fatalf("parseTrashItemFromByIDIndexKey: %v", err)
	}

	for _, item := range []TrashItem{fromTime, fromID} {
		if item.ID != metadata.ID {
			t.Fatalf("expected id %q, got %q", metadata.ID, item.ID)
		}
		if item.OriginalKey != metadata.OriginalKey {
			t.Fatalf("expected original key %q, got %q", metadata.OriginalKey, item.OriginalKey)
		}
		if item.DeletedAt != metadata.DeletedAt {
			t.Fatalf("expected deletedAt %q, got %q", metadata.DeletedAt, item.DeletedAt)
		}
		if item.Size != metadata.Size {
			t.Fatalf("expected size %d, got %d", metadata.Size, item.Size)
		}
		if item.ObjectCount != metadata.ObjectCount {
			t.Fatalf("expected object count %d, got %d", metadata.ObjectCount, item.ObjectCount)
		}
		if item.TrashKey != metadata.TrashKey {
			t.Fatalf("expected trash key %q, got %q", metadata.TrashKey, item.TrashKey)
		}
	}
}

func TestListTrashPageContextUsesIndexedEntriesWithoutGetObject(t *testing.T) {
	t.Parallel()

	const bucket = "bucket"
	cfg := storageconfig.RemoteStorageConfig{
		Endpoint:           "",
		Region:             "us-east-1",
		AccessKeyID:        "test",
		SecretAccessKey:    "test",
		UsePathStyle:       true,
		TrashDirectoryName: ".trash",
		TrashRetentionDays: -1,
	}
	metadata := trashMetadata{
		ID:          "trash-idx-1",
		Name:        "notes.txt",
		OriginalKey: "docs/notes.txt",
		DeletedAt:   "2026-05-27T08:00:00Z",
		IsDir:       false,
		Size:        42,
		ObjectCount: 1,
	}
	byTimeKey, _, err := buildTrashIndexKeys(cfg, metadata)
	if err != nil {
		t.Fatalf("buildTrashIndexKeys: %v", err)
	}

	getObjectCalls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/"+bucket) {
			http.NotFound(w, r)
			return
		}
		query := r.URL.Query()
		switch {
		case r.Method == http.MethodGet && query.Get("list-type") == "2":
			prefix := query.Get("prefix")
			w.Header().Set("Content-Type", "application/xml")
			if prefix == trashIndexByTimePrefix(cfg) {
				_, _ = fmt.Fprintf(w,
					"<?xml version=\"1.0\" encoding=\"UTF-8\"?><ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>%s</Key></Contents></ListBucketResult>",
					byTimeKey,
				)
				return
			}
			_, _ = w.Write([]byte("<?xml version=\"1.0\" encoding=\"UTF-8\"?><ListBucketResult><IsTruncated>false</IsTruncated></ListBucketResult>"))
		case r.Method == http.MethodGet:
			getObjectCalls++
			http.Error(w, "unexpected get", http.StatusInternalServerError)
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		}
	}))
	defer server.Close()
	cfg.Endpoint = server.URL

	page, err := ListTrashPageContext(Ctx(), cfg, bucket, "", 20)
	if err != nil {
		t.Fatalf("ListTrashPageContext: %v", err)
	}
	if getObjectCalls != 0 {
		t.Fatalf("expected no GetObject calls, got %d", getObjectCalls)
	}
	if len(page.Items) != 1 {
		t.Fatalf("expected one trash item, got %d", len(page.Items))
	}
	if page.Items[0].ID != metadata.ID {
		t.Fatalf("expected item id %q, got %q", metadata.ID, page.Items[0].ID)
	}
	if page.Items[0].OriginalKey != metadata.OriginalKey {
		t.Fatalf("expected original key %q, got %q", metadata.OriginalKey, page.Items[0].OriginalKey)
	}
}
