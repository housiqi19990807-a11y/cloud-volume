//go:build windows

// Windows drive mappings expose Cloud Files sync-root directories as optional drive letters.
package mount

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/windows"
)

type windowsDriveMapping struct {
	drive  string
	target string
}

var getLogicalDrivesProc = windows.NewLazySystemDLL("kernel32.dll").NewProc("GetLogicalDrives")

func allocateWindowsDriveLetter() (string, error) {
	letters, err := availableWindowsDriveLetters()
	if err != nil {
		return "", err
	}
	if len(letters) == 0 {
		return "", fmt.Errorf("no available drive letter")
	}
	return letters[0], nil
}

// AvailableWindowsDriveLetters returns free mount choices in preferred order.
func AvailableWindowsDriveLetters() ([]string, error) {
	return availableWindowsDriveLetters()
}

func availableWindowsDriveLetters() ([]string, error) {
	mask, _, callErr := getLogicalDrivesProc.Call()
	if mask == 0 {
		return nil, fmt.Errorf("list local drives: %v", callErr)
	}
	used := uint32(mask)
	letters := make([]string, 0, 23)
	for letter := 'Z'; letter >= 'D'; letter-- {
		index := uint(letter - 'A')
		if used&(1<<index) == 0 {
			letters = append(letters, string(letter)+":")
		}
	}
	return letters, nil
}

func assignWindowsDriveLetter(targetPath, requestedDrive string) (string, error) {
	target := filepath.Clean(strings.TrimSpace(targetPath))
	if !filepath.IsAbs(target) {
		return "", fmt.Errorf("drive mapping target must be absolute")
	}
	info, err := os.Stat(target)
	if err != nil {
		return "", fmt.Errorf("inspect drive mapping target %q: %w", target, err)
	}
	if !info.IsDir() {
		return "", fmt.Errorf("drive mapping target %q is not a directory", target)
	}

	drive, err := selectWindowsDriveLetter(requestedDrive)
	if err != nil {
		return "", err
	}
	output, err := hiddenWindowsCommand("subst.exe", drive, target).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("map %s to %q: %w: %s", drive, target, err, strings.TrimSpace(string(output)))
	}
	mappings, err := listWindowsDriveMappings()
	if err != nil {
		_ = removeWindowsDriveLetter(drive, target)
		return "", err
	}
	for _, mapping := range mappings {
		if mapping.drive == drive && windowsPathsEqual(mapping.target, target) {
			return drive + `\`, nil
		}
	}
	_ = removeWindowsDriveLetter(drive, target)
	return "", fmt.Errorf("drive mapping %s was not visible after creation", drive)
}

func selectWindowsDriveLetter(requestedDrive string) (string, error) {
	if strings.TrimSpace(requestedDrive) == "" {
		return allocateWindowsDriveLetter()
	}
	drive, err := normalizeWindowsDriveRequest(requestedDrive)
	if err != nil {
		return "", err
	}
	letters, err := availableWindowsDriveLetters()
	if err != nil {
		return "", err
	}
	for _, available := range letters {
		if available == drive {
			return drive, nil
		}
	}
	return "", fmt.Errorf("requested drive letter %s is no longer available", drive)
}

func normalizeWindowsDriveRequest(value string) (string, error) {
	trimmed := strings.ToUpper(strings.TrimSpace(value))
	if len(trimmed) == 1 {
		trimmed += ":"
	}
	drive := normalizeWindowsDrive(trimmed)
	if drive == "" || len(drive) != 2 || drive[0] < 'D' || drive[0] > 'Z' {
		return "", fmt.Errorf("invalid drive letter %q", value)
	}
	return drive, nil
}

func removeWindowsDriveLetter(drivePath, expectedTarget string) error {
	drive := normalizeWindowsDrive(drivePath)
	if drive == "" {
		return nil
	}
	mappings, err := listWindowsDriveMappings()
	if err != nil {
		return err
	}
	for _, mapping := range mappings {
		if mapping.drive != drive {
			continue
		}
		if expectedTarget != "" && !windowsPathsEqual(mapping.target, expectedTarget) {
			return fmt.Errorf(
				"refusing to remove %s: target %q does not match %q",
				drive,
				mapping.target,
				expectedTarget,
			)
		}
		output, removeErr := hiddenWindowsCommand("subst.exe", drive, "/D").CombinedOutput()
		if removeErr != nil {
			return fmt.Errorf("remove drive mapping %s: %w: %s", drive, removeErr, strings.TrimSpace(string(output)))
		}
		return nil
	}
	return nil
}

func listWindowsDriveMappings() ([]windowsDriveMapping, error) {
	output, err := hiddenWindowsCommand("subst.exe").CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("list drive mappings: %w: %s", err, strings.TrimSpace(string(output)))
	}
	return parseWindowsDriveMappings(string(output)), nil
}

func parseWindowsDriveMappings(output string) []windowsDriveMapping {
	mappings := make([]windowsDriveMapping, 0)
	for _, line := range strings.Split(output, "\n") {
		parts := strings.SplitN(strings.TrimSpace(line), "=>", 2)
		if len(parts) != 2 {
			continue
		}
		drive := normalizeWindowsDrive(strings.TrimSpace(parts[0]))
		target := filepath.Clean(strings.TrimSpace(parts[1]))
		if drive == "" || target == "." {
			continue
		}
		mappings = append(mappings, windowsDriveMapping{drive: drive, target: target})
	}
	return mappings
}

func cleanupWindowsDriveMappingsForPath(targetPath string) error {
	mappings, err := listWindowsDriveMappings()
	if err != nil {
		return err
	}
	for _, mapping := range mappings {
		if !windowsPathsEqual(mapping.target, targetPath) {
			continue
		}
		if err := removeWindowsDriveLetter(mapping.drive, targetPath); err != nil {
			return err
		}
	}
	return nil
}

func cleanupManagedWindowsCloudFilesDriveMappings() error {
	rootPath, err := windowsCloudFilesRootPath()
	if err != nil {
		return err
	}
	mappings, err := listWindowsDriveMappings()
	if err != nil {
		return err
	}
	for _, mapping := range mappings {
		if !isManagedWindowsCloudFilesMappingTarget(rootPath, mapping.target) {
			continue
		}
		if err := removeWindowsDriveLetter(mapping.drive, mapping.target); err != nil {
			return err
		}
	}
	return nil
}

func isManagedWindowsCloudFilesMappingTarget(rootPath, targetPath string) bool {
	return windowsPathsEqual(filepath.Dir(filepath.Clean(targetPath)), rootPath)
}

func windowsPathsEqual(left, right string) bool {
	return strings.EqualFold(
		filepath.Clean(strings.TrimSpace(left)),
		filepath.Clean(strings.TrimSpace(right)),
	)
}
