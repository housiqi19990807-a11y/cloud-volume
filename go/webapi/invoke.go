// Invoke endpoints mirror bridge method names while sourcing config from the server.
package webapi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	storageconfig "remote-storage/go/config"
	bucketmount "remote-storage/go/mount"
	s3ops "remote-storage/go/s3"
	shareops "remote-storage/go/share"
)

type invokeEnvelope struct {
	Config      storageconfig.RemoteStorageConfig `json:"config"`
	Name        string                            `json:"name"`
	Bucket      string                            `json:"bucket"`
	Prefix      string                            `json:"prefix"`
	NextToken   string                            `json:"nextToken"`
	PageSize    int32                             `json:"pageSize"`
	Key         string                            `json:"key"`
	IsDirectory bool                              `json:"isDirectory"`
	NewName     string                            `json:"newName"`
	SourceKey   string                            `json:"sourceKey"`
	TargetKey   string                            `json:"targetKey"`
	TaskID      string                            `json:"taskId"`
	TrashID     string                            `json:"trashId"`
	DurationSec int                               `json:"durationSec"`
	ID          string                            `json:"id"`
}

func (s *Server) handleInvoke(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeError(w, http.StatusMethodNotAllowed, fmt.Errorf("method not allowed"))
		return
	}
	method := strings.TrimPrefix(r.URL.Path, "/api/invoke/")
	method = strings.TrimSpace(method)
	if method == "" {
		writeError(w, http.StatusNotFound, fmt.Errorf("missing method"))
		return
	}

	var input invokeEnvelope
	if err := decodeBody(r.Body, &input); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if method == "save_config" {
		currentConfig, err := loadCurrentConfig()
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if isWebConfigured(currentConfig) && !s.authenticated(r) {
			writeError(w, http.StatusUnauthorized, fmt.Errorf("login required"))
			return
		}
	}
	if method != "load_bootstrap_state" &&
		method != "save_config" &&
		!s.authenticated(r) {
		writeError(w, http.StatusUnauthorized, fmt.Errorf("login required"))
		return
	}
	result, status, err := s.invokeMethod(r.Context(), method, input)
	if err != nil {
		writeError(w, status, err)
		return
	}
	if method == "save_config" && input.Config.HasWebDAVCredentials() {
		if err := s.establishSession(w, r); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
	}
	writeSuccess(w, result)
}

