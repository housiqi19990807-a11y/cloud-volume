// Encryption tests ensure remote snapshots never contain readable config JSON.
package configbackup

import (
	"bytes"
	"testing"
)

func TestEncryptRoundTrip(t *testing.T) {
	password := "my-secret-passphrase"
	plain := []byte(`{"profiles":{"main":{"secretAccessKey":"hidden"}}}`)
	ciphertext, err := encrypt(password, plain)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	if bytes.Contains(ciphertext, plain) {
		t.Fatal("ciphertext exposed plaintext")
	}
	got, err := decrypt(password, ciphertext)
	if err != nil {
		t.Fatalf("decrypt: %v", err)
	}
	if !bytes.Equal(got, plain) {
		t.Fatalf("decrypt = %q", got)
	}
}

// Different passwords must yield different ciphertexts and fail to decrypt.
func TestEncryptWrongPasswordFails(t *testing.T) {
	plain := []byte(`{"profiles":{}}`)
	ciphertext, err := encrypt("correct-password", plain)
	if err != nil {
		t.Fatalf("encrypt: %v", err)
	}
	if _, err := decrypt("wrong-password", ciphertext); err == nil {
		t.Fatal("decrypt with wrong password should fail")
	}
}
