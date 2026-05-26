// WebDAV server tests pin path scoping so system mounts only see one bucket root.
package mount

import "testing"

func TestTrimScopedPath(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name  string
		path  string
		scope string
		want  string
	}{
		{name: "root collection", path: "/云卷-demo", scope: "/云卷-demo", want: "/"},
		{name: "root collection slash", path: "/云卷-demo/", scope: "/云卷-demo", want: "/"},
		{name: "nested child", path: "/云卷-demo/folder/file.txt", scope: "/云卷-demo", want: "/folder/file.txt"},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := trimScopedPath(tc.path, tc.scope); got != tc.want {
				t.Fatalf("trimScopedPath(%q, %q) = %q, want %q", tc.path, tc.scope, got, tc.want)
			}
		})
	}
}