func (s *Server) invokeMethod(
	ctx context.Context,
	method string,
	input invokeEnvelope,
) (any, int, error) {
	switch method {
	case "load_bootstrap_state":
		state, err := loadBootstrapState()
		return state, http.StatusOK, err
	case "save_config":
		state, err := s.saveConfig(input.Config)
		return state, http.StatusOK, err
	case "list_profiles":
		profiles, err := storageconfig.ListProfiles()
		return profiles, http.StatusOK, err
	case "load_profile":
		if strings.TrimSpace(input.Name) == "" {
			return nil, http.StatusBadRequest, fmt.Errorf("missing profile name")
		}
		config, err := storageconfig.LoadProfile(input.Name)
		if err != nil {
			return nil, http.StatusInternalServerError, err
		}
		return config.PublicSanitized(), http.StatusOK, nil
	}
	config, err := requireConfiguredStorage()
	if err != nil {
		return nil, http.StatusBadRequest, err
	}

	switch method {
	case "list_buckets":
		result, err := s3ops.ListBuckets(config)
		return result, http.StatusOK, err
	case "list_object_page":
		if page, handled, err := bucketmount.ListMountedObjectPage(
			config,
			input.Bucket,
			input.Prefix,
			input.NextToken,
			input.PageSize,
		); handled || err != nil {
			return page, http.StatusOK, err
		}
		result, err := s3ops.ListObjectsPage(
			config,
			input.Bucket,
			input.Prefix,
			input.NextToken,
			input.PageSize,
		)
		return result, http.StatusOK, err
	case "head_object":
		result, err := s3ops.HeadObject(config, input.Bucket, input.Key)
		return result, http.StatusOK, err
	case "create_directory":
		err := s3ops.CreateDirectory(config, input.Bucket, input.Prefix, input.Name)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "delete_object":
		err := s3ops.DeleteObjectContextWithTask(
			ctx,
			config,
			input.Bucket,
			input.Key,
			input.IsDirectory,
			input.TaskID,
		)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "rename_object":
		err := s3ops.RenameObject(
			config,
			input.Bucket,
			input.Key,
			input.IsDirectory,
			input.NewName,
		)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "copy_object":
		err := s3ops.CopyObject(
			config,
			input.Bucket,
			input.SourceKey,
			input.TargetKey,
			input.IsDirectory,
			input.TaskID,
		)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "move_object":
		err := s3ops.MoveObjectWithTask(
			config,
			input.Bucket,
			input.SourceKey,
			input.TargetKey,
			input.IsDirectory,
			input.TaskID,
		)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "list_trash_page":
		result, err := s3ops.ListTrashPage(
			config,
			input.Bucket,
			input.NextToken,
			input.PageSize,
		)
		return result, http.StatusOK, err
	case "restore_trash_item":
		err := s3ops.RestoreTrashItem(config, input.Bucket, input.TrashID)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "delete_trash_item":
		err := s3ops.DeleteTrashItem(config, input.Bucket, input.TrashID)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "create_share":
		result, err := shareops.Create(
			config,
			input.Bucket,
			input.Key,
			input.Name,
			input.DurationSec,
		)
		return result, http.StatusOK, err
	case "list_shares":
		result, err := shareops.List(config)
		return result, http.StatusOK, err
	case "refresh_share":
		result, err := shareops.Refresh(config, input.ID, input.DurationSec)
		return result, http.StatusOK, err
	case "delete_share":
		err := shareops.Delete(config, input.ID)
		return map[string]any{"ok": true}, http.StatusOK, err
	case "list_transfer_jobs":
		return s3ops.ListTransferSnapshots(), http.StatusOK, nil
	case "cancel_transfer":
		if bucketmount.CancelQueuedTransfer(input.TaskID) {
			return map[string]any{"ok": true}, http.StatusOK, nil
		}
		return map[string]any{"ok": s3ops.CancelTransfer(input.TaskID)}, http.StatusOK, nil
	case "trigger_transfer":
		return map[string]any{"ok": bucketmount.TriggerQueuedTransfer(input.TaskID)}, http.StatusOK, nil
	case "mount_bucket":
		return bucketmount.BucketMountStatus{
			Mounted:   true,
			Bucket:    strings.TrimSpace(input.Bucket),
			MountPath: "",
			ServerURL: "/webdav/" + strings.Trim(strings.TrimSpace(input.Bucket), "/") + "/",
			Port:      0,
		}, http.StatusOK, nil
	case "get_bucket_mount_status", "open_bucket_mount":
		return bucketmount.BucketMountStatus{
			Mounted:   true,
			Bucket:    strings.TrimSpace(input.Bucket),
			MountPath: "",
			ServerURL: "/webdav/" + strings.Trim(strings.TrimSpace(input.Bucket), "/") + "/",
			Port:      0,
		}, http.StatusOK, nil
	case "unmount_bucket":
		return bucketmount.BucketMountStatus{
			Mounted:   false,
			Bucket:    strings.TrimSpace(input.Bucket),
			MountPath: "",
			ServerURL: "/webdav/" + strings.Trim(strings.TrimSpace(input.Bucket), "/") + "/",
			Port:      0,
		}, http.StatusOK, nil
	case "cleanup_mounts":
		return map[string]any{"ok": true}, http.StatusOK, s.webdav.Reset()
	case "cleanup_stale_windows_processes":
		return map[string]any{"ok": true, "count": 0}, http.StatusOK, nil
	default:
		return nil, http.StatusNotFound, fmt.Errorf("unsupported bridge method %q", method)
	}
}

func (s *Server) saveConfig(
	config storageconfig.RemoteStorageConfig,
) (storageconfig.BootstrapState, error) {
	if err := storageconfig.SaveProfile("default", config); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	s.sessions.Reset()
	if err := s.webdav.Reset(); err != nil {
		return storageconfig.BootstrapState{}, err
	}
	return loadBootstrapState()
}

func (s *Server) establishSession(
	w http.ResponseWriter,
	r *http.Request,
) error {
	s.sessions.Delete(s.sessionToken(r))
	token, expiresAt, err := s.sessions.Create()
	if err != nil {
		return err
	}
	s.setSessionCookie(w, r, token, expiresAt)
	return nil
}

func decodeBody(body io.ReadCloser, target any) error {
	defer body.Close()
	raw, err := io.ReadAll(body)
	if err != nil {
		return err
	}
	trimmed := strings.TrimSpace(string(raw))
	if trimmed == "" || trimmed == "null" {
		return nil
	}
	if err := json.Unmarshal(raw, target); err != nil {
		return fmt.Errorf("invalid request payload")
	}
	return nil
}
