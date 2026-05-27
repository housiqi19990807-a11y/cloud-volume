// Share record types keep presigned-link metadata separate from S3 object models.

package share

// Record describes one locally tracked file-sharing link.
type Record struct {
	ID          string `json:"id"`
	Bucket      string `json:"bucket"`
	Key         string `json:"key"`
	Name        string `json:"name"`
	URL         string `json:"url"`
	ExpiresAt   string `json:"expiresAt"`
	DurationSec int    `json:"durationSec"`
	CreatedAt   string `json:"createdAt"`
	UpdatedAt   string `json:"updatedAt"`
}
