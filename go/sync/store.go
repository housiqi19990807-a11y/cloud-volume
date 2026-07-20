// Store persists sync profiles to TOML alongside the main config layout.
package sync

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	toml "github.com/pelletier/go-toml/v2"
)

// profilesFile is the single TOML document holding every sync profile.
const profilesFile = "sync_profiles.toml"

// Store reads and writes the sync-profile document under a base directory.
type Store struct {
	baseDir string
}

// NewStore targets an explicit base directory (usually the app config root).
func NewStore(baseDir string) Store {
	return Store{baseDir: baseDir}
}

func (s Store) path() string {
	return filepath.Join(s.baseDir, profilesFile)
}

// document is the on-disk TOML shape.
type document struct {
	Profiles []SyncProfile `toml:"profiles"`
}

// LoadAll returns every stored profile, sorted by name.
func (s Store) LoadAll() ([]SyncProfile, error) {
	data, err := os.ReadFile(s.path())
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read sync profiles: %w", err)
	}
	if strings.TrimSpace(string(data)) == "" {
		return nil, nil
	}
	var doc document
	if err := toml.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("parse sync profiles: %w", err)
	}
	out := make([]SyncProfile, 0, len(doc.Profiles))
	for _, p := range doc.Profiles {
		out = append(out, p.Normalized())
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

// SaveAll replaces the entire profile set.
func (s Store) SaveAll(profiles []SyncProfile) error {
	if err := os.MkdirAll(s.baseDir, 0o700); err != nil {
		return fmt.Errorf("create sync config dir: %w", err)
	}
	doc := document{Profiles: profiles}
	body, err := toml.Marshal(doc)
	if err != nil {
		return fmt.Errorf("encode sync profiles: %w", err)
	}
	payload := append([]byte("# Cloud Volume sync profiles.\n"), body...)
	if err := os.WriteFile(s.path(), payload, 0o600); err != nil {
		return fmt.Errorf("write sync profiles: %w", err)
	}
	return nil
}

// Upsert inserts or replaces a single profile by ID.
func (s Store) Upsert(profile SyncProfile) error {
	profiles, err := s.LoadAll()
	if err != nil {
		return err
	}
	normalized := profile.Normalized()
	found := false
	for i, existing := range profiles {
		if existing.ID == normalized.ID {
			profiles[i] = normalized
			found = true
			break
		}
	}
	if !found {
		profiles = append(profiles, normalized)
	}
	return s.SaveAll(profiles)
}

// Delete removes a profile by ID. A fresh slice is allocated (instead of
// reusing the source backing array) so concurrent readers cannot observe
// stale entries after SaveAll rewrites the document.
func (s Store) Delete(id string) error {
	profiles, err := s.LoadAll()
	if err != nil {
		return err
	}
	out := make([]SyncProfile, 0, len(profiles))
	for _, p := range profiles {
		if p.ID != id {
			out = append(out, p)
		}
	}
	return s.SaveAll(out)
}

// DeleteByAccount removes every sync profile that references the given
// account profile name. It returns the number of profiles removed so callers
// (e.g. account deletion) can report cascade counts.
func (s Store) DeleteByAccount(accountProfile string) (int, error) {
	target := strings.TrimSpace(accountProfile)
	if target == "" {
		return 0, nil
	}
	profiles, err := s.LoadAll()
	if err != nil {
		return 0, err
	}
	out := make([]SyncProfile, 0, len(profiles))
	removed := 0
	for _, p := range profiles {
		if strings.TrimSpace(p.AccountProfile) == target {
			removed++
			continue
		}
		out = append(out, p)
	}
	if removed == 0 {
		return 0, nil
	}
	if err := s.SaveAll(out); err != nil {
		return 0, err
	}
	return removed, nil
}
