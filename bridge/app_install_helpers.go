// Helpers shared by the in-app update installer paths.

package main

import "strings"

// psQuote wraps a Windows path/value for safe embedding in a generated
// PowerShell script, escaping single quotes by doubling them.
func psQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "''") + "'"
}
