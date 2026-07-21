// Trash visibility helpers keep the app recycle bin hidden from mounted Finder views.
package mount

import (
	"io/fs"
	"strings"

	storageconfig "remote-storage/go/config"
	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) isTrashPath(virtualPath string) bool {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return false
	}
	// Match against aliases that already include RootPrefix when the account
	// is scoped to a subdirectory, so nested recycle bins stay hidden from
	// Finder/Explorer.
	name := strings.Trim(strings.TrimSpace(a.config.TrashDirectoryName), "/")
	if name == "" {
		name = ".trash"
	}
	root := strings.Trim(strings.TrimSpace(a.config.RootPrefix), "/")
	// Mount virtual paths are view-relative when RootPrefix is owned by the
	// mount layer (RootPrefix is cleared before ForConfig). Prefer the leaf
	// trash name for virtual-path checks; also accept the fully-resolved
	// provider path in case a raw key slips through.
	for _, trashName := range storageconfig.TrashDirectoryAliases(name) {
		trimmed := strings.Trim(strings.TrimSpace(trashName), "/")
		if clean == trimmed || strings.HasPrefix(clean, trimmed+"/") {
			return true
		}
		if root != "" {
			full := root + "/" + trimmed
			if clean == full || strings.HasPrefix(clean, full+"/") {
				return true
			}
		}
	}
	return false
}

func (a *bucketAccess) filterTrashItems(items []s3ops.ObjectInfo) []s3ops.ObjectInfo {
	filtered := make([]s3ops.ObjectInfo, 0, len(items))
	for _, item := range items {
		if a.isTrashPath(item.Key) {
			continue
		}
		filtered = append(filtered, item)
	}
	return filtered
}

func (a *bucketAccess) hiddenTrashError(virtualPath string) error {
	if !a.isTrashPath(virtualPath) {
		return nil
	}
	return fs.ErrNotExist
}
