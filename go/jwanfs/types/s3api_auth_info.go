// FGW auth-info response types.
package types

import "time"

// S3AuthInfoRes mirrors the gateway auth-info response. It is also the basis
// for the JWanFS-gateway auto-detection probe used by the SDK.
type S3AuthInfoRes struct {
	Status     string                 `json:"Status"`
	ExpireTime int64                  `json:"ExpireTime"`
	Resources  []AKSKBucketPermission `json:"Resources"`
	OwnerID    string                 `json:"OwnerID"`
}

// IsExpired reports whether the AKSK has expired (-1 means never).
func (r S3AuthInfoRes) IsExpired() bool {
	return r.ExpireTime != -1 && r.ExpireTime < time.Now().Unix()
}

