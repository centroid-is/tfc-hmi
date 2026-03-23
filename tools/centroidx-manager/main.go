package main

import (
	"flag"

	"github.com/centroid-is/centroidx-manager/internal/ui"
)

// Build-time variables — set via -ldflags at release time.
// Example: go build -ldflags "-X main.githubOwner=centroid-is -X main.githubRepo=tfc-hmi2"
var (
	githubOwner = "centroid-is"
	githubRepo  = "tfc-hmi2"
)

func main() {
	// --- CLI flags ---
	updateMode := flag.Bool("update", false, "Run in update mode (called by Flutter app)")
	pickerMode := flag.Bool("picker", false, "Open version picker UI for rollback/manual install")
	version := flag.String("version", "", "Target version to install (default: latest)")
	waitPID := flag.Int("wait-pid", 0, "PID of the running app to wait for before installing")
	token := flag.String("token", "", "GitHub API token (optional; falls back to CENTROIDX_GITHUB_TOKEN env var)")

	flag.Parse()

	// --- Mode routing ---
	mode := "install" // default: first-time install
	if *updateMode {
		mode = "update"
	}
	if *pickerMode {
		mode = "picker"
	}

	// --- MSIX extraction (Windows only — see main_windows.go) ---
	// On Windows, if the manager is running from inside the MSIX VFS
	// (WindowsApps path), it extracts itself to APPDATA before proceeding.
	// This is handled in init() in main_windows.go via build tags.

	// --- Start UI ---
	ui.Run(ui.Options{
		Mode:    mode,
		Version: *version,
		WaitPID: *waitPID,
		Token:   *token,
		Owner:   githubOwner,
		Repo:    githubRepo,
	})
}
