// Baidu Pan bridge methods keep the desktop OAuth loop inside the Go layer.
package main

import (
	"encoding/json"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

type baiduPanAuthorizeArgs struct {
	DisplayName string `json:"displayName"`
}

func authorizeBaiduPan(args json.RawMessage) (any, error) {
	var input baiduPanAuthorizeArgs
	if len(args) > 0 {
		if err := decodeArgs(args, &input); err != nil {
			return nil, err
		}
	}
	config, err := storageops.AuthorizeBaiduPan(input.DisplayName)
	if err != nil {
		return nil, err
	}
	publicConfig, err := config.WithResolvedCacheDirectory()
	if err != nil {
		return storageconfig.RemoteStorageConfig{}, err
	}
	return publicConfig, nil
}
