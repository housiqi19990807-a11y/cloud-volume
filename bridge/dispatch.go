package main

import (
	"encoding/json"
	"fmt"

	storageconfig "remote-storage/go/config"
)

type saveConfigArgs struct {
	Config storageconfig.RemoteStorageConfig `json:"config"`
}

// invokeBridgeMethod translates JSON RPC-like method names into typed Go operations.
func invokeBridgeMethod(method string, args json.RawMessage) (any, error) {
	switch method {
	case "load_bootstrap_state":
		return loadBootstrapState()
	case "save_config":
		return saveConfig(args)
	default:
		return nil, fmt.Errorf("unsupported bridge method %q", method)
	}
}

func loadBootstrapState() (storageconfig.BootstrapState, error) {
	store, err := storageconfig.NewDefaultStore()
	if err != nil {
		return storageconfig.BootstrapState{}, err
	}
	return store.LoadBootstrapState()
}

func saveConfig(args json.RawMessage) (storageconfig.BootstrapState, error) {
	store, err := storageconfig.NewDefaultStore()
	if err != nil {
		return storageconfig.BootstrapState{}, err
	}

	var input saveConfigArgs
	if err := decodeArgs(args, &input); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	if err := store.Save(input.Config); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	return store.LoadBootstrapState()
}
