// P2P bridge dispatchers expose LAN peer discovery and control to the Flutter
// settings UI. The bridge wires the mount broadcast hook to the PeerManager
// so that writeback successes fan out to trusted LAN peers automatically.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"sync"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	"remote-storage/go/p2p"
)

// p2pManagerHolder keeps the singleton PeerManager and its config provider.
var (
	p2pOnce   sync.Once
	p2pMgr    *p2p.PeerManager
	p2pErr    error
	p2pCfg    *p2pConfigProvider
)

// p2pConfigProvider adapts the stored RemoteStorageConfig to the P2P layer's
// ConfigProvider interface. It holds a pointer so settings changes take effect
// without recreating the manager.
type p2pConfigProvider struct {
	mu       sync.Mutex
	enabled  bool
	chunkMB  int
	endpoint string
	accessKey string
}

func (p *p2pConfigProvider) P2PEnabled() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.enabled
}

func (p *p2pConfigProvider) P2PChunkSizeMB() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.chunkMB
}

func (p *p2pConfigProvider) AccountFingerprint() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p2p.AccountFingerprint(p.endpoint, p.accessKey)
}

// ensureP2PManager lazily creates and starts the PeerManager based on the
// current config. It is called from load_bootstrap_state and after save_config.
func ensureP2PManager(cfg storageconfig.RemoteStorageConfig) error {
	p2pOnce.Do(func() {
		p2pCfg = &p2pConfigProvider{
			enabled:   cfg.P2PEnabled,
			chunkMB:   cfg.P2PChunkSizeMB,
			endpoint:  cfg.Endpoint,
			accessKey: cfg.AccessKeyID,
		}
		runtimeDir, err := storageconfig.RuntimeDir()
		if err != nil {
			p2pErr = err
			return
		}
		p2pMgr, p2pErr = p2p.NewPeerManager(runtimeDir, p2pCfg)
		if p2pErr != nil {
			return
		}
		// Wire mount broadcast hook to the P2P manager.
		bucketmount.SetPeerBroadcastCallback(func(bp bucketmount.BroadcastPayload) {
			if p2pMgr == nil || !p2pMgr.IsEnabled() {
				return
			}
			accountFP := p2pCfg.AccountFingerprint()
			bucketFP := p2p.BucketFingerprint(accountFP, bp.Bucket)
			pathHash := p2p.PathHash(accountFP, bp.VirtualPath)
			parentPath := parentDir(bp.VirtualPath)
			parentHash := p2p.PathHash(accountFP, parentPath)
			p2pMgr.BroadcastMutation(bucketFP, pathHash, parentHash, bp.VersionHint, bp.Operation)
		})
	})
	if p2pErr != nil {
		return p2pErr
	}
	// Apply config changes.
	p2pCfg.mu.Lock()
	p2pCfg.enabled = cfg.P2PEnabled
	p2pCfg.chunkMB = cfg.P2PChunkSizeMB
	p2pCfg.endpoint = cfg.Endpoint
	p2pCfg.accessKey = cfg.AccessKeyID
	shouldEnable := cfg.P2PEnabled
	p2pCfg.mu.Unlock()

	if shouldEnable {
		if !p2pMgr.IsEnabled() {
			if err := p2pMgr.Start(); err != nil {
				log.Printf("[bridge/p2p] start-error: %v", err)
				return err
			}
		}
	} else {
		if p2pMgr.IsEnabled() {
			p2pMgr.Stop()
		}
	}
	return nil
}

// parentDir returns the parent directory of a virtual path (e.g. "a/b/c" -> "a/b").
func parentDir(virtualPath string) string {
	for i := len(virtualPath) - 1; i >= 0; i-- {
		if virtualPath[i] == '/' {
			return virtualPath[:i]
		}
	}
	return ""
}

// p2pStatus handles the "get_p2p_status" bridge method.
func p2pStatus() (any, error) {
	if p2pMgr == nil {
		return map[string]any{
			"enabled":  false,
			"deviceId": "",
			"peers":    []any{},
		}, nil
	}
	data, err := p2pMgr.StatusJSON()
	if err != nil {
		return nil, err
	}
	var result any
	return result, json.Unmarshal(data, &result)
}

// setP2PEnabled handles the "set_p2p_enabled" bridge method.
func setP2PEnabled(args json.RawMessage) (any, error) {
	var params struct {
		Enabled bool `json:"enabled"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return nil, fmt.Errorf("parse args: %w", err)
	}
	if p2pMgr == nil {
		return nil, fmt.Errorf("p2p manager not initialized")
	}
	if err := p2pMgr.SetEnabled(params.Enabled); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true, "enabled": params.Enabled}, nil
}
