// P2P bridge lifecycle wires account credentials, mounts, and the settings UI.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"log"
	"sync"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	"remote-storage/go/p2p"
)

var (
	p2pMu  sync.Mutex
	p2pMgr *p2p.PeerManager
	p2pKey string
)

type bridgePeerReceiver struct {
	cfg storageconfig.RemoteStorageConfig
}

// OnPeerEvent refreshes only the announced parent directory in matching mounts.
func (r bridgePeerReceiver) OnPeerEvent(_ string, bucket, parentPath, _ string) {
	bucketmount.RefreshRemoteDirectory(r.cfg, bucket, parentPath)
}

// ensureP2PManager applies a private, credential-bearing account config.
// P2P remains an optimization, so startup errors are reported but non-fatal.
func ensureP2PManager(cfg storageconfig.RemoteStorageConfig) error {
	cfg = cfg.Normalized()
	endpoint, principal, secret := p2pCredentials(cfg)
	if !cfg.P2PEnabled || !cfg.IsConfigured() || secret == "" {
		p2pMu.Lock()
		old := p2pMgr
		p2pMgr, p2pKey = nil, ""
		p2pMu.Unlock()
		if old != nil {
			old.Stop()
		}
		return nil
	}
	fingerprint := p2p.AccountFingerprint(endpoint, principal)
	authKey := p2p.AccountAuthKey(endpoint, principal, secret)
	key, err := p2pManagerKey(cfg)
	if err != nil {
		return err
	}
	p2pMu.Lock()
	if p2pMgr != nil && p2pKey == key {
		manager := p2pMgr
		p2pMu.Unlock()
		return manager.Start()
	}
	old := p2pMgr
	p2pMgr, p2pKey = nil, ""
	p2pMu.Unlock()
	if old != nil {
		old.Stop()
	}
	runtimeDir, err := storageconfig.RuntimeDir()
	if err != nil {
		return err
	}
	manager, err := p2p.NewPeerManager(runtimeDir, fingerprint, authKey, cfg.P2PChunkSizeMB)
	if err != nil {
		return err
	}
	manager.SetReceiver(bridgePeerReceiver{cfg: cfg})
	manager.SetContentResolver(func(ctx context.Context, bucket, path, hint string) (string, int64, bool) {
		return bucketmount.LocalPeerContentPath(cfg, bucket, path, hint)
	})
	p2pMu.Lock()
	p2pMgr, p2pKey = manager, key
	p2pMu.Unlock()
	if err := manager.Start(); err != nil {
		return err
	}
	installPeerHooks()
	return nil
}

// p2pManagerKey follows the full captured config, not merely account credentials.
func p2pManagerKey(cfg storageconfig.RemoteStorageConfig) (string, error) {
	configBytes, err := json.Marshal(cfg)
	if err != nil {
		return "", fmt.Errorf("encode P2P config: %w", err)
	}
	return fmt.Sprintf("%x", sha256.Sum256(configBytes)), nil
}

func p2pCredentials(cfg storageconfig.RemoteStorageConfig) (endpoint, principal, secret string) {
	switch cfg.StorageType {
	case storageconfig.StorageTypeWebDAV:
		return cfg.Endpoint, cfg.WebDAVUsername, cfg.WebDAVPassword
	case storageconfig.StorageTypeFTP, storageconfig.StorageTypeSFTP:
		return cfg.Endpoint, cfg.FTPUsername, cfg.FTPPassword
	default:
		return cfg.Endpoint, cfg.AccessKeyID, cfg.SecretAccessKey
	}
}

func installPeerHooks() {
	bucketmount.SetPeerBroadcastCallback(func(payload bucketmount.BroadcastPayload) {
		p2pMu.Lock()
		manager := p2pMgr
		p2pMu.Unlock()
		if manager != nil {
			manager.BroadcastMutation(payload.Bucket, payload.VirtualPath, parentDir(payload.VirtualPath), payload.VersionHint, payload.Operation)
		}
	})
	bucketmount.SetPeerContentFetcher(func(ctx context.Context, payload bucketmount.ContentFetchPayload) error {
		p2pMu.Lock()
		manager := p2pMgr
		p2pMu.Unlock()
		if manager == nil {
			return fmt.Errorf("P2P disabled")
		}
		return manager.FetchToFile(ctx, payload.Bucket, payload.VirtualPath, payload.VersionHint, payload.Size, payload.DestinationPath, payload.ChunkSize)
	})
}

func parentDir(virtualPath string) string {
	for index := len(virtualPath) - 1; index >= 0; index-- {
		if virtualPath[index] == '/' {
			return virtualPath[:index]
		}
	}
	return ""
}

// broadcastPeerMutation mirrors a remote-confirmed bridge mutation to LAN peers.
func broadcastPeerMutation(bucket, path, operation string) {
	p2pMu.Lock()
	manager := p2pMgr
	p2pMu.Unlock()
	if manager != nil {
		manager.BroadcastMutation(bucket, path, parentDir(path), "", operation)
	}
}

func p2pStatus() (any, error) {
	p2pMu.Lock()
	manager := p2pMgr
	p2pMu.Unlock()
	if manager == nil {
		return map[string]any{"enabled": false, "deviceId": "", "peers": []any{}}, nil
	}
	data, err := manager.StatusJSON()
	if err != nil {
		return nil, err
	}
	var result any
	return result, json.Unmarshal(data, &result)
}

func setP2PEnabled(args json.RawMessage) (any, error) {
	var params struct {
		Enabled bool `json:"enabled"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return nil, fmt.Errorf("parse args: %w", err)
	}
	p2pMu.Lock()
	manager := p2pMgr
	p2pMu.Unlock()
	if manager == nil {
		if !params.Enabled {
			return map[string]any{"ok": true, "enabled": false}, nil
		}
		return nil, fmt.Errorf("P2P is unavailable until an account is configured")
	}
	if err := manager.SetEnabled(params.Enabled); err != nil {
		log.Printf("[bridge/p2p] toggle error: %v", err)
		return nil, err
	}
	return map[string]any{"ok": true, "enabled": params.Enabled}, nil
}
