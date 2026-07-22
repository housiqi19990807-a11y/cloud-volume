package jwanfs

import (
	"testing"

	storageconfig "remote-storage/go/config"
)

// configForEndpoint builds a minimal S3 RemoteStorageConfig for tests.
func configForEndpoint(endpoint string) storageconfig.RemoteStorageConfig {
	return storageconfig.RemoteStorageConfig{
		Endpoint:        endpoint,
		StorageType:     storageconfig.StorageTypeS3,
		AccessKeyID:     "ak",
		SecretAccessKey: "sk",
	}
}

func TestConfigForEndpoint(t *testing.T) {
	cfg := configForEndpoint("http://example")
	if cfg.Endpoint != "http://example" || cfg.AccessKeyID != "ak" {
		t.Fatalf("unexpected cfg: %+v", cfg)
	}
}

