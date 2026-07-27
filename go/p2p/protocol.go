// Message type constants and content transfer protocol structures.
package p2p

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"hash"
)

// First byte of every QUIC stream message identifies its type.
const (
	MsgEvent        byte = 1 // signed peer event notification
	MsgContentQuery byte = 2 // "do you have this object?"
	MsgContentFetch byte = 3 // "send me bytes [offset, offset+length)"
	MsgContentReply byte = 4 // content-query response
	MsgContentChunk byte = 5 // chunk metadata followed by raw bytes
	MsgContentProof byte = 6 // HMAC for the preceding raw chunk bytes
)

// ContentQuery asks a peer whether it has a local copy of the given object
// at the specified version. The receiver responds with ContentResponse.
type ContentQuery struct {
	Bucket      string `json:"bucket"`
	Path        string `json:"path"`
	VersionHint string `json:"versionHint"` // ETag / mtime+size
	AuthTag     []byte `json:"authTag"`
}

// ContentResponse tells the requester whether the peer has the object.
// If Has is true, Sha256 and Size describe the full file content.
type ContentResponse struct {
	Has       bool   `json:"has"`
	Sha256    string `json:"sha256,omitempty"`    // full-file content hash
	Size      int64  `json:"size,omitempty"`      // total file size in bytes
	ChunkSize int64  `json:"chunkSize,omitempty"` // suggested chunk size
	AuthTag   []byte `json:"authTag"`
}

// ChunkRequest requests a specific byte range from the peer's local copy.
type ChunkRequest struct {
	Bucket      string `json:"bucket"`
	Path        string `json:"path"`
	VersionHint string `json:"versionHint"`
	Offset      int64  `json:"offset"`
	Length      int64  `json:"length"`
	AuthTag     []byte `json:"authTag"`
}

// ChunkResponse describes raw chunk bytes that immediately follow its framed
// metadata on the same QUIC stream.
type ChunkResponse struct {
	Offset  int64  `json:"offset"`
	Length  int64  `json:"length"`
	AuthTag []byte `json:"authTag"`
}

// ContentProof follows a raw chunk and authenticates its bytes plus identity.
type ContentProof struct {
	AuthTag []byte `json:"authTag"`
}

// NewChunkAuthenticator binds raw bytes to the exact requested object range.
// Callers stream bytes through the returned hash while sending or receiving.
func NewChunkAuthenticator(accountKey []byte, bucket, path, versionHint string, offset, length int64) hash.Hash {
	mac := hmac.New(sha256.New, accountKey)
	for _, value := range []string{bucket, path, versionHint} {
		_, _ = mac.Write([]byte(value))
		_, _ = mac.Write([]byte{0})
	}
	var rangeBytes [16]byte
	binary.BigEndian.PutUint64(rangeBytes[:8], uint64(offset))
	binary.BigEndian.PutUint64(rangeBytes[8:], uint64(length))
	_, _ = mac.Write(rangeBytes[:])
	return mac
}

// Sign authenticates a control request without including the tag itself in
// its canonical payload.
func (q *ContentQuery) Sign(accountKey []byte) error {
	q.AuthTag = nil
	payload, err := json.Marshal(q)
	if err != nil {
		return err
	}
	q.AuthTag = AuthenticatePayload(accountKey, payload)
	return nil
}

// Verify rejects requests from devices that do not share this account secret.
func (q ContentQuery) Verify(accountKey []byte) bool {
	tag := q.AuthTag
	q.AuthTag = nil
	payload, err := json.Marshal(q)
	return err == nil && VerifyPayloadAuthentication(accountKey, payload, tag)
}

// Sign authenticates a byte-range request.
func (r *ChunkRequest) Sign(accountKey []byte) error {
	r.AuthTag = nil
	payload, err := json.Marshal(r)
	if err != nil {
		return err
	}
	r.AuthTag = AuthenticatePayload(accountKey, payload)
	return nil
}

// Verify validates a byte-range request before the provider opens a file.
func (r ChunkRequest) Verify(accountKey []byte) bool {
	tag := r.AuthTag
	r.AuthTag = nil
	payload, err := json.Marshal(r)
	return err == nil && VerifyPayloadAuthentication(accountKey, payload, tag)
}

// Sign authenticates a peer availability response.
func (r *ContentResponse) Sign(accountKey []byte) error {
	r.AuthTag = nil
	payload, err := json.Marshal(r)
	if err != nil {
		return err
	}
	r.AuthTag = AuthenticatePayload(accountKey, payload)
	return nil
}

func (r ContentResponse) Verify(accountKey []byte) bool {
	tag := r.AuthTag
	r.AuthTag = nil
	payload, err := json.Marshal(r)
	return err == nil && VerifyPayloadAuthentication(accountKey, payload, tag)
}

// Sign authenticates chunk metadata before raw bytes follow on the stream.
func (r *ChunkResponse) Sign(accountKey []byte) error {
	r.AuthTag = nil
	payload, err := json.Marshal(r)
	if err != nil {
		return err
	}
	r.AuthTag = AuthenticatePayload(accountKey, payload)
	return nil
}

func (r ChunkResponse) Verify(accountKey []byte) bool {
	tag := r.AuthTag
	r.AuthTag = nil
	payload, err := json.Marshal(r)
	return err == nil && VerifyPayloadAuthentication(accountKey, payload, tag)
}
