// Baidu Pan SDK helpers centralize OAuth token reuse around the xpan globals.
package storage

import (
	"errors"
	"fmt"
	"strings"
	"sync"

	xpanauth "github.com/lfhy/xpan/auth"
	xpanclient "github.com/lfhy/xpan/client"
	xpanhttp "github.com/lfhy/xpan/http"
	xpantypes "github.com/lfhy/xpan/types"

	storageconfig "remote-storage/go/config"
	bridgelog "remote-storage/go/logging"
)

const (
	baiduPanClientID     = "LXSNsyO78fe6j3RkXsY0UBhC191P4RW6"
	baiduPanClientSecret = "2FdwKMRizTw45rnMS4fon22hHa1ZIRQz"
	baiduPanEndpoint     = "https://pan.baidu.com"
	baiduPanUploadRoot   = "/apps/网盘demo"
)

type baiduPanAuthState struct {
	accessToken  string
	refreshToken string
}

var (
	baiduPanSDKMu    sync.Mutex
	baiduPanSessions sync.Map
)

func init() {
	// Keep one reusable HTTP client for SDK calls and retry transient upstream throttling.
	xpanhttp.SetClient(newBaiduPanRetryHTTPClient())
	// The SDK's conservative default rate limit is too low for 4 MB upload chunks.
	xpanhttp.SetRateLimitEnabled(false)
}

// ApplyBaiduPanProxy replaces the SDK's global HTTP client with one that uses
// the global proxy transport. Per-account proxy is handled per-Client via
// baiduPanHTTPClientForConfig; this sets the fallback for code paths that have
// not been migrated to per-Client usage.
func ApplyBaiduPanProxy(cfg storageconfig.RemoteStorageConfig) {
	xpanhttp.SetClient(newBaiduPanRetryHTTPClientWithClient(
		storageconfig.ProxyHTTPClient(cfg, 0),
	))
}

func baiduPanConfigFromAuth(
	displayName string,
	accessToken string,
	refreshToken string,
) storageconfig.RemoteStorageConfig {
	cfg := storageconfig.DefaultConfig()
	cfg.Endpoint = baiduPanEndpoint
	cfg.StorageType = storageconfig.StorageTypeBaiduPan
	cfg.ProviderType = storageconfig.StorageTypeBaiduPan
	cfg.DisplayName = strings.TrimSpace(displayName)
	cfg.MappedBucketName = strings.TrimSpace(displayName)
	cfg.AccessKeyID = strings.TrimSpace(accessToken)
	cfg.SecretAccessKey = strings.TrimSpace(refreshToken)
	cfg.HasSecretAccessKey = cfg.SecretAccessKey != ""
	return cfg.Normalized()
}

func baiduPanBucketLabel(cfg storageconfig.RemoteStorageConfig) string {
	label := strings.TrimSpace(cfg.MappedBucketLabel())
	if label != "" {
		return label
	}
	if name := strings.TrimSpace(cfg.DisplayName); name != "" {
		return name
	}
	return "百度网盘"
}

func withBaiduPanClient[T any](
	cfg storageconfig.RemoteStorageConfig,
	fn func(*xpanclient.Client) (T, error),
) (T, error) {
	var zero T

	baiduPanSDKMu.Lock()
	state := baiduPanStateForConfig(cfg)
	baiduPanSDKMu.Unlock()

	// Build a per-account HTTP client carrying its own proxy transport and
	// credentials. For inherit-mode accounts this resolves to the global proxy.
	httpClient := baiduPanHTTPClientForConfig(cfg, state)
	client := xpanclient.NewWithClient(httpClient, &xpanauth.AuthEnv{
		ClientId:     baiduPanClientID,
		ClientSecret: baiduPanClientSecret,
		AccessToken:  state.accessToken,
		RefreshToken: state.refreshToken,
	})

	result, err := fn(client)
	if err == nil || !shouldRefreshBaiduPanToken(err) || state.refreshToken == "" {
		return result, err
	}
	bridgelog.Infof(
		"[storage/baidu-pan] authentication expired profile=%q; refreshing OAuth token",
		cfg.DisplayName,
	)
	baiduPanSDKMu.Lock()
	refreshed, refreshErr := refreshBaiduPanStateLocked(state)
	if refreshErr != nil {
		baiduPanSDKMu.Unlock()
		bridgelog.Errorf(
			"[storage/baidu-pan] OAuth token refresh failed profile=%q err=%v",
			cfg.DisplayName,
			refreshErr,
		)
		return zero, fmt.Errorf("refresh Baidu Pan OAuth token: %w", refreshErr)
	}
	rememberBaiduPanState(baiduPanSessionKeys(cfg, state), refreshed)
	if persistErr := persistBaiduPanState(cfg, refreshed); persistErr != nil {
		bridgelog.Errorf(
			"[storage/baidu-pan] persist refreshed OAuth token failed profile=%q err=%v",
			cfg.DisplayName,
			persistErr,
		)
	}
	baiduPanSDKMu.Unlock()

	// Rebuild client with refreshed token.
	refreshedHTTPClient := baiduPanHTTPClientForConfig(cfg, refreshed)
	refreshedClient := xpanclient.NewWithClient(refreshedHTTPClient, &xpanauth.AuthEnv{
		ClientId:     baiduPanClientID,
		ClientSecret: baiduPanClientSecret,
		AccessToken:  refreshed.accessToken,
		RefreshToken: refreshed.refreshToken,
	})
	result, retryErr := fn(refreshedClient)
	if retryErr != nil {
		bridgelog.Errorf(
			"[storage/baidu-pan] request retry after OAuth refresh failed profile=%q err=%v",
			cfg.DisplayName,
			retryErr,
		)
	}
	return result, retryErr
}

