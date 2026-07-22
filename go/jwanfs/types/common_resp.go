// FGW common envelope and list helpers, migrated from jwanfs/pkg/types.
package types

// FGWResp is the standard envelope returned by every FGW JSON route.
// Code == 200 means success; Data carries the typed payload (may be nil).
type FGWResp[T any] struct {
	Code int    `json:"Code"`
	Msg  string `json:"Msg"`
	Data *T     `json:"Data"`
}

