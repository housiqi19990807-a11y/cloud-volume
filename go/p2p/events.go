// Peer event structures and serialization for LAN change notifications.
package p2p

import (
	"crypto/ed25519"
	"encoding/hex"
	"encoding/json"
	"time"
)

const (
	OpUpload = "upload"
	OpDelete = "delete"
	OpRename = "rename"
)

// PeerEvent is the signed payload broadcast to trusted LAN peers after a
// remote-confirmed mutation. Bucket and path are sent inside the authenticated
// TLS session so receivers can refresh the exact directory without attempting
// to reverse a hash. They are never advertised through mDNS.
type PeerEvent struct {
	DeviceID    string `json:"deviceId"`          // sender device identifier
	Sequence    uint64 `json:"sequence"`          // per-device monotonic counter for dedup
	AccountFP   string `json:"accountFp"`         // account fingerprint (matches receivers)
	BucketFP    string `json:"bucketFp"`          // HMAC(accountFP, bucket) — not plaintext
	PathHash    string `json:"pathHash"`          // HMAC(accountFP, virtualPath)
	ParentHash  string `json:"parentHash"`        // HMAC(accountFP, parent dir)
	VersionHint string `json:"versionHint"`       // ETag / mtime+size for version check
	Operation   string `json:"operation"`         // "upload" | "delete" | "rename"
	OldHash     string `json:"oldHash,omitempty"` // for rename: HMAC of old path
	Bucket      string `json:"bucket,omitempty"`
	Path        string `json:"path,omitempty"`
	ParentPath  string `json:"parentPath,omitempty"`
	Timestamp   int64  `json:"timestamp"` // unix milliseconds
	Nonce       string `json:"nonce"`     // random hex for replay protection
}

// SignedEvent wraps a PeerEvent with an Ed25519 signature over the JSON payload.
type SignedEvent struct {
	Event     PeerEvent `json:"event"`
	PublicKey []byte    `json:"publicKey"`
	Signature []byte    `json:"signature"` // Ed25519 over event bytes
	AuthTag   []byte    `json:"authTag"`   // HMAC using AccountAuthKey
}

// NewEvent creates a PeerEvent populated with timestamp and nonce.
func NewEvent(op, accountFP, bucketFP, pathHash, parentHash, versionHint string) PeerEvent {
	return PeerEvent{
		DeviceID:    "", // filled by sender
		Sequence:    0,  // filled by sender
		AccountFP:   accountFP,
		BucketFP:    bucketFP,
		PathHash:    pathHash,
		ParentHash:  parentHash,
		VersionHint: versionHint,
		Operation:   op,
		Timestamp:   time.Now().UnixMilli(),
		Nonce:       randomHex(8),
	}
}

// MarshalForSigning serializes the event deterministically for signing.
func (e PeerEvent) MarshalForSigning() ([]byte, error) {
	return json.Marshal(e)
}

// Sign produces a SignedEvent by signing the event payload.
func (e PeerEvent) Sign(
	identity *DeviceIdentity,
	accountKey []byte,
) (SignedEvent, error) {
	payload, err := e.MarshalForSigning()
	if err != nil {
		return SignedEvent{}, err
	}
	return SignedEvent{
		Event:     e,
		PublicKey: identity.PublicKey,
		Signature: identity.SignPayload(payload),
		AuthTag:   AuthenticatePayload(accountKey, payload),
	}, nil
}

// Verify checks both account authentication and the sender device signature.
func (s SignedEvent) Verify(accountKey []byte) bool {
	payload, err := s.Event.MarshalForSigning()
	if err != nil {
		return false
	}
	if !VerifyPayloadAuthentication(accountKey, payload, s.AuthTag) {
		return false
	}
	if len(s.PublicKey) != ed25519.PublicKeySize ||
		s.Event.DeviceID != hex.EncodeToString(s.PublicKey[:8]) {
		return false
	}
	return VerifySignature(s.PublicKey, payload, s.Signature)
}

// Encode serializes a SignedEvent to JSON bytes for QUIC transmission.
func (s SignedEvent) Encode() ([]byte, error) {
	return json.Marshal(s)
}

// DecodeSignedEvent parses a SignedEvent from JSON bytes.
func DecodeSignedEvent(data []byte) (SignedEvent, error) {
	var se SignedEvent
	err := json.Unmarshal(data, &se)
	return se, err
}
