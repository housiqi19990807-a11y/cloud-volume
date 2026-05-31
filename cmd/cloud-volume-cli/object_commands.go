// Object commands reuse the shared S3 layer for upload, download, and one-level listings.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"text/tabwriter"

	s3ops "remote-storage/go/s3"
)

type objectTarget struct {
	config     loadedConfig
	bucket     string
	visibleKey string
	remoteKey  string
}

func runPutCommand(args []string) error {
	flags := newFlagSet("put")
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	if err := flags.Parse(args); err != nil {
		return err
	}
	remaining := flags.Args()
	if len(remaining) < 1 || len(remaining) > 2 {
		return errors.New("put 用法: cloud-volume-cli put [--bucket name] <local-path> [remote-path]")
	}

	target, err := resolveObjectTarget(*configPath, *bucketName, "")
	if err != nil {
		return err
	}
	localPath := strings.TrimSpace(remaining[0])
	if localPath == "" {
		return errors.New("local path 不能为空")
	}
	if err := ensureLocalSourceExists(localPath); err != nil {
		return err
	}
	remotePath := ""
	if len(remaining) == 2 {
		remotePath = remaining[1]
	} else {
		remotePath = resolveVisiblePath(currentShellDir(), defaultRemoteObjectPath(localPath))
	}
	if strings.TrimSpace(remotePath) == "" {
		return errors.New("remote path 不能为空")
	}

	target.visibleKey = resolveVisiblePath(currentShellDir(), remotePath)
	target.remoteKey = applyRootPrefix(target.config.cfg.RootPrefix, target.visibleKey, false)
	if target.remoteKey == "" {
		return errors.New("remote path 不能为空")
	}

	if err := s3ops.UploadFile(target.config.cfg, target.bucket, target.remoteKey, localPath, ""); err != nil {
		return err
	}
	fmt.Fprintf(stdoutWriter(), "uploaded %s -> s3://%s/%s\n", localPath, target.bucket, target.visibleKey)
	return nil
}

func runGetCommand(args []string) error {
	flags := newFlagSet("get")
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	if err := flags.Parse(args); err != nil {
		return err
	}
	remaining := flags.Args()
	if len(remaining) < 1 || len(remaining) > 2 {
		return errors.New("get 用法: cloud-volume-cli get [--bucket name] <remote-path> [local-path]")
	}

	target, err := resolveObjectTarget(*configPath, *bucketName, resolveVisiblePath(currentShellDir(), remaining[0]))
	if err != nil {
		return err
	}
	localPath := ""
	if len(remaining) == 2 {
		localPath = strings.TrimSpace(remaining[1])
	} else {
		localPath = defaultDownloadPath(target.visibleKey)
	}
	if localPath == "" {
		return errors.New("local path 不能为空")
	}

	if err := s3ops.DownloadFile(target.config.cfg, target.bucket, target.remoteKey, localPath, ""); err != nil {
		return err
	}
	fmt.Fprintf(stdoutWriter(), "downloaded s3://%s/%s -> %s\n", target.bucket, target.visibleKey, localPath)
	return nil
}

func runListCommand(args []string) error {
	flags := newFlagSet("ls")
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	jsonOutput := flags.Bool("json", false, "print JSON output")
	if err := flags.Parse(args); err != nil {
		return err
	}
	remaining := flags.Args()
	if len(remaining) > 1 {
		return errors.New("ls/list 只接受一个可选 prefix 位置参数")
	}

	prefix := ""
	if len(remaining) == 1 {
		prefix = resolveVisiblePath(currentShellDir(), remaining[0])
	} else {
		prefix = currentShellDir()
	}
	target, err := resolveObjectTarget(*configPath, *bucketName, prefix)
	if err != nil {
		return err
	}

	items, err := s3ops.ListObjects(target.config.cfg, target.bucket, applyRootPrefix(
		target.config.cfg.RootPrefix,
		target.visibleKey,
		true,
	))
	if err != nil {
		return err
	}

	visibleItems := make([]s3ops.ObjectInfo, 0, len(items))
	for _, item := range items {
		visible, ok := stripRootPrefix(target.config.cfg.RootPrefix, item.Key, item.IsDir)
		if !ok {
			continue
		}
		item.Key = relativeListedPath(target.visibleKey, visible, item.IsDir)
		visibleItems = append(visibleItems, item)
	}

	if *jsonOutput {
		encoder := json.NewEncoder(stdoutWriter())
		encoder.SetIndent("", "  ")
		return encoder.Encode(visibleItems)
	}
	return printListTable(visibleItems)
}

func resolveObjectTarget(configPath, bucketName, visiblePath string) (objectTarget, error) {
	loaded, err := loadConfiguredConfig(configPath)
	if err != nil {
		return objectTarget{}, err
	}
	bucket := strings.TrimSpace(bucketName)
	if bucket == "" {
		if activeShell != nil && strings.TrimSpace(activeShell.bucketOverride) != "" {
			bucket = strings.TrimSpace(activeShell.bucketOverride)
		} else {
			bucket = strings.TrimSpace(loaded.cfg.Bucket)
		}
	}
	if bucket == "" {
		return objectTarget{}, errors.New("缺少 bucket，请通过 --bucket 指定、在 shell 里设置 bucket，或先在 init 中保存默认 bucket")
	}

	cleanVisible := cleanObjectPath(visiblePath)
	return objectTarget{
		config:     loaded,
		bucket:     bucket,
		visibleKey: cleanVisible,
		remoteKey:  applyRootPrefix(loaded.cfg.RootPrefix, cleanVisible, false),
	}, nil
}

func printListTable(items []s3ops.ObjectInfo) error {
	writer := tabwriter.NewWriter(stdoutWriter(), 0, 4, 2, ' ', 0)
	if _, err := fmt.Fprintln(writer, "TYPE\tSIZE\tUPDATED\tPATH"); err != nil {
		return err
	}
	for _, item := range items {
		size := "-"
		if !item.IsDir {
			size = fmt.Sprintf("%d", item.Size)
		}
		itemType := "FILE"
		if item.IsDir {
			itemType = "DIR"
		}
		if _, err := fmt.Fprintf(
			writer,
			"%s\t%s\t%s\t%s\n",
			itemType,
			size,
			strings.TrimSpace(item.LastModified),
			item.Key,
		); err != nil {
			return err
		}
	}
	return writer.Flush()
}

func ensureLocalSourceExists(localPath string) error {
	info, err := os.Stat(localPath)
	if err != nil {
		return err
	}
	if info.IsDir() {
		return fmt.Errorf("暂不支持目录 put: %s", localPath)
	}
	return nil
}
