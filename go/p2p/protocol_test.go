// Protocol tests lock down account authentication for LAN control messages.
package p2p

import (
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/rand"
	"encoding/hex"
	"testing"
)

func TestSignedEventRejectsWrongAccountKey(t *testing.T) {
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	identity := &DeviceIdentity{DeviceID: hex.EncodeToString(publicKey[:8]), PublicKey: publicKey, PrivateKey: privateKey}
	event := PeerEvent{DeviceID: identity.DeviceID, AccountFP: "account", Bucket: "bucket", Timestamp: 1, Nonce: "nonce"}
	signed, err := event.Sign(identity, []byte("shared-key"))
	if err != nil {
		t.Fatal(err)
	}
	if !signed.Verify([]byte("shared-key")) {
		t.Fatal("expected signed event to verify")
	}
	if signed.Verify([]byte("other-key")) {
		t.Fatal("wrong account key verified event")
	}
	signed.Event.Bucket = "tampered"
	if signed.Verify([]byte("shared-key")) {
		t.Fatal("tampered event verified")
	}
}

func TestContentControlAuthentication(t *testing.T) {
	key := []byte("shared-key")
	query := ContentQuery{Bucket: "bucket", Path: "a/file", VersionHint: "version"}
	if err := query.Sign(key); err != nil {
		t.Fatal(err)
	}
	if !query.Verify(key) || query.Verify([]byte("wrong")) {
		t.Fatal("query authentication mismatch")
	}
	request := ChunkRequest{Bucket: "bucket", Path: "a/file", VersionHint: "version", Offset: 4, Length: 8}
	if err := request.Sign(key); err != nil {
		t.Fatal(err)
	}
	if !request.Verify(key) {
		t.Fatal("chunk request did not verify")
	}
	response := ChunkResponse{Offset: 4, Length: 8}
	if err := response.Sign(key); err != nil {
		t.Fatal(err)
	}
	if !response.Verify(key) {
		t.Fatal("chunk response did not verify")
	}
}

func TestChunkAuthenticatorBindsObjectAndRange(t *testing.T) {
	key := []byte("shared-key")
	first := NewChunkAuthenticator(key, "bucket", "a/file", "v1", 0, 3)
	_, _ = first.Write([]byte("abc"))
	second := NewChunkAuthenticator(key, "bucket", "a/file", "v1", 0, 3)
	_, _ = second.Write([]byte("abc"))
	if !hmac.Equal(first.Sum(nil), second.Sum(nil)) {
		t.Fatal("matching chunk proof differs")
	}
	different := NewChunkAuthenticator(key, "bucket", "other", "v1", 0, 3)
	_, _ = different.Write([]byte("abc"))
	if hmac.Equal(first.Sum(nil), different.Sum(nil)) {
		t.Fatal("proof did not bind path")
	}
}
