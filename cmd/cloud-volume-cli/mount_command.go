// The mount command owns Linux environment checks and the foreground wait loop.
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"strings"
	"syscall"
	"time"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	s3ops "remote-storage/go/s3"
)

const mountStatusPollInterval = time.Second

func runMountCommand(args []string) error {
	flags := newFlagSet("mount")
	configPath := flags.String("config", "", "config file path")
	bucketName := flags.String("bucket", "", "bucket name")
	mountPoint := flags.String("mount-point", "", "mount point path")
	skipValidate := flags.Bool("skip-validate", false, "skip bucket reachability validation")
	if err := flags.Parse(args); err != nil {
		return err
	}

	if err := applyMountPositionals(flags, bucketName, mountPoint); err != nil {
		return err
	}
	if err := ensureLinuxMountEnvironment(); err != nil {
		return err
	}

	store, _, err := openConfigStore(*configPath)
	if err != nil {
		return err
	}
	cfg, err := store.Load()
	if err != nil {
		return err
	}
	if !cfg.IsConfigured() {
		return errors.New("当前还没有完整配置，请先运行 cloud-volume-cli init")
	}

	bucket := strings.TrimSpace(*bucketName)
	if bucket == "" {
		bucket = strings.TrimSpace(cfg.Bucket)
	}
	if bucket == "" {
		return errors.New("缺少 bucket，请通过 --bucket 指定或先在 init 中保存默认 bucket")
	}

	if !*skipValidate {
		fmt.Println("正在校验 Bucket 可访问性...")
		if err := s3ops.CheckBucketAccess(cfg, bucket); err != nil {
			return fmt.Errorf("校验 bucket 失败: %w", err)
		}
	}

	status, err := bucketmount.MountBucketWithOptions(cfg, bucket, bucketmount.MountOptions{
		MountPath: strings.TrimSpace(*mountPoint),
	})
	if err != nil {
		return err
	}

	fmt.Printf("Bucket %s 已挂载到 %s\n", bucket, status.MountPath)
	fmt.Println("保持当前进程运行；按 Ctrl+C 可卸载并退出。")
	return waitForMountedBucket(bucket)
}

func applyMountPositionals(
	flags *flag.FlagSet,
	bucketName *string,
	mountPoint *string,
) error {
	args := flags.Args()
	if len(args) > 2 {
		return errors.New("mount 只接受最多两个位置参数：bucket 和 mount point")
	}
	if strings.TrimSpace(*bucketName) == "" && len(args) >= 1 {
		*bucketName = args[0]
	}
	if strings.TrimSpace(*mountPoint) == "" && len(args) == 2 {
		*mountPoint = args[1]
	}
	return nil
}

func ensureLinuxMountEnvironment() error {
	if runtime.GOOS != "linux" {
		return fmt.Errorf("mount 命令目前只支持 Linux，当前平台是 %s", runtime.GOOS)
	}
	if _, err := exec.LookPath("fusermount3"); err != nil {
		return errors.New("缺少 fusermount3，请先安装 fuse3")
	}
	info, err := os.Stat("/dev/fuse")
	if err != nil {
		return errors.New("缺少 /dev/fuse，请确认系统启用了 FUSE 内核设备")
	}
	if info.Mode()&os.ModeDevice == 0 {
		return errors.New("/dev/fuse 不可用，请确认 FUSE 设备节点正常")
	}
	return nil
}

func waitForMountedBucket(bucket string) error {
	signalCh := make(chan os.Signal, 1)
	signal.Notify(signalCh, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	defer signal.Stop(signalCh)

	ticker := time.NewTicker(mountStatusPollInterval)
	defer ticker.Stop()

	for {
		select {
		case sig := <-signalCh:
			fmt.Printf("收到信号 %s，开始卸载...\n", sig)
			_, err := bucketmount.UnmountBucket(bucket)
			return err
		case <-ticker.C:
			status, err := bucketmount.GetBucketMountStatus(bucket)
			if err != nil {
				return err
			}
			if !status.Mounted {
				fmt.Println("挂载已结束。")
				return nil
			}
		}
	}
}

func openConfigStore(explicitPath string) (storageconfig.Store, string, error) {
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
