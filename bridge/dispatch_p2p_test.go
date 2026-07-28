// P2P bridge tests protect manager routing and credential-change replacement.
package main

import (
	"testing"

	storageconfig "remote-storage/go/config"
	"remote-storage/go/p2p"
)

// The manager lifecycle must follow credential material only. Timestamps or
// non-credential fields (cache dir, chunk size) must not restart P2P.
func TestP2PSecretsKeyIgnoresNonCredentialFields(t *testing.T) {
	base := storageconfig.RemoteStorageConfig{
		Endpoint:        "https://example.test",
		AccessKeyID:     "access",
		SecretAccessKey: "secret",
		P2PEnabled:      true,
		P2PChunkSizeMB:  4,
	}.Normalized()
	baseKey := p2pSecretsKey(base)

	updated := base
	updated.CacheDirectory = "C:/cache/updated"
	updated.P2PChunkSizeMB = 16
	if p2pSecretsKey(updated) != baseKey {
		t.Fatal("non-credential change must not alter the P2P secrets key")
	}

	rotated := base
	rotated.SecretAccessKey = "new-secret"
	if p2pSecretsKey(rotated) == baseKey {
		t.Fatal("credential change must alter the P2P secrets key")
	}
}

// Mutations must route to the manager whose account fingerprint matches the
// originating config, not to whichever profile happens to be active.
func TestManagerForConfigMatchesAccountFingerprint(t *testing.T) {
	t.Setenv("CLOUD_VOLUME_DATA_DIR", t.TempDir())
	cfgA := storageconfig.RemoteStorageConfig{
		Endpoint:        "https://a.example.test",
		AccessKeyID:     "access-a",
		SecretAccessKey: "secret-a",
		P2PEnabled:      true,
	}.Normalized()
	cfgB := storageconfig.RemoteStorageConfig{
		Endpoint:        "https://b.example.test",
		AccessKeyID:     "access-b",
		SecretAccessKey: "secret-b",
		P2PEnabled:      true,
	}.Normalized()

	runtimeDir := t.TempDir()
	mkManager := func(cfg storageconfig.RemoteStorageConfig) *p2p.PeerManager {
		endpoint, principal, secret := p2pCredentials(cfg)
		manager, err := p2p.NewPeerManager(runtimeDir,
			p2p.AccountFingerprint(endpoint, principal),
			p2p.AccountAuthKey(endpoint, principal, secret), cfg.P2PChunkSizeMB)
		if err != nil {
			t.Fatal(err)
		}
		return manager
	}
	mgrA, mgrB := mkManager(cfgA), mkManager(cfgB)

	p2pMu.Lock()
	savedManagers, savedDisabled := p2pManagers, p2pDisabledProfiles
	p2pManagers = map[string]*p2pManagerEntry{
		"profile-a": {manager: mgrA, secrets: "a"},
		"profile-b": {manager: mgrB, secrets: "b"},
	}
	p2pDisabledProfiles = map[string]bool{}
	p2pMu.Unlock()
	t.Cleanup(func() {
		p2pMu.Lock()
		p2pManagers, p2pDisabledProfiles = savedManagers, savedDisabled
		p2pMu.Unlock()
	})

	if got := managerForConfig(cfgA); got != mgrA {
		t.Fatal("mutation for account A routed to the wrong manager")
	}
	if got := managerForConfig(cfgB); got != mgrB {
		t.Fatal("mutation for account B routed to the wrong manager")
	}
	unknown := cfgA
	unknown.AccessKeyID = "someone-else"
	if got := managerForConfig(unknown); got != nil {
		t.Fatal("unknown account unexpectedly matched a manager")
	}
}