func baiduPanStateForConfig(cfg storageconfig.RemoteStorageConfig) baiduPanAuthState {
	keys := baiduPanSessionKeys(
		cfg,
		baiduPanAuthState{
			accessToken:  cfg.AccessKeyID,
			refreshToken: cfg.SecretAccessKey,
		},
	)
	for _, key := range keys {
		if value, ok := baiduPanSessions.Load(key); ok {
			if state, valid := value.(baiduPanAuthState); valid {
				return state
			}
		}
	}
	return baiduPanAuthState{
		accessToken:  strings.TrimSpace(cfg.AccessKeyID),
		refreshToken: strings.TrimSpace(cfg.SecretAccessKey),
	}
}

func baiduPanClientForState(state baiduPanAuthState) *xpanclient.Client {
	return xpanclient.New(&xpanauth.AuthEnv{
		ClientId:     baiduPanClientID,
		ClientSecret: baiduPanClientSecret,
		AccessToken:  state.accessToken,
		RefreshToken: state.refreshToken,
	})
}

// baiduPanHTTPClientForConfig builds a per-account retry+proxy HTTP client.
// The proxy is resolved through ResolveProxyConfig so accounts with
// ProxyModeInherit fall back to the global proxy.
func baiduPanHTTPClientForConfig(cfg storageconfig.RemoteStorageConfig, state baiduPanAuthState) *baiduPanRetryHTTPClient {
	globalProxy, err := storageconfig.LoadGlobalProxy()
	if err == nil {
		cfg = storageconfig.ResolveProxyConfig(cfg, globalProxy)
	}
	creds := &xpantypes.Credentials{
		ClientId:     baiduPanClientID,
		ClientSecret: baiduPanClientSecret,
		AccessToken:  state.accessToken,
		RefreshToken: state.refreshToken,
	}
	return newBaiduPanRetryHTTPClientWithCreds(
		storageconfig.ProxyHTTPClient(cfg, 0),
		creds,
	)
}

func refreshBaiduPanStateLocked(
	current baiduPanAuthState,
) (baiduPanAuthState, error) {
	client := baiduPanClientForState(current)
	res, err := client.RefreshToken()
	if err != nil {
		return baiduPanAuthState{}, err
	}
	next := baiduPanAuthState{
		accessToken:  strings.TrimSpace(res.AccessToken),
		refreshToken: strings.TrimSpace(res.RefreshToken),
	}
	if next.refreshToken == "" {
		next.refreshToken = current.refreshToken
	}
	return next, nil
}

func rememberBaiduPanState(keys []string, state baiduPanAuthState) {
	for _, key := range keys {
		if strings.TrimSpace(key) == "" {
			continue
		}
		baiduPanSessions.Store(key, state)
	}
}

func baiduPanSessionKeys(
	cfg storageconfig.RemoteStorageConfig,
	state baiduPanAuthState,
) []string {
	keys := []string{
		"refresh:" + strings.TrimSpace(state.refreshToken),
		"access:" + strings.TrimSpace(state.accessToken),
		"profile:" + strings.TrimSpace(cfg.DisplayName) + "|" + strings.TrimSpace(cfg.Endpoint),
	}
	filtered := make([]string, 0, len(keys))
	for _, key := range keys {
		if strings.HasSuffix(key, ":") || strings.HasSuffix(key, "|") {
			continue
		}
		filtered = append(filtered, key)
	}
	return filtered
}

func persistBaiduPanState(
	cfg storageconfig.RemoteStorageConfig,
	state baiduPanAuthState,
) error {
	profiles, err := storageconfig.ListProfiles()
	if err != nil {
		return err
	}
	base := cfg.Normalized()
	for _, profile := range profiles {
		current, loadErr := storageconfig.LoadProfile(profile.Name)
		if loadErr != nil {
			return loadErr
		}
		current = current.Normalized()
		if !sameStoredBaiduPanProfile(current, base) {
			continue
		}
		current.AccessKeyID = state.accessToken
		current.SecretAccessKey = state.refreshToken
		current.HasSecretAccessKey = state.refreshToken != ""
		return storageconfig.SaveProfile(profile.Name, current)
	}
	return nil
}

func sameStoredBaiduPanProfile(
	current storageconfig.RemoteStorageConfig,
	base storageconfig.RemoteStorageConfig,
) bool {
	if current.StorageType != storageconfig.StorageTypeBaiduPan ||
		current.StorageType != base.StorageType ||
		current.DisplayName != base.DisplayName ||
		current.Endpoint != base.Endpoint {
		return false
	}
	accessMatches := base.AccessKeyID != "" && current.AccessKeyID == base.AccessKeyID
	refreshMatches := base.SecretAccessKey != "" &&
		current.SecretAccessKey == base.SecretAccessKey
	return accessMatches || refreshMatches
}

func shouldRefreshBaiduPanToken(err error) bool {
	if err == nil {
		return false
	}
	var apiErr xpantypes.Error
	if errors.As(err, &apiErr) {
		if strings.TrimSpace(apiErr.AuthError) != "" {
			return true
		}
		text := strings.ToLower(apiErr.Error())
		if strings.Contains(text, "token") || strings.Contains(text, "expired") {
			return true
		}
	}
	text := strings.ToLower(err.Error())
	return strings.Contains(text, "token") ||
		strings.Contains(text, "expired") ||
		strings.Contains(text, "invalid") ||
		strings.Contains(text, "用户未登录")
}
