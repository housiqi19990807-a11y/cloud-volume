//go:build windows && cgo

// Existing Cloud Files directories are repaired when a retained cache is mounted again.
package mount

// #cgo amd64 CFLAGS: -I. -D_AMD64_ -D_M_AMD64=100 -DWIN64 -D_WIN32_WINNT=0x0A00
// #cgo arm64 CFLAGS: -I. -D_ARM64_ -D_M_ARM64=1 -DWIN64 -D_WIN32_WINNT=0x0A00
// #include "cloud_files_windows.h"
// #include <stdlib.h>
import "C"

import (
	"fmt"
	"log"
	"unsafe"
)

func (p *cloudFilesProvider) repairExistingDirectoryPlaceholder(
	localPath string,
	item cloudPlaceholderInfo,
) error {
	updated, err := p.UpdatePlaceholder(localPath, item)
	if err != nil {
		return fmt.Errorf("refresh retained directory placeholder %q: %w", localPath, err)
	}
	if updated {
		log.Printf(
			"[mount/cloud-files] retained-directory path=%q action=enable-on-demand",
			localPath,
		)
		return nil
	}
	if err := p.convertDirectoryToPlaceholder(localPath, item.FileID); err != nil {
		return fmt.Errorf("convert retained directory %q to placeholder: %w", localPath, err)
	}
	log.Printf(
		"[mount/cloud-files] retained-directory path=%q action=convert-placeholder",
		localPath,
	)
	return nil
}

func (p *cloudFilesProvider) convertDirectoryToPlaceholder(
	localPath,
	fileID string,
) error {
	wPath, freePath := cloudFilesWideString(localPath)
	defer freePath()

	var identity *C.char
	if fileID != "" {
		identity = C.CString(fileID)
		defer C.free(unsafe.Pointer(identity))
	}
	hr := C.rs_cf_convert_directory_placeholder(
		wPath,
		C.LPCVOID(unsafe.Pointer(identity)),
		C.DWORD(len(fileID)),
	)
	if hr != 0 {
		return fmt.Errorf("HRESULT 0x%08x", uint32(hr))
	}
	return nil
}

func boolToInt(value bool) int {
	if value {
		return 1
	}
	return 0
}
