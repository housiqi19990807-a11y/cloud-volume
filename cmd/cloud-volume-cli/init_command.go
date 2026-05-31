// The init command collects and optionally validates the persisted S3 config.
package main

import (
	"fmt"
	"strings"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

func runInitCommand(args []string) error {
	flags := newFlagSet("init")
	configPath := flags.String("config", "", "config file path")
	skipValidate := flags.Bool("skip-validate", false, "skip endpoint and credential validation")
	if err := flags.Parse(args); err != nil {
		return err
	}

	store, resolvedPath, err := openConfigStore(*configPath)
	if err != nil {
		return err
	}
	current, err := store.Load()
	if err != nil {
		return err
	}

	ui := newPromptUI()
	fmt.Fprintf(ui.out, "配置文件: %s\n", resolvedPath)
	fmt.Fprintln(ui.out, "请输入 S3 兼容存储配置。直接回车会保留当前值。")

	cfg := current
	if cfg == (storageconfig.RemoteStorageConfig{}) {
		cfg = storageconfig.DefaultConfig()
	}

	if cfg.Endpoint, err = ui.askString("Endpoint", cfg.Endpoint, true); err != nil {
		return err
	}
	if cfg.Region, err = ui.askString("Region", cfg.Region, false); err != nil {
		return err
	}
	if cfg.Bucket, err = ui.askString("默认 Bucket", cfg.Bucket, false); err != nil {
		return err
	}
	if cfg.AccessKeyID, err = ui.askString("Access Key ID", cfg.AccessKeyID, true); err != nil {
		return err
	}
	if cfg.SecretAccessKey, err = ui.askSecret("Secret Access Key", cfg.SecretAccessKey); err != nil {
		return err
	}
	if cfg.RootPrefix, err = ui.askString("Root Prefix", cfg.RootPrefix, false); err != nil {
		return err
	}
	if cfg.UsePathStyle, err = ui.askBool("启用 path-style URL", cfg.UsePathStyle); err != nil {
		return err
	}

	cfg = cfg.Normalized()
	if !*skipValidate {
		fmt.Fprintln(ui.out, "正在校验连接...")
		if err := s3ops.CheckBucketAccess(cfg, cfg.Bucket); err != nil {
			return fmt.Errorf("校验配置失败: %w", err)
		}
	}
	if err := store.Save(cfg); err != nil {
		return err
	}

	fmt.Fprintf(ui.out, "已保存配置到 %s\n", resolvedPath)
	if strings.TrimSpace(cfg.Bucket) != "" {
		fmt.Fprintf(ui.out, "默认 Bucket: %s\n", cfg.Bucket)
	}
	if activeShell != nil && strings.TrimSpace(cfg.Bucket) != "" {
		activeShell.bucketOverride = strings.TrimSpace(cfg.Bucket)
	}
	return nil
}
