// Message type constants and content transfer protocol structures.
package p2p

// First byte of every QUIC stream message identifies its type.
const (
	MsgEvent        byte = 1 // signed peer event notification
	MsgContentQuery byte = 2 // "do you have this object?"
	MsgContentFetch byte = 3 // "send me bytes [offset, offset+length)"
)

// ContentQuery asks a peer whether it has a local copy of the given object
// at the specified version. The receiver responds with ContentResponse.
type ContentQuery struct {
	BucketFP    string `json:"bucketFp"`    // HMAC(accountFP, bucket)
	PathHash    string `json:"pathHash"`    // HMAC(accountFP, virtualPath)
	VersionHint string `json:"versionHint"` // ETag / mtime+size
}

// ContentResponse tells the requester whether the peer has the object.
// If Has is true, Sha256 and Size describe the full file content.
type ContentResponse struct {
	Has       bool   `json:"has"`
	Sha256    string `json:"sha256,omitempty"`    // full-file content hash
	Size      int64  `json:"size,omitempty"`      // total file size in bytes
	ChunkSize int64  `json:"chunkSize,omitempty"` // suggested chunk size
}

// ChunkRequest requests a specific byte range from the peer's local copy.
type ChunkRequest struct {
	PathHash string `json:"pathHash"`
	Offset   int64  `json:"offset"`
	Length   int64  `json:"length"`
}

// ChunkResponse carries a single block of file data.
type ChunkResponse struct {
	PathHash string `json:"pathHash"`
	Offset   int64  `json:"offset"`
	Data     []byte `json:"data"`
}
