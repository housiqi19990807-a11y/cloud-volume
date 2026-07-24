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

// backupEnvelope wraps AES-GCM encrypted backup data. The Marker field
// distinguishes encrypted envelopes from plaintext JSON backups — both are
// valid JSON so Version alone is ambiguous (ConfigBackupArchive also has a
// Version field that can be 1).
type backupEnvelope struct {
	Marker   bool   `json:"__enc__"`
	Version  int    `json:"version"`
	Nonce    string `json:"nonce"`
	Data     string `json:"data"`
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
	cfg, bucket, prefix, password, err := resolveTarget(settings)
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
	ciphertext, err := encrypt(password, payload)
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
	cfg, bucket, prefix, _, err := resolveTarget(settings)
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
	cfg, bucket, prefix, password, err := resolveTarget(settings)
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
	plain, err := decrypt(password, body)
	if err != nil {
		return fmt.Errorf("无法解密配置备份：%w", err)
	}
	var archive storageconfig.ConfigBackupArchive
	if err := json.Unmarshal(plain, &archive); err != nil {
		return fmt.Errorf("解析配置备份：%w", err)
	}
	return storageconfig.RestoreConfigBackup(archive)
}

// Delete removes a single backup snapshot from the configured remote target.
func Delete(ctx context.Context, key string) error {
	settings, err := storageconfig.LoadConfigBackupSettings()
	if err != nil {
		return err
	}
	cfg, bucket, prefix, _, err := resolveTarget(settings)
	if err != nil {
		return err
	}
	cleanKey := strings.Trim(strings.TrimSpace(key), "/")
	if !strings.HasPrefix(cleanKey, ensurePrefix(prefix)) || !strings.HasSuffix(cleanKey, backupFileSuffix) {
		return fmt.Errorf("无效的配置备份文件")
	}
	return storageops.ForConfig(cfg).DeleteObject(ctx, bucket, cleanKey, false, "")
}

func resolveTarget(settings storageconfig.ConfigBackupSettings) (storageconfig.RemoteStorageConfig, string, string, string, error) {
	target := settings.Target
	var cfg storageconfig.RemoteStorageConfig
	var err error
	if target.ProfileName != "" {
		cfg, err = storageconfig.LoadProfile(target.ProfileName)
		if err != nil {
			return cfg, "", "", "", fmt.Errorf("读取备份账号：%w", err)
		}
	} else {
		if target.Standalone == nil {
			return cfg, "", "", "", fmt.Errorf("请先完成配置备份存储")
		}
		cfg = *target.Standalone
	}
	cfg = cfg.Normalized().WithDefaultWebDAVCredentials()
	if !cfg.IsConfigured() || strings.TrimSpace(target.Bucket) == "" {
		return cfg, "", "", "", fmt.Errorf("请先完成配置备份存储")
	}
	// Password is optional — empty means plaintext (unencrypted) backups.
	password := strings.TrimSpace(target.BackupPassword)
	return cfg, strings.TrimSpace(target.Bucket), strings.Trim(strings.TrimSpace(target.Prefix), "/"), password, nil
}

func ensurePrefix(prefix string) string {
	clean := strings.Trim(prefix, "/")
	if clean == "" {
		return ""
	}
	return clean + "/"
}

// encryptionKey returns nil when no password is set, signalling that the
// backup should be stored as plaintext JSON.
func encryptionKey(password string) ([]byte, error) {
	if strings.TrimSpace(password) == "" {
		return nil, nil
	}
	// Derive a stable AES-256 key from the user's passphrase only — not from
	// connection credentials — so the same password decrypts backups across
	// machines regardless of endpoint or OAuth token differences.
	sum := sha256.Sum256([]byte("cloud-volume/config-backup/v2\x00" + password))
	return sum[:], nil
}

// encrypt returns the AES-GCM envelope when a password is set, or the
// plaintext payload directly when no password is configured.
func encrypt(password string, plain []byte) ([]byte, error) {
	key, err := encryptionKey(password)
	if err != nil {
		return nil, err
	}
	if key == nil {
		// No password: store as plaintext JSON (no encryption).
		return plain, nil
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
	envelope, err := json.Marshal(backupEnvelope{Marker: true, Version: 1, Nonce: base64.RawStdEncoding.EncodeToString(nonce), Data: base64.RawStdEncoding.EncodeToString(gcm.Seal(nil, nonce, plain, nil))})
	return envelope, err
}

// decrypt unwraps the AES-GCM envelope when a password is set, or returns
// the payload directly if it is plaintext JSON (no password / v0 backups).
func decrypt(password string, payload []byte) ([]byte, error) {
	key, err := encryptionKey(password)
	if err != nil {
		return nil, err
	}
	// If the payload does not carry the encryption marker, treat it as
	// plaintext JSON (unencrypted mode). We cannot rely on Version==1 alone
	// because ConfigBackupArchive also uses Version: 1.
	var envelope backupEnvelope
	if jsonErr := json.Unmarshal(payload, &envelope); jsonErr != nil || !envelope.Marker {
		return payload, nil
	}
	if key == nil {
		// Envelope exists but no password configured — cannot decrypt.
		return nil, fmt.Errorf("此备份已加密，请先设置加密密码")
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
