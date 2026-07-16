//go:build !windows

// Non-Windows builds expose no drive-letter choices to the shared bridge.
package mount

// AvailableWindowsDriveLetters keeps the bridge API portable.
func AvailableWindowsDriveLetters() ([]string, error) {
	return []string{}, nil
}
