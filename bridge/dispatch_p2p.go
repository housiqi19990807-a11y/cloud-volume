// P2P bridge lifecycle: one PeerManager per configured account so devices
// sharing any account can discover each other, not only the active profile.
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

// p2pManagerEntry tracks one account's manager plus the config it captured.
type p2pManagerEntry struct {
	manager *p2p.PeerManager
	secrets string // credential fingerprint, not a lifecycle hash
	label   string
}

var (
	p2pMu           sync.Mutex
	p2pManagers     = map[string]*p2pManagerEntry{}
	p2pHooksMounted bool
	// Profile names of managers disabled via the settings toggle. The toggle is
	// runtime-only for the current process; the persisted p2pEnabled flag in
	// each profile stays authoritative across restarts.
	p2pDisabledProfiles = map[string]bool{}
)

// p2pSecretsKey fingerprints only the credential material. Non-credential
// edits (cache dir, chunk size, timestamps) must NOT restart P2P, otherwise
// a backup/restore with a different timestamp would change the fingerprint.
func p2pSecretsKey(cfg storageconfig.RemoteStorageConfig) string {
	endpoint, principal, secret := p2pCredentials(cfg)
	return fmt.Sprintf("%x", sha256.Sum256([]byte(
		cfg.StorageType+"|"+endpoint+"|"+principal+"|"+secret)))
}

type bridgePeerReceiver struct {
	cfg storageconfig.RemoteStorageConfig
}

// OnPeerEvent refreshes only the announced parent directory in matching mounts.
func (r bridgePeerReceiver) OnPeerEvent(_ string, bucket, parentPath, _ string) {
	bucketmount.RefreshRemoteDirectory(r.cfg, bucket, parentPath)
}

// ensureP2PManagers reconciles running managers with the stored profiles:
// every enabled, fully configured account gets its own mDNS broadcast and
// QUIC listener; removed or disabled profiles are stopped. Extra overlays
// (e.g. an unsaved active config) are treated as one more account.
// P2P remains an optimization, so individual failures are logged, not fatal.
func ensureP2PManagers(overlays map[string]storageconfig.RemoteStorageConfig) error {
	accounts := map[string]storageconfig.RemoteStorageConfig{}
	if profiles, err := storageconfig.ListProfiles(); err == nil {
		for _, profile := range profiles {
			cfg, err := storageconfig.LoadProfile(profile.Name)
			if err != nil {
				log.Printf("[bridge/p2p] load profile %q: %v", profile.Name, err)
				continue
			}
			accounts[profile.Name] = cfg
		}
	}
	for name, cfg := range overlays {
		accounts[name] = cfg
	}
	runtimeDir, err := storageconfig.RuntimeDir()
	if err != nil {
		return err
	}
	var firstErr error
	for name, rawCfg := range accounts {
		cfg := rawCfg.Normalized().WithDefaultWebDAVCredentials()
		endpoint, principal, secret := p2pCredentials(cfg)
		enabled := cfg.P2PEnabled && cfg.IsConfigured() && secret != "" && !cfg.Disabled
		p2pMu.Lock()
		runtimeDisabled := p2pDisabledProfiles[name]
		entry := p2pManagers[name]
		p2pMu.Unlock()
		if !enabled {
			if entry != nil {
				stopP2PManager(name)
			}
			continue
		}
		secrets := p2pSecretsKey(cfg)
		if entry != nil && (entry.secrets != secrets || entry.label != cfg.AccountLabel(name)) {
			stopP2PManager(name)
			entry = nil
		}
		if entry == nil {
			fingerprint := p2p.AccountFingerprint(endpoint, principal)
			authKey := p2p.AccountAuthKey(endpoint, principal, secret)
			manager, err := p2p.NewPeerManager(runtimeDir, fingerprint, authKey, cfg.P2PChunkSizeMB)
			if err != nil {
				if firstErr == nil {
					firstErr = err
				}
				continue
			}
			manager.SetReceiver(bridgePeerReceiver{cfg: cfg})
			manager.SetContentResolver(func(ctx context.Context, bucket, path, hint string) (string, int64, bool) {
				return bucketmount.LocalPeerContentPath(cfg, bucket, path, hint)
			})
			entry = &p2pManagerEntry{manager: manager, secrets: secrets, label: cfg.AccountLabel(name)}
			p2pMu.Lock()
			p2pManagers[name] = entry
			p2pMu.Unlock()
		}
		if runtimeDisabled {
			continue
		}
		if err := entry.manager.Start(); err != nil {
			log.Printf("[bridge/p2p] start %q: %v", name, err)
			if firstErr == nil {
				firstErr = err
			}
		}
	}
	// Stop managers whose profile disappeared since the last reconcile.
	p2pMu.Lock()
	stale := []string{}
	for name := range p2pManagers {
		_, ok := accounts[name]
		if !ok {
			stale = append(stale, name)
		}
	}
	p2pMu.Unlock()
	for _, name := range stale {
		stopP2PManager(name)
	}
	installPeerHooks()
	return firstErr
}

