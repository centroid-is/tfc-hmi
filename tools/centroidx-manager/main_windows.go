//go:build windows

package main

import (
	"log"

	"github.com/centroid-is/centroidx-manager/internal/platform"
)

// init runs before main() on Windows. If the manager is executing from within
// the MSIX VFS (WindowsApps path), it copies itself to APPDATA so it can
// outlive the current package during updates.
func init() {
	if platform.IsRunningFromMSIX() {
		if err := platform.ExtractManager(); err != nil {
			// Log but do not abort — the manager can still function
			// even if the extraction fails (e.g., on first install
			// before any MSIX has been installed).
			log.Printf("warn: failed to extract manager from MSIX: %v", err)
		}
	}
}
