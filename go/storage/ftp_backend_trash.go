// FTP trash and connection-helper glue.
package storage

import (
	"context"
	"fmt"

	ftpclient "github.com/jlaffaye/ftp"
)

// ftpConnLike allows tests to inject a mock connection type.
type ftpConnLike interface {
	MakeDir(string) error
}

func (b ftpBackend) ListTrashPage(
	_ context.Context,
	_ string,
	_ string,
	_ int32,
) (TrashPage, error) {
	return TrashPage{Items: []TrashItem{}}, nil
}

func (b ftpBackend) RestoreTrashItem(_ context.Context, _, _ string) error {
	return fmt.Errorf("FTP 账号暂不支持应用级回收站恢复")
}

func (b ftpBackend) DeleteTrashItem(_ context.Context, _, _ string) error {
	return fmt.Errorf("FTP 账号暂不支持应用级回收站删除")
}

func (b ftpBackend) ClearTrash(_ context.Context, _ string) error {
	return fmt.Errorf("FTP 账号暂不支持应用级回收站清空")
}

// Compile-time assertion that ftpBackend satisfies the Backend interface.
var _ Backend = ftpBackend{}

// Compile-time assertion that ftpConnLike is satisfied by the real FTP connection.
var _ ftpConnLike = (*ftpclient.ServerConn)(nil)

