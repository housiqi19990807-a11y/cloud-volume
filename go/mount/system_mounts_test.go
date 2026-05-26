// System mount parsing tests keep stale-session detection stable.
package mount

import (
	"strings"
	"testing"
)

func TestMountOutputContainsPath(t *testing.T) {
	t.Parallel()

	output := strings.Join([]string{
		"http://127.0.0.1:19090/ on /Users/3000y/Desktop/\u4e91\u5377-demo (webdav, nodev, nosuid, mounted by 3000y)",
		"http://127.0.0.1:19091/ on /Users/3000y/Desktop/My\\040Bucket (webdav, nodev, nosuid, mounted by 3000y)",
	}, "\n")

	if !mountOutputContainsPath(output, "/Users/3000y/Desktop/云卷-demo") {
		t.Fatal("expected unicode mount path to be detected")
	}
	if !mountOutputContainsPath(output, "/Users/3000y/Desktop/My Bucket") {
		t.Fatal("expected escaped-space mount path to be detected")
	}
	if mountOutputContainsPath(output, "/Users/3000y/Desktop/missing") {
		t.Fatal("expected unrelated mount path to be absent")
	}
}
