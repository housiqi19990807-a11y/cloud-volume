// Shared CLI helpers keep bucket-targeted subcommands consistent.
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	storageconfig "remote-storage/go/config"
)

type bucketRequest struct {
	bucket    string
	mountPath string
}

type loadedConfig struct {
	path string
	cfg  storageconfig.RemoteStorageConfig
}

func parseBucketRequest(command string, args []string) (bucketRequest, error) {
	flags := newFlagSet(command)
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	mountPoint := flags.String("mount-point", "", "mount point path")
	if err := flags.Parse(args); err != nil {
		return bucketRequest{}, err
	}
	if remaining := flags.Args(); len(remaining) > 2 {
		return bucketRequest{}, fmt.Errorf("%s 只接受最多两个位置参数：bucket 和 mount point", command)
	} else {
		if strings.TrimSpace(*bucketName) == "" && len(remaining) >= 1 {
			*bucketName = remaining[0]
		}
		if strings.TrimSpace(*mountPoint) == "" && len(remaining) == 2 {
			*mountPoint = remaining[1]
		}
	}

	loaded, err := loadConfig(*configPath)
	if err != nil {
		return bucketRequest{}, err
	}

	bucket := strings.TrimSpace(*bucketName)
	if bucket == "" {
		if activeShell != nil && strings.TrimSpace(activeShell.bucketOverride) != "" {
			bucket = strings.TrimSpace(activeShell.bucketOverride)
		} else {
			bucket = strings.TrimSpace(loaded.cfg.Bucket)
		}
	}
	resolvedMountPath := strings.TrimSpace(*mountPoint)
	if bucket == "" && resolvedMountPath == "" {
		return bucketRequest{}, errors.New("缺少 bucket，请通过 --bucket 指定、传入 mount point，或先在 init 中保存默认 bucket")
	}
	return bucketRequest{
		bucket:    bucket,
		mountPath: resolvedMountPath,
	}, nil
}

func openConfigStore(explicitPath string) (storageconfig.Store, string, error) {
	if strings.TrimSpace(explicitPath) == "" && activeShell != nil && strings.TrimSpace(activeShell.configPath) != "" {
		explicitPath = activeShell.configPath
	}
	if strings.TrimSpace(explicitPath) != "" {
		path := strings.TrimSpace(explicitPath)
		return storageconfig.NewStore(path), path, nil
	}
	path, err := storageconfig.DefaultConfigPath()
	if err != nil {
		return storageconfig.Store{}, "", err
	}
	return storageconfig.NewStore(path), path, nil
}

func loadConfig(explicitPath string) (loadedConfig, error) {
	store, resolvedPath, err := openConfigStore(explicitPath)
	if err != nil {
		return loadedConfig{}, err
	}
	cfg, err := store.Load()
	if err != nil {
		return loadedConfig{}, err
	}
	return loadedConfig{
		path: resolvedPath,
		cfg:  cfg.Normalized(),
	}, nil
}

func loadConfiguredConfig(explicitPath string) (loadedConfig, error) {
	loaded, err := loadConfig(explicitPath)
	if err != nil {
		return loadedConfig{}, err
	}
	if !loaded.cfg.IsConfigured() {
		return loadedConfig{}, errors.New("当前还没有完整配置，请先运行 cloud-volume-cli init")
	}
	return loaded, nil
}

func stdoutWriter() io.Writer {
	return os.Stdout
}
