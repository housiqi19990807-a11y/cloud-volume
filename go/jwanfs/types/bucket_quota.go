// Bucket quota types returned by the FGW bucket-quota route.
package types

// GetBucketQuotaReq is retained for wire compatibility but is not currently
// sent as a body by the SDK (the route uses the bucket header).
type GetBucketQuotaReq struct {
	OwnerID string `json:"OwnerID"`
	Bucket  string `json:"Bucket"`
}

// GetBucketQuotaRes mirrors the gateway quota response. Sizes are int64 bytes.
type GetBucketQuotaRes struct {
	Total int64 `json:"Total"`
	Free  int64 `json:"Free"`
	Used  int64 `json:"Used"`
}

