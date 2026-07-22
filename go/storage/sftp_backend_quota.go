// SFTP quota support: SFTP v3/v6 servers may expose disk free space via
// statvfs@openssh.com extended request. When available we return total/used;
// otherwise QuotaKnown stays false and the UI shows an unknown-capacity track.
package storage

import (
	"context"

	"github.com/pkg/sftp"
)

// sftpQuota attempts to read the server-side filesystem statistics via the
// statvfs@openssh.com SFTP extension (supported by OpenSSH and most modern
// SFTP servers). Returns (total, used, known=false) when unsupported.
func (b sftpBackend) sftpQuota(ctx context.Context) (total, used int64, known bool, err error) {
	client, sshConn, dialErr := b.sftpClient(ctx)
	if dialErr != nil {
		return 0, 0, false, dialErr
	}
	defer func() {
		_ = client.Close()
		_ = sshConn.Close()
	}()
	// Try statvfs on root — the most reliable path that always exists.
	stat, err := client.StatVFS("/")
	if err != nil {
		// statvfs extension not supported — not an error, just unknown.
		return 0, 0, false, nil
	}
	total = int64(stat.Blocks) * int64(stat.Bsize)
	free := int64(stat.Bfree) * int64(stat.Bsize)
	used = total - free
	if total <= 0 {
		return 0, 0, false, nil
	}
	return total, used, true, nil
}

// Compile-time assertion that sftp stat fields we use exist.
var _ = sftp.StatVFS{}

