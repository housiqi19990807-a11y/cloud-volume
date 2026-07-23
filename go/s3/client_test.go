// Client cache tests keep gateway discovery from becoming a per-object cost.
package s3

import (
	"testing"
	"time"

	storageconfig "remote-storage/go/config"
)

func TestActiveEndpointCacheUsesConfigIdentityAndExpires(t *testing.T) {
	cfg := storageconfig.RemoteStorageConfig{
		Endpoint:          "https://gateway.example",
		StorageType:       storageconfig.StorageTypeS3,
		AccessKeyID:       "test-ak",
		JWanFSGatewayMode: storageconfig.JWanFSGatewayModeAuto,
	}
	key := activeEndpointCacheKey(cfg)

	activeEndpointCacheMu.Lock()
	delete(activeEndpointCache, key)
	activeEndpointCacheMu.Unlock()
	t.Cleanup(func() {
		activeEndpointCacheMu.Lock()
		delete(activeEndpointCache, key)
		activeEndpointCacheMu.Unlock()
	})

	cacheActiveEndpoint(cfg, "https://gw-2.example")
	if endpoint, ok := cachedActiveEndpoint(cfg); !ok || endpoint != "https://gw-2.example" {
		t.Fatalf("cached endpoint = %q, ok=%v", endpoint, ok)
	}

	activeEndpointCacheMu.Lock()
	entry := activeEndpointCache[key]
	entry.expiresAt = time.Now().Add(-time.Second)
	activeEndpointCache[key] = entry
	activeEndpointCacheMu.Unlock()
	if _, ok := cachedActiveEndpoint(cfg); ok {
		t.Fatal("expired endpoint cache entry remained usable")
	}
}
