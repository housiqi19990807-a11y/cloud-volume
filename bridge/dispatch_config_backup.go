// Configuration backup bridge handlers keep backup traffic out of profile management.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	storageconfig "remote-storage/go/config"
	configbackup "remote-storage/go/configbackup"
	bucketmount "remote-storage/go/mount"
)

var automaticConfigBackup struct {
	sync.Mutex
	pending bool
}

type configBackupSettingsArgs struct {
	Settings storageconfig.ConfigBackupSettings `json:"settings"`
}

type configBackupRestoreArgs struct {
	Key string `json:"key"`
}

func loadConfigBackupSettings() (any, error) {
	return storageconfig.LoadConfigBackupSettings()
}

func saveConfigBackupSettings(args json.RawMessage) (any, error) {
	var input configBackupSettingsArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	if err := storageconfig.SaveConfigBackupSettings(input.Settings); err != nil {
		return nil, err
	}
	return storageconfig.LoadConfigBackupSettings()
}

func backupConfigNow() (any, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	return configbackup.BackupNow(ctx)
}

func listConfigBackups() (any, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	return configbackup.List(ctx)
}

func restoreConfigBackup(args json.RawMessage) (any, error) {
	var input configBackupRestoreArgs
	if err := decodeArgs(args, &input); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	if err := bucketmount.CleanupMounts(); err != nil {
		return nil, fmt.Errorf("还原前卸载现有挂载失败：%w", err)
	}
	if err := configbackup.Restore(ctx, input.Key); err != nil {
		return nil, err
	}
	return loadBootstrapState()
}

// queueAutomaticConfigBackup never makes saving an account depend on remote availability.
func queueAutomaticConfigBackup() {
	automaticConfigBackup.Lock()
	if automaticConfigBackup.pending {
		automaticConfigBackup.Unlock()
		return
	}
	automaticConfigBackup.pending = true
	automaticConfigBackup.Unlock()
	go func() {
		defer func() {
			automaticConfigBackup.Lock()
			automaticConfigBackup.pending = false
			automaticConfigBackup.Unlock()
		}()
		// Coalesce the multiple writes made by a single settings edit.
		time.Sleep(2 * time.Second)
		settings, err := storageconfig.LoadConfigBackupSettings()
		if err != nil || !settings.Enabled {
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
		defer cancel()
		if _, err := configbackup.BackupNow(ctx); err != nil {
			log.Printf("[config-backup] automatic backup failed: %v", err)
		}
	}()
}
