// Trash item types keep soft-delete metadata separate from normal object listings.
package s3

// TrashItem describes one soft-deleted file or directory tree in the app trash.
type TrashItem struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	OriginalKey string `json:"originalKey"`
	TrashKey    string `json:"trashKey"`
	DeletedAt   string `json:"deletedAt"`
	IsDir       bool   `json:"isDir"`
	Size        int64  `json:"size"`
	ObjectCount int    `json:"objectCount"`
}
