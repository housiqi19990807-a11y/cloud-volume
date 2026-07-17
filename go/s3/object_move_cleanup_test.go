// Move plan tests pin that the post-copy source cleanup uses the exact key set
// captured at plan build time, so no source object is left behind on moves.
package s3

import (
	"testing"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
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
