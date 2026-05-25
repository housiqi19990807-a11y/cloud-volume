// Trash visibility helpers keep the app recycle bin hidden from mounted Finder views.
package mount

import (
	"io/fs"
	"strings"

	s3ops "remote-storage/go/s3"
)

func (a *bucketAccess) isTrashPath(virtualPath string) bool {
	clean := cleanVirtualPath(virtualPath)
	if clean == "" {
		return false
	}
	trashName := strings.Trim(strings.TrimSpace(a.config.TrashDirectoryName), "/")
	if trashName == "" {
		trashName = ".trash"
	}
	return clean == trashName || strings.HasPrefix(clean, trashName+"/")
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
