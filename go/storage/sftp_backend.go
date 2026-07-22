// SFTP backend connects to an SSH/SFTP server using pkg/sftp as the client.
// Like the FTP backend, it exposes the remote tree as a single virtual bucket.
package storage

import (
	"context"
	"fmt"
	"net"
	"strconv"
	"strings"
	"time"

	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"

	storageconfig "remote-storage/go/config"
)

// sftpBackend implements Backend over an SSH/SFTP connection.
type sftpBackend struct {
	cfg storageconfig.RemoteStorageConfig
}

// newSFTPBackend constructs an SFTP backend from the normalized config.
func newSFTPBackend(cfg storageconfig.RemoteStorageConfig) Backend {
	return sftpBackend{cfg: cfg}
}

// sftpClient dials the configured SFTP endpoint and returns a live client.
// The caller is responsible for closing both the sftp client and the underlying SSH connection.
func (b sftpBackend) sftpClient(ctx context.Context) (*sftp.Client, *ssh.Client, error) {
	host := b.dialHost()
	if ctx == nil {
		ctx = context.Background()
	}
	user, pass := b.sftpCredentials()
	sshConfig := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.Password(pass)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         30 * time.Second,
	}
	sshClient, err := ssh.Dial("tcp", host, sshConfig)
	if err != nil {
		return nil, nil, fmt.Errorf("sftp ssh dial %s: %w", host, err)
	}
	client, err := sftp.NewClient(sshClient)
	if err != nil {
		_ = sshClient.Close()
		return nil, nil, fmt.Errorf("sftp init: %w", err)
	}
	return client, sshClient, nil
}

// sftpHostPort extracts host:port from an endpoint URL or bare address.
// If no port is present the SFTP default 22 is assumed.
func sftpHostPort(endpoint string) string {
	return hostPortFromEndpoint(endpoint, 22)
}

// sftpCredentials returns (username, password) for the SSH connection,
// applying anonymous login conventions when FTPAnonymous is set.
func (b sftpBackend) sftpCredentials() (string, string) {
	if b.cfg.FTPAnonymous {
		user := b.cfg.FTPUsername
		if user == "" {
			user = "anonymous"
		}
		return user, b.cfg.FTPPassword
	}
	return b.cfg.FTPUsername, b.cfg.FTPPassword
}

// dialHost resolves the host:port to dial, honoring an explicit FTPPort override.
func (b sftpBackend) dialHost() string {
	host := hostFromEndpoint(b.cfg.Endpoint)
	if b.cfg.FTPPort > 0 {
		return net.JoinHostPort(host, strconv.Itoa(b.cfg.FTPPort))
	}
	return hostPortFromEndpoint(b.cfg.Endpoint, 22)
}

// sftpBucketLabel returns the display name for the single virtual bucket.
func sftpBucketLabel(cfg storageconfig.RemoteStorageConfig) string {
	label := strings.TrimSpace(cfg.MappedBucketLabel())
	if label != "" {
		return label
	}
	return "SFTP"
}

func (b sftpBackend) bucketConfig(bucket string) storageconfig.RemoteStorageConfig {
	return b.cfg.WithBucketSettingsApplied(bucket)
}

func (b sftpBackend) ensureBucketWritable(bucket string) error {
	if b.bucketConfig(bucket).BucketSettingsFor(bucket).ReadOnly {
		return fmt.Errorf("当前存储桶已配置为只读，无法写入")
	}
	return nil
}

// sftpRemotePath converts a view-relative key to an absolute SFTP server path.
func sftpRemotePath(key string) string {
	clean := strings.Trim(strings.TrimSpace(key), "/")
	if clean == "" {
		return "/"
	}
	return "/" + clean
}

// sftpBucketQuota implements BucketQuotaProvider for SFTP via statvfs extension.
func (b sftpBackend) BucketQuota(ctx context.Context, bucketName string) (BucketInfo, error) {
	bucket := BucketInfo{Name: bucketName}
	total, used, known, err := b.sftpQuota(ctx)
	if err != nil {
		return bucket, err
	}
	if known {
		bucket.QuotaBytes = total
		bucket.UsedBytes = used
		bucket.QuotaKnown = true
	}
	return bucket, nil
}

func (b sftpBackend) ListBuckets(context.Context) ([]BucketInfo, error) {
	return []BucketInfo{{Name: sftpBucketLabel(b.cfg)}}, nil
}
