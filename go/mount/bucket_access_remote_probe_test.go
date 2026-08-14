// Remote path probe tests keep provider failures distinct from confirmed absence.
package mount

import (
	"context"
	"errors"
	"os"
	"testing"

	storageops "remote-storage/go/storage"
)

type remoteProbeErrorBackend struct {
	mountTestBackend
	headErr error
	listErr error
}

func (b remoteProbeErrorBackend) HeadObject(context.Context, string, string) (storageops.ObjectInfo, error) {
	return storageops.ObjectInfo{}, b.headErr
}

func (b remoteProbeErrorBackend) ListObjectsPage(
	context.Context,
	string,
	string,
	string,
	int32,
) (storageops.ObjectPage, error) {
	return storageops.ObjectPage{}, b.listErr
}

func TestDirectoryProbePropagatesProviderHeadError(t *testing.T) {
	want := errors.New("provider authentication failed")
	access := newTestBucketAccess(t)
	access.backend = remoteProbeErrorBackend{headErr: want}

	_, err := access.probeRemotePath(context.Background(), "Reports", true)
	if !errors.Is(err, want) {
		t.Fatalf("probe error = %v, want provider error %v", err, want)
	}
}

func TestDirectoryProbePropagatesProviderListingError(t *testing.T) {
	want := errors.New("provider listing failed")
	access := newTestBucketAccess(t)
	access.backend = remoteProbeErrorBackend{headErr: os.ErrNotExist, listErr: want}

	_, err := access.probeRemotePath(context.Background(), "Reports", true)
	if !errors.Is(err, want) {
		t.Fatalf("probe error = %v, want provider error %v", err, want)
	}
}
