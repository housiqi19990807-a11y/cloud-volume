// Package sync implements directory synchronization between a local folder
// and a remote bucket prefix. It reconciles state via a local index plus
// quiet-period debouncing, and emits upload/download/delete/rename tasks into
// the shared transfer monitor instead of polling the remote in a tight loop.
package sync

import (
	"errors"
	"path"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Direction controls which way changes flow during a reconcile pass.
type Direction string

const (
	// DirectionUpload pushes local changes to the remote.
	DirectionUpload Direction = "upload"
	// DirectionDownload pulls remote changes to the local folder.
	DirectionDownload Direction = "download"
	// DirectionTwoWay reconciles both sides, resolving conflicts via ConflictPolicy.
	DirectionTwoWay Direction = "twoway"
)

// ConflictPolicy decides what to do when both sides changed since the last sync.
type ConflictPolicy string

const (
	ConflictNewest      ConflictPolicy = "newest"
	ConflictLocalWins   ConflictPolicy = "local_wins"
	ConflictRemoteWins  ConflictPolicy = "remote_wins"
	ConflictSkip        ConflictPolicy = "skip"
)

// ProfileStatus reflects the runtime state of a sync profile.
type ProfileStatus string

const (
	StatusIdle      ProfileStatus = "idle"
	StatusSyncing   ProfileStatus = "syncing"
	StatusError     ProfileStatus = "error"
	StatusPaused    ProfileStatus = "paused"
)

// SyncProfile is a user-configured directory-sync pairing persisted to TOML.
type SyncProfile struct {
	ID             string         `json:"id" toml:"id"`
	Name           string         `json:"name" toml:"name"`
	AccountProfile string         `json:"accountProfile" toml:"account_profile"`
	Bucket         string         `json:"bucket" toml:"bucket"`
	RemotePrefix   string         `json:"remotePrefix" toml:"remote_prefix"`
	LocalPath      string         `json:"localPath" toml:"local_path"`
	Direction      Direction      `json:"direction" toml:"direction"`
	IntervalSeconds int           `json:"intervalSeconds" toml:"interval_seconds"`
	ConflictPolicy ConflictPolicy `json:"conflictPolicy" toml:"conflict_policy"`
	ExcludePatterns []string      `json:"excludePatterns" toml:"exclude_patterns"`
	QuietSeconds   int            `json:"quietSeconds" toml:"quiet_seconds"`
	Enabled        bool           `json:"enabled" toml:"enabled"`
}

// SyncProfileRuntime is the live view Flutter renders: profile + current state.
type SyncProfileRuntime struct {
	SyncProfile
	Status        ProfileStatus `json:"status"`
	LastSyncAt    string        `json:"lastSyncAt,omitempty"`
	LastError     string        `json:"lastError,omitempty"`
	PendingOps    int           `json:"pendingOps"`
	LastOpsCount  int           `json:"lastOpsCount"`
}

// Defaults applied to new profiles when fields are zero.
const (
	defaultIntervalSeconds = 300
	defaultQuietSeconds    = 10
	minIntervalSeconds     = 10
	maxIntervalSeconds     = 86400
	minQuietSeconds        = 0
	maxQuietSeconds        = 600
)

// NewProfileID returns a fresh unique profile identifier.
func NewProfileID() string {
	return "sync-" + uuid.NewString()
}

// Validate enforces required fields and clamps numeric ranges.
func (p SyncProfile) Validate() error {
	if strings.TrimSpace(p.Name) == "" {
		return errors.New("同步配置名称不能为空")
	}
	if strings.TrimSpace(p.LocalPath) == "" {
		return errors.New("本地目录不能为空")
	}
	if strings.TrimSpace(p.Bucket) == "" {
		return errors.New("远端桶不能为空")
	}
	switch p.Direction {
	case DirectionUpload, DirectionDownload, DirectionTwoWay:
	default:
		return errors.New("未知的同步方向")
	}
	switch p.ConflictPolicy {
	case ConflictNewest, ConflictLocalWins, ConflictRemoteWins, ConflictSkip:
	default:
		return errors.New("未知的冲突策略")
	}
	return nil
}

// Normalized clamps intervals and cleans the remote prefix into a trailing-slash form.
func (p SyncProfile) Normalized() SyncProfile {
	out := p
	if out.IntervalSeconds < minIntervalSeconds {
		out.IntervalSeconds = defaultIntervalSeconds
	}
	if out.IntervalSeconds > maxIntervalSeconds {
		out.IntervalSeconds = maxIntervalSeconds
	}
	if out.QuietSeconds < minQuietSeconds {
		out.QuietSeconds = defaultQuietSeconds
	}
	if out.QuietSeconds > maxQuietSeconds {
		out.QuietSeconds = maxQuietSeconds
	}
	out.RemotePrefix = cleanRemotePrefix(out.RemotePrefix)
	if len(out.ExcludePatterns) == 0 {
		out.ExcludePatterns = DefaultExcludePatterns()
	}
	return out
}

// cleanRemotePrefix returns a prefix with no leading slash and a single trailing slash.
func cleanRemotePrefix(prefix string) string {
	p := strings.Trim(strings.TrimSpace(prefix), "/")
	if p == "" {
		return ""
	}
	return p + "/"
}

// relativeKey joins a cleaned prefix with a slash-separated relative path.
func (p SyncProfile) relativeKey(rel string) string {
	clean := strings.Trim(p.RemotePrefix, "/")
	rel = strings.TrimPrefix(rel, "/")
	if clean == "" {
		return rel
	}
	return clean + "/" + rel
}

// DefaultExcludePatterns returns sensible defaults so OS cruft is not synced.
func DefaultExcludePatterns() []string {
	return []string{
		".DS_Store",
		".Trash",
		".Trash-*",
		"Thumbs.db",
		"desktop.ini",
		".svn",
		".git",
	}
}

// matchesExclude reports whether rel (slash-separated) matches any glob pattern.
func matchesExclude(rel string, patterns []string) bool {
	base := path.Base(rel)
	for _, pattern := range patterns {
		pattern = strings.TrimSpace(pattern)
		if pattern == "" {
			continue
		}
		if ok, _ := path.Match(pattern, base); ok {
			return true
		}
		if ok, _ := path.Match(pattern, rel); ok {
			return true
		}
	}
	return false
}

// quietDuration exposes the debounce window as a time.Duration.
func (p SyncProfile) quietDuration() time.Duration {
	return time.Duration(p.QuietSeconds) * time.Second
}
