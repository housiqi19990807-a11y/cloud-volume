// Content client downloads a verified remote-version cache entry from one LAN peer.
package p2p

import (
	"context"
	"crypto/hmac"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sync"

	"github.com/quic-go/quic-go"
)

const contentWorkers = 4

// FetchToFile tries each discovered peer until one serves every requested
// chunk. The caller owns destination cleanup and still validates remote state.
func (pm *PeerManager) FetchToFile(
	ctx context.Context,
	bucket, virtualPath, versionHint string,
	size int64,
	destination string,
	chunkSize int64,
) error {
	if size < 0 {
		return fmt.Errorf("invalid content size")
	}
	transport, peers := pm.peerSnapshot()
	if transport == nil || len(peers) == 0 {
		return fmt.Errorf("no LAN peers available")
	}
	if chunkSize <= 0 || chunkSize > 64*1024*1024 {
		chunkSize = pm.chunkSize()
	}
	for _, peer := range peers {
		if err := pm.fetchFromPeer(ctx, transport, peer, bucket, virtualPath, versionHint, size, destination, chunkSize); err == nil {
			return nil
		}
	}
	return fmt.Errorf("no LAN peer has %s", virtualPath)
}

func (pm *PeerManager) fetchFromPeer(
	ctx context.Context, transport *Transport, peer DiscoveredPeer,
	bucket, virtualPath, versionHint string, size int64, destination string, chunkSize int64,
) error {
	conn, err := transport.Connect(ctx, peer.Addr)
	if err != nil {
		return err
	}
	defer conn.CloseWithError(0, "done")
	if err := pm.queryPeer(ctx, conn, bucket, virtualPath, versionHint, size); err != nil {
		return err
	}
	file, err := os.OpenFile(destination, os.O_CREATE|os.O_RDWR|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	defer file.Close()
	if err := file.Truncate(size); err != nil {
		return err
	}
	if size == 0 {
		return nil
	}
	chunks := (size + chunkSize - 1) / chunkSize
	workerCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	jobs := make(chan int64)
	errs := make(chan error, 1)
	var workers sync.WaitGroup
	for worker := 0; worker < contentWorkers; worker++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for index := range jobs {
				offset := index * chunkSize
				length := chunkSize
				if remaining := size - offset; remaining < length {
					length = remaining
				}
				if err := pm.fetchChunk(workerCtx, conn, file, bucket, virtualPath, versionHint, offset, length); err != nil {
					select {
					case errs <- err:
						cancel()
					default:
					}
					return
				}
			}
		}()
	}
	for index := int64(0); index < chunks; index++ {
		select {
		case jobs <- index:
		case <-workerCtx.Done():
			break
		}
		if workerCtx.Err() != nil {
			break
		}
	}
	close(jobs)
	workers.Wait()
	select {
	case err := <-errs:
		return err
	default:
		return workerCtx.Err()
	}
}

func (pm *PeerManager) queryPeer(ctx context.Context, conn quicConnection, bucket, path, hint string, size int64) error {
	stream, err := conn.OpenStreamSync(ctx)
	if err != nil {
		return err
	}
	ps := &PeerStream{stream: stream}
	defer ps.Close()
	query := ContentQuery{Bucket: bucket, Path: path, VersionHint: hint}
	if err := query.Sign(pm.accountKey); err != nil {
		return err
	}
	payload, err := json.Marshal(query)
	if err != nil {
		return err
	}
	if err := ps.SendMessage(append([]byte{MsgContentQuery}, payload...)); err != nil {
		return err
	}
	reply, err := ps.RecvMessage()
	if err != nil || len(reply) == 0 || reply[0] != MsgContentReply {
		return fmt.Errorf("invalid peer content reply")
	}
	var response ContentResponse
	if err := json.Unmarshal(reply[1:], &response); err != nil || !response.Verify(pm.accountKey) || !response.Has || response.Size != size {
		return fmt.Errorf("peer content unavailable")
	}
	return nil
}

func (pm *PeerManager) fetchChunk(ctx context.Context, conn quicConnection, file *os.File, bucket, path, hint string, offset, length int64) error {
	stream, err := conn.OpenStreamSync(ctx)
	if err != nil {
		return err
	}
	ps := &PeerStream{stream: stream}
	defer ps.Close()
	request := ChunkRequest{Bucket: bucket, Path: path, VersionHint: hint, Offset: offset, Length: length}
	if err := request.Sign(pm.accountKey); err != nil {
		return err
	}
	payload, err := json.Marshal(request)
	if err != nil {
		return err
	}
	if err := ps.SendMessage(append([]byte{MsgContentFetch}, payload...)); err != nil {
		return err
	}
	reply, err := ps.RecvMessage()
	if err != nil || len(reply) == 0 || reply[0] != MsgContentChunk {
		return fmt.Errorf("invalid peer chunk reply")
	}
	var response ChunkResponse
	if err := json.Unmarshal(reply[1:], &response); err != nil || !response.Verify(pm.accountKey) || response.Offset != offset || response.Length != length {
		return fmt.Errorf("unexpected peer chunk")
	}
	mac := NewChunkAuthenticator(pm.accountKey, bucket, path, hint, offset, length)
	written, err := io.CopyN(io.MultiWriter(io.NewOffsetWriter(file, offset), mac), ps.stream, length)
	if err != nil {
		return fmt.Errorf("read peer chunk: %w", err)
	}
	if written != length {
		return fmt.Errorf("short peer chunk: got %d want %d", written, length)
	}
	proofFrame, err := ps.RecvMessage()
	if err != nil || len(proofFrame) == 0 || proofFrame[0] != MsgContentProof {
		return fmt.Errorf("missing peer chunk proof")
	}
	var proof ContentProof
	if err := json.Unmarshal(proofFrame[1:], &proof); err != nil || !hmac.Equal(mac.Sum(nil), proof.AuthTag) {
		return fmt.Errorf("invalid peer chunk proof")
	}
	return nil
}

// quicConnection captures just the methods shared by the quic-go connection.
type quicConnection interface {
	OpenStreamSync(context.Context) (*quic.Stream, error)
}
