// Encryption tests ensure remote snapshots never contain readable config JSON.
package configbackup

import (
	"bytes"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestEncryptRoundTrip(t *testing.T) {
	cfg := storageconfig.RemoteStorageConfig{Endpoint: "https://backup.example", AccessKeyID: "ak", SecretAccessKey: "sk"}
	plain := []byte(`{"profiles":{"main":{"secretAccessKey":"hidden"}}}`)
	ciphertext, err := encrypt(cfg, plain)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	if bytes.Contains(ciphertext, plain) {
		t.Fatal("ciphertext exposed plaintext")
	}
	got, err := decrypt(cfg, ciphertext)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if !bytes.Equal(got, plain) {
		t.Fatalf("decrypt = %q", got)
	}
}
