// Sort and search enums migrated from jwanfs/pkg/consts.
// Kept as string newtypes so FGW query structs serialize identically.
package types

// SortOrder controls asc/desc listing order.
type SortOrder string

const (
	SortOrderAsc  SortOrder = "asc"
	SortOrderDesc SortOrder = "desc"
)

// ToInt returns +1 for asc and -1 for desc.
func (s SortOrder) ToInt() int {
	if s == SortOrderAsc {
		return 1
	}
	return -1
}

// SortBy selects the field to sort by.
type SortBy string

const (
	SortByName SortBy = "name"
	SortByTime SortBy = "time"
	SortBySize SortBy = "size"
)

// SearchType filters files by category in search/list requests.
type SearchType string

const (
	SearchTypeImage SearchType = "image"
	SearchTypeVideo SearchType = "video"
	SearchTypeDoc   SearchType = "doc"
	SearchTypeAudio SearchType = "audio"
	SearchTypeZip   SearchType = "zip"
	SearchTypeOther SearchType = "other"
)

