//go:build windows && !cgo

// Windows without CGO cannot compile the Cloud Files backend, so mount stays disabled.
package mount

import "fmt"

type windowsNoCGOBackend struct{}

func newPlatformMountBackend() (mountBackend, error) {
	return nil, fmt.Errorf("Windows Cloud Files mount requires CGO_ENABLED=1")
}

func (b *windowsNoCGOBackend) Initialize(session *mountSession) error {
	return fmt.Errorf("Windows Cloud Files mount requires CGO_ENABLED=1")
}

func (b *windowsNoCGOBackend) Start(session *mountSession) error {
	return fmt.Errorf("Windows Cloud Files mount requires CGO_ENABLED=1")
}

func (b *windowsNoCGOBackend) Stop(session *mountSession) error {
	return nil
}

func (b *windowsNoCGOBackend) IsActive(session *mountSession) (bool, error) {
	return false, nil
}

func (b *windowsNoCGOBackend) CleanupStale(session *mountSession) error {
	return nil
}

func cleanupAllManagedMounts() error {
	return nil
}
