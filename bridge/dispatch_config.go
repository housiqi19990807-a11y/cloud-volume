package main

import (
	"encoding/json"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

// Config, profile and cache bridge handlers. Split from dispatch.go so each
// bridge file stays under the repository 500-line ceiling.

type saveConfigArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

type profileArgs struct {
	Name   string                            `json:"name"`
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

type profileNameArgs struct {
	Name string `json:"name"`
}

type updateProxySettingsArgs struct {
	ProxyMode     string `json:"proxyMode"`
	ProxyType     string `json:"proxyType"`
	ProxyHost     string `json:"proxyHost"`
	ProxyPort     string `json:"proxyPort"`
	ProxyUsername string `json:"proxyUsername"`
	ProxyPassword string `json:"proxyPassword"`
}

func loadBootstrapState() (storageconfig.BootstrapState, error) {
	// Auto-migrate legacy config to profiles dir.
	_ = storageconfig.MigrateDefault()

	profiles, _ := storageconfig.ListProfiles()
	configured := len(profiles) > 0

	var config storageconfig.RemoteStorageConfig
	if configured {
		activeName := profiles[0].Name
		for _, profile := range profiles {
			if profile.Active {
				activeName = profile.Name
				break
			}
		}
		config, _ = storageconfig.LoadProfile(activeName)
	} else {
		config = storageconfig.DefaultConfig()
	}
	publicConfig, err := config.WithResolvedCacheDirectory()
	if err != nil {
		return storageconfig.BootstrapState{}, err
	}
	globalProxy, err := storageconfig.LoadGlobalProxy()
	if err == nil {
		publicConfig.ProxyMode = globalProxy.ProxyMode
		publicConfig.ProxyType = globalProxy.ProxyType
		publicConfig.ProxyHost = globalProxy.ProxyHost
		publicConfig.ProxyPort = globalProxy.ProxyPort
		publicConfig.ProxyUsername = globalProxy.ProxyUsername
		publicConfig.ProxyPassword = globalProxy.ProxyPassword
	}

	return storageconfig.BootstrapState{
		ConfigPath: "bbolt",
		Configured: config.IsConfigured(),
		Config:     publicConfig,
		Profiles:   profiles,
	}, nil
}

func migrateAndBootstrap() (storageconfig.BootstrapState, error) {
	_ = storageconfig.MigrateDefault()
	return loadBootstrapState()
}

func saveConfig(args json.RawMessage) (storageconfig.BootstrapState, error) {
	var input saveConfigArgs
	if err := decodeArgs(args, &input); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	// Apply proxy settings to the Baidu Pan SDK before any network calls.
	storageops.ApplyBaiduPanProxy(input.Config)
	// Save to "default" profile.
	if err := storageconfig.SaveProfileWithValidation("default", input.Config); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	_ = storageconfig.SetActiveProfile("default")
	return loadBootstrapState()
}

// updateProxySettings saves the global proxy independently from account
// profiles. Accounts with ProxyMode "inherit" automatically use these values;
// explicit account modes (system/direct/custom) are unaffected.
func updateProxySettings(args json.RawMessage) (bool, error) {
	var input updateProxySettingsArgs
	if err := decodeArgs(args, &input); err != nil {
		return false, err
	}
	cfg := storageconfig.RemoteStorageConfig{
		ProxyMode:     input.ProxyMode,
		ProxyType:     input.ProxyType,
		ProxyHost:     input.ProxyHost,
		ProxyPort:     input.ProxyPort,
		ProxyUsername: input.ProxyUsername,
		ProxyPassword: input.ProxyPassword,
	}
	if err := storageconfig.SaveGlobalProxy(cfg); err != nil {
		return false, err
	}
	// Apply the global proxy to the Baidu Pan SDK fallback client. Per-account
	// clients are built independently by baiduPanHTTPClientForConfig.
	globalCfg, err := storageconfig.LoadGlobalProxy()
	if err != nil {
		return false, err
	}
	storageops.ApplyBaiduPanProxy(globalCfg)
	return true, nil
}

// --- Profile management ---

func listProfiles() (any, error) {
	_ = storageconfig.MigrateDefault()
	return storageconfig.ListProfiles()
}

func loadProfile(args json.RawMessage) (any, error) {
	var input profileNameArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	config, err := storageconfig.LoadProfile(input.Name)
	if err != nil {
		return nil, err
	}
	return config.WithResolvedCacheDirectory()
}

func saveProfile(args json.RawMessage) (any, error) {
	var input profileArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.SaveProfile(input.Name, input.Config); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

func deleteProfile(args json.RawMessage) (any, error) {
	var input profileNameArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.DeleteProfile(input.Name); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

// resetUserConfig wipes every stored account plus legacy default config
// sources so the desktop shell returns to the first-run setup flow.
func resetUserConfig(args json.RawMessage) (any, error) {
	var input struct {
		Confirm bool `json:"confirm"`
	}
	// The payload is informational today, but keep decodeArgs so a future
	// confirmation token can be validated without changing the contract.
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.ResetAllProfiles(); err != nil {
		return nil, err
	}
	return loadBootstrapState()
}

func setActiveProfile(args json.RawMessage) (any, error) {
	var input profileNameArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.SetActiveProfile(input.Name); err != nil {
		return nil, err
	}
	return loadBootstrapState()
}

// --- Cache directory maintenance ---

// getCacheStats reports the resolved cache directory size for the settings card.
func getCacheStats(args json.RawMessage) (any, error) {
	var input bucketArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageconfig.GetCacheStats(input.Config)
}

// openCacheDirectory reveals the resolved cache directory in the desktop shell.
func openCacheDirectory(args json.RawMessage) (any, error) {
	var input bucketArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.OpenCacheDirectory(input.Config); err != nil {
		return nil, err
	}
	return map[string]any{"ok": true}, nil
}

// cleanCache runs either a full wipe or a rules-based eviction pass.
func cleanCache(args json.RawMessage) (any, error) {
	var input struct {
		Config   storageconfig.RemoteStorageConfig `json:"config"`
		ClearAll bool                              `json:"clearAll"`
	}
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	return storageconfig.CleanCache(input.Config, storageconfig.CleanCacheRequest{
		ClearAll: input.ClearAll,
	})
}
