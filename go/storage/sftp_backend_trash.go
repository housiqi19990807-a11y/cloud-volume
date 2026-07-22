// SFTP trash stubs: FTP/SFTP servers have their own server-side delete semantics
// and do not support the app-level soft-delete trash contract.
package storage

import (
	"context"
	"fmt"
)

func (b sftpBackend) ListTrashPage(
	_ context.Context,
	_ string,
	_ string,
	_ int32,
) (TrashPage, error) {
	return TrashPage{Items: []TrashItem{}}, nil
}

func (b sftpBackend) RestoreTrashItem(_ context.Context, _, _ string) error {
	return fmt.Errorf("SFTP 账号暂不支持应用级回收站恢复")
}

func (b sftpBackend) DeleteTrashItem(_ context.Context, _, _ string) error {
	return fmt.Errorf("SFTP 账号暂不支持应用级回收站删除")
}

func (b sftpBackend) ClearTrash(_ context.Context, _ string) error {
	return fmt.Errorf("SFTP 账号暂不支持应用级回收站清空")
}

// Compile-time assertion that sftpBackend satisfies the Backend interface.
var _ Backend = sftpBackend{}