// stopP2PManager removes and stops the manager for one profile.
func stopP2PManager(name string) {
	p2pMu.Lock()
	entry := p2pManagers[name]
	delete(p2pManagers, name)
	p2pMu.Unlock()
	if entry != nil {
		entry.manager.Stop()
	}
}

// managerForConfig finds the manager whose account fingerprint matches cfg,
// so mutations route through the manager that owns the matching peer set.
func managerForConfig(cfg storageconfig.RemoteStorageConfig) *p2p.PeerManager {
	cfg = cfg.Normalized().WithDefaultWebDAVCredentials()
	endpoint, principal, _ := p2pCredentials(cfg)
	fingerprint := p2p.AccountFingerprint(endpoint, principal)
	p2pMu.Lock()
	defer p2pMu.Unlock()
	for _, entry := range p2pManagers {
		if entry.manager.AccountFP() == fingerprint {
			return entry.manager
		}
	}
	return nil
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
	p2pMu.Lock()
	if p2pHooksMounted {
		p2pMu.Unlock()
		return
	}
	p2pHooksMounted = true
	p2pMu.Unlock()
	bucketmount.SetPeerBroadcastCallback(func(payload bucketmount.BroadcastPayload) {
		manager := managerForConfig(payload.Config)
		if manager != nil {
			manager.BroadcastMutation(payload.Bucket, payload.VirtualPath, parentDir(payload.VirtualPath), payload.VersionHint, payload.Operation)
		}
	})
	bucketmount.SetPeerContentFetcher(func(ctx context.Context, payload bucketmount.ContentFetchPayload) error {
		manager := managerForConfig(payload.Config)
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
func broadcastPeerMutation(cfg storageconfig.RemoteStorageConfig, bucket, path, operation string) {
	manager := managerForConfig(cfg)
	if manager != nil {
		manager.BroadcastMutation(bucket, path, parentDir(path), "", operation)
	}
}

func p2pStatus() (any, error) {
	p2pMu.Lock()
	entries := make([]*p2pManagerEntry, 0, len(p2pManagers))
	for _, entry := range p2pManagers {
		entries = append(entries, entry)
	}
	p2pMu.Unlock()
	if len(entries) == 0 {
		return map[string]any{"enabled": false, "deviceId": "", "peers": []any{}}, nil
	}
	// Merge every account manager into one UI snapshot: a device is unique by
	// ID, while "accounts" lists which of our accounts it shares with us.
	enabled := false
	deviceID := ""
	type peerAggregate struct {
		addr     string
		lastSeen string
		accounts map[string]bool
	}
	peerOrder := []string{}
	peerByDevice := map[string]*peerAggregate{}
	for _, entry := range entries {
		status := entry.manager.Status()
		enabled = enabled || status.Enabled
		if deviceID == "" {
			deviceID = status.DeviceID
		}
		for _, peer := range status.Peers {
			agg, ok := peerByDevice[peer.DeviceID]
			if !ok {
				agg = &peerAggregate{addr: peer.Addr, lastSeen: peer.LastSeen, accounts: map[string]bool{}}
				peerByDevice[peer.DeviceID] = agg
				peerOrder = append(peerOrder, peer.DeviceID)
			}
			agg.accounts[entry.label] = true
			if peer.LastSeen > agg.lastSeen {
				agg.lastSeen = peer.LastSeen
			}
		}
	}
	peers := make([]any, 0, len(peerOrder))
	for _, id := range peerOrder {
		agg := peerByDevice[id]
		accounts := make([]string, 0, len(agg.accounts))
		for label := range agg.accounts {
			accounts = append(accounts, label)
		}
		peers = append(peers, map[string]any{
			"deviceId": id,
			"addr":     agg.addr,
			"lastSeen": agg.lastSeen,
			"accounts": accounts,
		})
	}
	return map[string]any{"enabled": enabled, "deviceId": deviceID, "peers": peers}, nil
}

func setP2PEnabled(args json.RawMessage) (any, error) {
	var params struct {
		Enabled bool `json:"enabled"`
	}
	if err := json.Unmarshal(args, &params); err != nil {
		return nil, fmt.Errorf("parse args: %w", err)
	}
	// The settings toggle edits the active profile; other accounts keep their
	// own persisted p2pEnabled flag and are unaffected.
	profileName, err := storageconfig.ActiveProfileName()
	if err != nil {
		profileName = ""
	}
	p2pMu.Lock()
	var manager *p2p.PeerManager
	if entry := p2pManagers[profileName]; entry != nil {
		manager = entry.manager
	} else {
		// Fall back to the manager whose fingerprint matches the active config,
		// e.g. when the same account is also stored under another profile.
		if cfg, err := storageconfig.LoadProfile(profileName); err == nil {
			p2pMu.Unlock()
			manager = managerForConfig(cfg)
			p2pMu.Lock()
		}
	}
	if params.Enabled {
		delete(p2pDisabledProfiles, profileName)
	} else {
		p2pDisabledProfiles[profileName] = true
	}
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
