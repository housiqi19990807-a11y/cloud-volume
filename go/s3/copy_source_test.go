// Copy source tests pin URL encoding for CopyObject-compatible object keys.
package s3

import "testing"

func TestEncodeCopySource(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name   string
		bucket string
		key    string
		want   string
	}{
		{
			name:   "plain file",
			bucket: "demo",
			key:    "folder/file.txt",
			want:   "demo%2Ffolder%2Ffile.txt",
		},
		{
			name:   "unicode directory placeholder",
			bucket: "demo",
			key:    "（AUHelperService正在保存文稿）/",
			want:   "demo%2F%EF%BC%88AUHelperService%E6%AD%A3%E5%9C%A8%E4%BF%9D%E5%AD%98%E6%96%87%E7%A8%BF%EF%BC%89%2F",
		},
		{
			name:   "nested unicode path",
			bucket: "demo",
			key:    "父目录/（临时）/文件 1.txt",
			want:   "demo%2F%E7%88%B6%E7%9B%AE%E5%BD%95%2F%EF%BC%88%E4%B8%B4%E6%97%B6%EF%BC%89%2F%E6%96%87%E4%BB%B6%201.txt",
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := encodeCopySource(tc.bucket, tc.key); got != tc.want {
				t.Fatalf("encodeCopySource(%q, %q) = %q, want %q", tc.bucket, tc.key, got, tc.want)
			}
		})
	}
}
