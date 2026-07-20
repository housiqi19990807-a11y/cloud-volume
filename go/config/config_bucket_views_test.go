// Bucket view tests cover allowlist normalization and dynamic-all semantics.
package config

import "testing"

func TestNormalizeBucketViewsTrimsNamesAndPrefixes(t *testing.T) {
	views := normalizeBucketViews(map[string]BucketViewSettings{
		" bucket-a ": {DisplayName: " Photos ", RootPrefix: "/archive/2026/"},
		"":           {RootPrefix: "ignored"},
	})
	if len(views) != 1 {
		t.Fatalf("len(views) = %d, want 1", len(views))
	}
	if got := views["bucket-a"]; got.DisplayName != "Photos" || got.RootPrefix != "archive/2026" {
		t.Fatalf("normalized view = %#v", got)
	}
}

func TestBucketViewForDistinguishesDynamicAll(t *testing.T) {
	config := RemoteStorageConfig{BucketViews: map[string]BucketViewSettings{}}
	if _, ok := config.BucketViewFor("bucket-a"); ok {
		t.Fatal("empty views should mean dynamic all, not an explicit entry")
	}
	config.BucketViews = map[string]BucketViewSettings{"bucket-a": {}}
	if _, ok := config.BucketViewFor("bucket-a"); !ok {
		t.Fatal("configured bucket should be allowlisted")
	}
}
