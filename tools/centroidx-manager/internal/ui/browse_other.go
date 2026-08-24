//go:build !windows

package ui

// browseForFolder has no native picker outside Windows; the portable install
// is a Windows-only path today, so this keeps the package building.
func browseForFolder(start string) (string, error) { return "", nil }
