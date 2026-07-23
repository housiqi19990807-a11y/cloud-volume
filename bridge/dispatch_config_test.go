// Config dispatch tests keep credential checks side-effect free before save.
package main

import (
	"encoding/json"
	"strings"
	"testing"

	storageconfig "remote-storage/go/config"
)

func TestValidateAccountCredentialsRejectsIncompleteConfig(t *testing.T) {
	payload, err := json.Marshal(saveConfigArgs{Config: storageconfig.RemoteStorageConfig{}})
	if err != nil {
		t.Fatalf("marshal credential payload: %v", err)
	}

	_, err = validateAccountCredentials(payload)
	if err == nil || !strings.Contains(err.Error(), "补全账号连接信息") {
		t.Fatalf("validateAccountCredentials error = %v, want incomplete-config error", err)
	}
}
