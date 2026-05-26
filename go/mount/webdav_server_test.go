// WebDAV server tests pin scoped URL generation for system-mounted bucket roots.
package mount

import "testing"

func TestScopedServerURL(t *testing.T) {
	t.Parallel()

	got := scopedServerURL(19090, "/云卷-demo")
	want := "http://127.0.0.1:19090/%E4%BA%91%E5%8D%B7-demo/"
	if got != want {
		t.Fatalf("scopedServerURL() = %q, want %q", got, want)
	}
}
