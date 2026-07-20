// Bucket view normalization preserves allowlist semantics across persistence.
package config

import "strings"

func normalizeBucketViews(views map[string]BucketViewSettings) map[string]BucketViewSettings {
	result := map[string]BucketViewSettings{}
	for bucket, view := range views {
		name := strings.TrimSpace(bucket)
		if name == "" {
			continue
		}
		result[name] = BucketViewSettings{
			DisplayName: strings.TrimSpace(view.DisplayName),
			RootPrefix:  strings.Trim(strings.TrimSpace(view.RootPrefix), "/"),
		}
	}
	return result
}

// BucketViewFor reports the configured allowlist entry for a provider bucket.
func (c RemoteStorageConfig) BucketViewFor(bucket string) (BucketViewSettings, bool) {
	normalized := c.Normalized()
	view, ok := normalized.BucketViews[strings.TrimSpace(bucket)]
	return view, ok
}
