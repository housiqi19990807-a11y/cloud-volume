// WebDAV access helpers detect per-directory write permissions when advertised.
package storage

import (
	"context"
	"encoding/xml"
	"fmt"
	"net/http"
	"strings"
)

func (b webDAVBackend) DirectoryAccess(
	ctx context.Context,
	_, prefix string,
) (DirectoryAccess, error) {
	access, err := b.directoryAccessFromPropfind(ctx, prefix)
	if err == nil && access.Known {
		return access, nil
	}
	return b.directoryAccessFromOptions(ctx, prefix)
}

func (b webDAVBackend) ensureWritableDirectory(ctx context.Context, prefix string) error {
	access, err := b.DirectoryAccess(ctx, "", cleanParentDirectory(prefix))
	if err != nil {
		return err
	}
	if access.Known && !access.Writable {
		if access.Reason != "" {
			return fmt.Errorf("%s", access.Reason)
		}
		return fmt.Errorf("当前 WebDAV 目录为只读，无法写入")
	}
	return nil
}

func cleanParentDirectory(value string) string {
	clean := cleanRemotePath(value)
	if clean == "." {
		return ""
	}
	return clean
}

func (b webDAVBackend) directoryAccessFromPropfind(
	ctx context.Context,
	prefix string,
) (DirectoryAccess, error) {
	req, err := b.request(ctx, "PROPFIND", webDAVDirectoryKey(prefix), strings.NewReader(webDAVPrivilegePropfindBody))
	if err != nil {
		return DirectoryAccess{}, err
	}
	req.Header.Set("Depth", "0")
	req.Header.Set("Content-Type", `application/xml; charset="utf-8"`)
	resp, err := b.client.Do(req)
	if err != nil {
		return DirectoryAccess{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return DirectoryAccess{}, fmt.Errorf("webdav propfind: %s", resp.Status)
	}
	var multi webDAVPrivilegeMultistatus
	if err := xml.NewDecoder(resp.Body).Decode(&multi); err != nil {
		return DirectoryAccess{}, err
	}
	for _, response := range multi.Responses {
		for _, propstat := range response.Propstat {
			if !propstat.statusOK() || len(propstat.Prop.Privileges) == 0 {
				continue
			}
			return accessFromPrivileges(propstat.Prop.Privileges), nil
		}
	}
	return DirectoryAccess{Writable: true, Known: false}, nil
}

func (b webDAVBackend) directoryAccessFromOptions(
	ctx context.Context,
	prefix string,
) (DirectoryAccess, error) {
	req, err := b.request(ctx, http.MethodOptions, webDAVDirectoryKey(prefix), nil)
	if err != nil {
		return DirectoryAccess{}, err
	}
	resp, err := b.client.Do(req)
	if err != nil {
		return DirectoryAccess{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusForbidden || resp.StatusCode == http.StatusUnauthorized {
		return DirectoryAccess{Writable: false, Known: true, Reason: "当前 WebDAV 目录为只读，无法写入"}, nil
	}
	if resp.StatusCode >= 300 {
		return DirectoryAccess{Writable: true, Known: false}, nil
	}
	allow := strings.ToUpper(resp.Header.Get("Allow"))
	if allow == "" {
		return DirectoryAccess{Writable: true, Known: false}, nil
	}
	if strings.Contains(allow, "PUT") || strings.Contains(allow, "MKCOL") {
		return DirectoryAccess{Writable: true, Known: true}, nil
	}
	return DirectoryAccess{Writable: true, Known: false}, nil
}

func webDAVDirectoryKey(prefix string) string {
	clean := cleanRemotePath(prefix)
	if clean == "" {
		return ""
	}
	return clean + "/"
}

func accessFromPrivileges(privileges []webDAVPrivilege) DirectoryAccess {
	var readable bool
	var writable bool
	for _, privilege := range privileges {
		for _, name := range privilege.Names {
			local := strings.ToLower(name.Local)
			if local == "read" {
				readable = true
			}
			if local == "write" || local == "write-content" || local == "bind" ||
				local == "unbind" || local == "all" {
				writable = true
			}
		}
	}
	if writable {
		return DirectoryAccess{Writable: true, Known: true}
	}
	if readable {
		return DirectoryAccess{Writable: false, Known: true, Reason: "当前 WebDAV 目录为只读，无法写入"}
	}
	return DirectoryAccess{Writable: true, Known: false}
}

const webDAVPrivilegePropfindBody = `<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:current-user-privilege-set/>
  </D:prop>
</D:propfind>`

type webDAVPrivilegeMultistatus struct {
	Responses []webDAVPrivilegeResponse `xml:"response"`
}

type webDAVPrivilegeResponse struct {
	Propstat []webDAVPrivilegePropstat `xml:"propstat"`
}

type webDAVPrivilegePropstat struct {
	Status string              `xml:"status"`
	Prop   webDAVPrivilegeProp `xml:"prop"`
}

func (p webDAVPrivilegePropstat) statusOK() bool {
	return p.Status == "" || strings.Contains(p.Status, " 200 ")
}

type webDAVPrivilegeProp struct {
	Privileges []webDAVPrivilege `xml:"current-user-privilege-set>privilege"`
}

type webDAVPrivilege struct {
	Names []xml.Name `xml:",any"`
}
