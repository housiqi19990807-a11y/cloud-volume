// Package p2p implements LAN-local peer discovery, event broadcast, and
// content-acceleration between devices that share the same storage account.
// It uses mDNS for zero-config discovery and QUIC for encrypted transport.
package p2p

import (
	"crypto/ed25519"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

const identityFileName = "p2p-identity.json"

// DeviceIdentity holds the persistent Ed25519 key pair and device identifier.
// The private key signs peer events; the public key serves as a device
// fingerprint visible in mDNS TXT records.
type DeviceIdentity struct {
	DeviceID   string `json:"deviceId"`   // hex of first 8 bytes of public key
	PublicKey  []byte `json:"publicKey"`  // Ed25519 public key (32 bytes)
	PrivateKey []byte `json:"privateKey"` // Ed25519 private key (64 bytes, OS-protected file)
}

// identityStore caches the loaded identity so repeated lookups are free.
var (
	identityMu     sync.Mutex
	identityCached *DeviceIdentity
)

// LoadOrCreateIdentity loads the device identity from the runtime directory,
// or generates a new one on first run. The identity file is created with
// 0600 permissions so the private key is only readable by the current user.
func LoadOrCreateIdentity(runtimeDir string) (*DeviceIdentity, error) {
	identityMu.Lock()
	defer identityMu.Unlock()
	if identityCached != nil {
		return identityCached, nil
	}
	path := filepath.Join(runtimeDir, identityFileName)
	if data, err := os.ReadFile(path); err == nil {
		var id DeviceIdentity
		if err := json.Unmarshal(data, &id); err == nil && len(id.PrivateKey) == ed25519.PrivateKeySize {
			identityCached = &id
			return &id, nil
		}
	}
	// First run: generate a fresh key pair.
	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate identity: %w", err)
	}
	id := DeviceIdentity{
		DeviceID:   hex.EncodeToString(pub[:8]),
		PublicKey:  pub,
		PrivateKey: priv,
	}
	blob, err := json.Marshal(id)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(runtimeDir, 0o700); err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, blob, 0o600); err != nil {
		return nil, fmt.Errorf("write identity: %w", err)
	}
	identityCached = &id
	return &id, nil
}

// AccountFingerprint computes a 16-byte hex hash that identifies a storage
// account without revealing credentials. Two devices with the same endpoint
// and access key produce the same fingerprint, enabling zero-config trust.
func AccountFingerprint(endpoint, accessKey string) string {
	mac := hmac.New(sha256.New, []byte("cloud-volume-lan-discovery-v1"))
	mac.Write([]byte(endpoint))
	mac.Write([]byte{0})
	mac.Write([]byte(accessKey))
	sum := mac.Sum(nil)
	return hex.EncodeToString(sum[:16])
}

// AccountAuthKey derives an in-memory shared key for authenticated LAN
// messages. The secret never leaves a device; the public account fingerprint
// is intentionally not sufficient to authenticate a peer.
func AccountAuthKey(endpoint, accessKey, secret string) []byte {
	mac := hmac.New(sha256.New, []byte("cloud-volume-lan-auth-v1"))
	mac.Write([]byte(endpoint))
	mac.Write([]byte{0})
	mac.Write([]byte(accessKey))
	mac.Write([]byte{0})
	mac.Write([]byte(secret))
	return mac.Sum(nil)
}

// AuthenticatePayload returns a tag a peer can validate only when it has the
// same account secret-derived key.
func AuthenticatePayload(accountKey, payload []byte) []byte {
	mac := hmac.New(sha256.New, accountKey)
	mac.Write(payload)
	return mac.Sum(nil)
}

// VerifyPayloadAuthentication validates a message authentication tag.
func VerifyPayloadAuthentication(accountKey, payload, tag []byte) bool {
	expected := AuthenticatePayload(accountKey, payload)
	return hmac.Equal(expected, tag)
}

// BucketFingerprint derives a per-bucket hash using the account fingerprint
// as the HMAC key. Events reference a bucket without sending its real name.
func BucketFingerprint(accountFP, bucket string) string {
	mac := hmac.New(sha256.New, []byte(accountFP))
	mac.Write([]byte(bucket))
	sum := mac.Sum(nil)
	return hex.EncodeToString(sum[:16])
}

// PathHash derives a per-path hash so events can signal which virtual path
// changed without leaking the actual filename.
func PathHash(accountFP, virtualPath string) string {
	mac := hmac.New(sha256.New, []byte(accountFP))
	mac.Write([]byte(virtualPath))
	sum := mac.Sum(nil)
	return hex.EncodeToString(sum[:16])
}

// SignPayload signs an arbitrary byte payload with the device private key.
func (id *DeviceIdentity) SignPayload(payload []byte) []byte {
	return ed25519.Sign(id.PrivateKey, payload)
}

// VerifySignature checks a signature against an Ed25519 public key.
func VerifySignature(publicKey, payload, signature []byte) bool {
	if len(publicKey) != ed25519.PublicKeySize {
		return false
	}
	return ed25519.Verify(publicKey, payload, signature)
}
