// Package configbackup stores encrypted, restorable account snapshots in a user-selected remote store.
package configbackup

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"path"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"

	storageconfig "remote-storage/go/config"
	storageops "remote-storage/go/storage"
)

const backupFileSuffix = ".cloud-volume-config.json.enc"

type backupEnvelope struct {
	Version int    `json:"version"`
	Nonce   string `json:"nonce"`
	Data    string `json:"data"`
}

type Snapshot struct {
	Key         string `json:"key"`
	CreatedAt   string `json:"createdAt"`
	Size        int64  `json:"size"`
	DisplayName string `json:"displayName"`
}

// BackupNow serializes the current account configuration and uploads an encrypted snapshot.
func BackupNow(ctx context.Context) (Snapshot, error) {
	settings, err := storageconfig.LoadConfigBackupSettings()
	if err != nil {
		return Snapshot{}, err
	}
	cfg, bucket, prefix, err := resolveTarget(settings)
	if err != nil {
		return Snapshot{}, err
	}
	archive, err := storageconfig.ExportConfigBackup()
	if err != nil {
		return Snapshot{}, err
	}
	payload, err := json.Marshal(archive)
	if err != nil {
		return Snapshot{}, err
	}
	ciphertext, err := encrypt(cfg, payload)
	if err != nil {
		return Snapshot{}, err
	}
	now := time.Now().UTC()
	name := fmt.Sprintf("config-%s-%s%s", now.Format("20060102T150405Z"), uuid.NewString(), backupFileSuffix)
	key := path.Join(prefix, name)
	if err := storageops.ForConfig(cfg).UploadReader(ctx, bucket, key, bytes.NewReader(ciphertext), int64(len(ciphertext)), "", name); err != nil {
		return Snapshot{}, err
	}
	return Snapshot{Key: key, CreatedAt: now.Format(time.RFC3339), Size: int64(len(ciphertext)), DisplayName: name}, nil
}

// List returns newest-first configuration snapshots at the configured target.
func List(ctx context.Context) ([]Snapshot, error) {
	settings, err := storageconfig.LoadConfigBackupSettings()
	if err != nil {
		return nil, err
	}
	cfg, bucket, prefix, err := resolveTarget(settings)
	if err != nil {
		return nil, err
	}
	page, err := storageops.ForConfig(cfg).ListObjectsPage(ctx, bucket, ensurePrefix(prefix), "", 1000)
	if err != nil {
		return nil, err
	}
	items := make([]Snapshot, 0, len(page.Items))
	for _, item := range page.Items {
		if item.IsDir || !strings.HasSuffix(item.Key, backupFileSuffix) {
			continue
		}
		items = append(items, Snapshot{Key: item.Key, CreatedAt: item.LastModified, Size: item.Size, DisplayName: path.Base(item.Key)})
	}
	sort.Slice(items, func(i, j int) bool { return items[i].Key > items[j].Key })
	return items, nil
}

// Restore downloads, authenticates, and applies one snapshot. The backup target remains configured locally.
func Restore(ctx context.Context, key string) error {
	settings, err := storageconfig.LoadConfigBackupSettings()
	if err != nil {
		return err
	}
	cfg, bucket, prefix, err := resolveTarget(settings)
	if err != nil {
		return err
	}
	cleanKey := strings.Trim(strings.TrimSpace(key), "/")
	if !strings.HasPrefix(cleanKey, ensurePrefix(prefix)) || !strings.HasSuffix(cleanKey, backupFileSuffix) {
		return fmt.Errorf("无效的配置备份文件")
	}
	info, err := storageops.ForConfig(cfg).HeadObject(ctx, bucket, cleanKey)
	if err != nil {
		return err
	}
	if info.Size <= 0 || info.Size > 32<<20 {
		return fmt.Errorf("配置备份文件大小异常")
	}
	body, err := storageops.ForConfig(cfg).ReadObjectRange(ctx, bucket, cleanKey, 0, info.Size)
	if err != nil {
		return err
	}
	plain, err := decrypt(cfg, body)
	if err != nil {
		return fmt.Errorf("无法解密配置备份：%w", err)
	}
	var archive storageconfig.ConfigBackupArchive
	if err := json.Unmarshal(plain, &archive); err != nil {
		return fmt.Errorf("解析配置备份：%w", err)
	}
	return storageconfig.RestoreConfigBackup(archive)
}

func resolveTarget(settings storageconfig.ConfigBackupSettings) (storageconfig.RemoteStorageConfig, string, string, error) {
	target := settings.Target
	var cfg storageconfig.RemoteStorageConfig
	var err error
	if target.ProfileName != "" {
		cfg, err = storageconfig.LoadProfile(target.ProfileName)
		if err != nil {
			return cfg, "", "", fmt.Errorf("读取备份账号：%w", err)
		}
	} else {
		if target.Standalone == nil {
			return cfg, "", "", fmt.Errorf("请先完成配置备份存储")
		}
		cfg = *target.Standalone
	}
	cfg = cfg.Normalized().WithDefaultWebDAVCredentials()
	if !cfg.IsConfigured() || strings.TrimSpace(target.Bucket) == "" {
		return cfg, "", "", fmt.Errorf("请先完成配置备份存储")
	}
	if _, err := encryptionKey(cfg); err != nil {
		return cfg, "", "", err
	}
	return cfg, strings.TrimSpace(target.Bucket), strings.Trim(strings.TrimSpace(target.Prefix), "/"), nil
}

func ensurePrefix(prefix string) string {
	clean := strings.Trim(prefix, "/")
	if clean == "" {
		return ""
	}
	return clean + "/"
}

func encryptionKey(cfg storageconfig.RemoteStorageConfig) ([]byte, error) {
	secret := strings.Join([]string{cfg.StorageType, cfg.Endpoint, cfg.AccessKeyID, cfg.SecretAccessKey, cfg.WebDAVUsername, cfg.WebDAVPassword, cfg.FTPUsername, cfg.FTPPassword}, "\x00")
	if strings.TrimSpace(strings.ReplaceAll(secret, "\x00", "")) == "" || (cfg.SecretAccessKey == "" && cfg.WebDAVPassword == "" && cfg.FTPPassword == "") {
		return nil, fmt.Errorf("备份存储必须使用带密钥或密码的账号")
	}
	sum := sha256.Sum256([]byte("cloud-volume/config-backup/v1\x00" + secret))
	return sum[:], nil
}

func encrypt(cfg storageconfig.RemoteStorageConfig, plain []byte) ([]byte, error) {
	key, err := encryptionKey(cfg)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return nil, err
	}
	envelope, err := json.Marshal(backupEnvelope{Version: 1, Nonce: base64.RawStdEncoding.EncodeToString(nonce), Data: base64.RawStdEncoding.EncodeToString(gcm.Seal(nil, nonce, plain, nil))})
	return envelope, err
}

func decrypt(cfg storageconfig.RemoteStorageConfig, payload []byte) ([]byte, error) {
	key, err := encryptionKey(cfg)
	if err != nil {
		return nil, err
	}
	var envelope backupEnvelope
	if err := json.Unmarshal(payload, &envelope); err != nil || envelope.Version != 1 {
		return nil, fmt.Errorf("不支持的备份格式")
	}
	nonce, err := base64.RawStdEncoding.DecodeString(envelope.Nonce)
	if err != nil {
		return nil, err
	}
	ciphertext, err := base64.RawStdEncoding.DecodeString(envelope.Data)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	return gcm.Open(nil, nonce, ciphertext, nil)
}
