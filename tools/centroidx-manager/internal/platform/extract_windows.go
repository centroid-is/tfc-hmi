//go:build windows

package platform

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// IsRunningFromMSIX returns true when the current executable is running from
// the MSIX VFS path (i.e., under WindowsApps). This indicates the manager is
// bundled inside the installed MSIX package and needs to be extracted to
// APPDATA so it can outlive the package during updates.
func IsRunningFromMSIX() bool {
	exe, err := os.Executable()
	if err != nil {
		return false
	}
	return pathIsFromMSIX(exe)
}

// pathIsFromMSIX is the testable core of IsRunningFromMSIX.
func pathIsFromMSIX(exePath string) bool {
	return strings.Contains(exePath, "WindowsApps")
}

// ExtractManager copies the current manager executable to
// %APPDATA%\centroidx\manager\centroidx-manager.exe so it can be used for
// self-updates after it is no longer accessible from the MSIX VFS.
//
// If the destination already exists and has the same file size as the source,
// this function is a no-op (idempotent).
func ExtractManager() error {
	src, err := os.Executable()
	if err != nil {
		return fmt.Errorf("ExtractManager: resolve executable: %w", err)
	}

	appdata := os.Getenv("APPDATA")
	if appdata == "" {
		return fmt.Errorf("ExtractManager: APPDATA environment variable not set")
	}

	return extractManagerFrom(src, appdata)
}

// extractManagerFrom is the testable core of ExtractManager.
// src is the source executable path; appdataRoot is the APPDATA directory.
func extractManagerFrom(src, appdataRoot string) error {
	destDir := filepath.Join(appdataRoot, "centroidx", "manager")
	dest := filepath.Join(destDir, "centroidx-manager.exe")

	// Check if already extracted with same size (idempotent guard).
	srcInfo, err := os.Stat(src)
	if err != nil {
		return fmt.Errorf("extractManagerFrom: stat source: %w", err)
	}
	if destInfo, err := os.Stat(dest); err == nil {
		if destInfo.Size() == srcInfo.Size() {
			return nil // already extracted
		}
	}

	// Create destination directory if needed.
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return fmt.Errorf("extractManagerFrom: create dest dir: %w", err)
	}

	return copyFile(src, dest)
}

// copyFile copies src to dest atomically via a temp file + rename.
func copyFile(src, dest string) error {
	in, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("copyFile: open source: %w", err)
	}
	defer in.Close()

	tmpDest := dest + ".tmp"
	out, err := os.Create(tmpDest)
	if err != nil {
		return fmt.Errorf("copyFile: create temp: %w", err)
	}
	defer func() {
		out.Close()
		os.Remove(tmpDest)
	}()

	if _, err := io.Copy(out, in); err != nil {
		return fmt.Errorf("copyFile: copy: %w", err)
	}
	if err := out.Close(); err != nil {
		return fmt.Errorf("copyFile: close temp: %w", err)
	}

	if err := os.Rename(tmpDest, dest); err != nil {
		return fmt.Errorf("copyFile: rename: %w", err)
	}
	return nil
}
