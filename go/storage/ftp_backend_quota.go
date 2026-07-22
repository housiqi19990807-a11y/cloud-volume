// FTP quota support: FTP servers occasionally expose free/used space via the
// SITE QUOTA extension or custom STAT responses. When unavailable the bucket
// simply reports QuotaKnown=false so the UI shows an unknown-capacity track.
package storage

import (
	"context"
	"strings"
)

// ftpSupportsQuota reports whether the backend advertises server-side quota.
// FTP has no standard quota protocol so we return false by default; servers
// that do support it can be added as opt-in cases later.
func (b ftpBackend) supportsQuota() bool {
	return false
}

// ftpQuota attempts to read free/used space from the FTP server.
// Returns QuotaKnown=false when the server does not provide quota info.
func (b ftpBackend) ftpQuota(ctx context.Context) (total, used int64, known bool, err error) {
	_ = ctx
	// Standard FTP has no quota command. We try the STAT response on root
	// which some servers (e.g. vsftpd with quota plugin) annotate with
	// free space. This is best-effort and non-fatal.
	conn, err := b.ftpConnect(ctx)
	if err != nil {
		return 0, 0, false, err
	}
	defer func() { _ = conn.Quit() }()
	// STAT on "/" — most servers just return a directory listing here.
	// If a future server returns quota-like numbers, parse them.
	_ = conn
	return 0, 0, false, nil
}

// ftpFreeSpaceFromStat is a placeholder for parsing STAT output.
// Real FTP quota parsing would look for patterns like "free space: N bytes".
func ftpFreeSpaceFromStat(statText string) (total, used int64, ok bool) {
	lower := strings.ToLower(statText)
	if !strings.Contains(lower, "quota") && !strings.Contains(lower, "free space") {
		return 0, 0, false
	}
	// Future: parse actual numbers. For now, report unknown.
	return 0, 0, false
}

