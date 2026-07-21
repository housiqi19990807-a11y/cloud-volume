// Trash helper tests pin the view-rooted recycle-bin location.
package s3

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestTrashPrefixIncludesRootPrefix(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name       string
		rootPrefix string
		trashName  string
		want       string
	}{
		{
			name:       "bucket root keeps default trash",
			rootPrefix: "",
			trashName:  ".trash",
			want:       ".trash/",
		},
		{
			name:       "subdirectory view nests trash under root",
			rootPrefix: "archive/2026",
			trashName:  ".trash",
			want:       "archive/2026/.trash/",
		},
		{
			name:       "custom trash name still nests under root",
			rootPrefix: "work",
			trashName:  ".recycle",
			want:       "work/.recycle/",
		},
		{
			name:       "empty trash name falls back to .trash under root",
			rootPrefix: "work",
			trashName:  "",
			want:       "work/.trash/",
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			cfg := storageconfig.RemoteStorageConfig{
				RootPrefix:         tc.rootPrefix,
				TrashDirectoryName: tc.trashName,
			}
			if got := trashPrefix(cfg); got != tc.want {
				t.Fatalf("trashPrefix = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestIsTrashKeyMatchesNestedTrash(t *testing.T) {
	t.Parallel()

	cfg := storageconfig.RemoteStorageConfig{
		RootPrefix:         "archive/2026",
		TrashDirectoryName: ".trash",
	}
	if !isTrashKey(cfg, "archive/2026/.trash/objects/id/a.txt") {
		t.Fatal("expected nested trash key to be recognised")
	}
	if isTrashKey(cfg, "archive/2026/photos/a.txt") {
		t.Fatal("normal object under root must not be treated as trash")
	}
	// Bucket-root .trash is a different recycle bin and must not match a
	// subdirectory view's trash root.
	if isTrashKey(cfg, ".trash/objects/id/a.txt") {
		t.Fatal("bucket-root trash must not match a nested view's isTrashKey")
	}
}

func TestIsRootTrashKeyMatchesLeafName(t *testing.T) {
	t.Parallel()

	cfg := storageconfig.RemoteStorageConfig{
		RootPrefix:         "archive/2026",
		TrashDirectoryName: ".trash",
	}
	// After scopedBackend.unscopedKey the listing leaf is just ".trash".
	if !isRootTrashKey(cfg, ".trash") {
		t.Fatal("expected leaf .trash to be hidden from root listings")
	}
	if !isRootTrashKey(cfg, "archive/2026/.trash") {
		t.Fatal("expected fully-resolved trash root to be hidden")
	}
	if isRootTrashKey(cfg, "photos") {
		t.Fatal("normal directory must not be treated as trash root")
	}
}

