// Coverage for MinIO-specific directory helpers keeps compatibility rules stable.
package s3

import "testing"

func TestDirectoryKey(t *testing.T) {
	t.Parallel()

	key, err := directoryKey("alpha/beta", " reports ")
	if err != nil {
		t.Fatalf("directoryKey returned error: %v", err)
	}
	if key != "alpha/beta/reports/" {
		t.Fatalf("unexpected directory key %q", key)
	}
}

func TestDirectoryKeyRejectsBlankNames(t *testing.T) {
	t.Parallel()

	if _, err := directoryKey("", " / "); err == nil {
		t.Fatal("expected blank directory name to fail")
	}
}

func TestNormalizeMinioEndpoint(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		raw      string
		endpoint string
		secure   bool
	}{
		{
			name:     "https endpoint keeps host and secure flag",
			raw:      "https://storage.example.com",
			endpoint: "storage.example.com",
			secure:   true,
		},
		{
			name:     "http endpoint keeps host and disables tls",
			raw:      "http://127.0.0.1:9000",
			endpoint: "127.0.0.1:9000",
			secure:   false,
		},
		{
			name:     "bare host preserves pathless endpoint",
			raw:      "minio.internal:9000/",
			endpoint: "minio.internal:9000",
			secure:   true,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()

			endpoint, secure, err := normalizeMinioEndpoint(test.raw)
			if err != nil {
				t.Fatalf("normalizeMinioEndpoint returned error: %v", err)
			}
			if endpoint != test.endpoint {
				t.Fatalf("unexpected endpoint %q", endpoint)
			}
			if secure != test.secure {
				t.Fatalf("unexpected secure flag %t", secure)
			}
		})
	}
}

func TestNormalizeMinioEndpointRejectsPaths(t *testing.T) {
	t.Parallel()

	if _, _, err := normalizeMinioEndpoint("https://storage.example.com/custom"); err == nil {
		t.Fatal("expected endpoint with path to fail")
	}
}
