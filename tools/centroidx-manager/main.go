package main

import (
	"flag"

	"github.com/centroid-is/centroidx-manager/internal/ui"
)

// Build-time variables — set via -ldflags at release time.
// Example: go build -ldflags "-X main.githubOwner=centroid-is -X main.githubRepo=tfc-hmi"
var (
	githubOwner = "centroid-is"
	githubRepo  = "tfc-hmi"
)

func main() {
	// --- CLI flags ---
	updateMode := flag.Bool("update", false, "Run in update mode (called by Flutter app)")
	pickerMode := flag.Bool("picker", false, "Open version picker UI for rollback/manual install")
	version := flag.String("version", "", "Target version to install (default: latest)")
	waitPID := flag.Int("wait-pid", 0, "PID of the running app to wait for before installing")
	token := flag.String("token", "", "GitHub API token (optional; falls back to CENTROIDX_GITHUB_TOKEN env var)")
	localPkg := flag.String("local-package", "", "Install from a local package file (dev/testing: skip GitHub Releases)")
	artifactURL := flag.String("artifact-url", "", "Download and install from a direct URL (dev/testing: CI artifact URLs)")

	flag.Parse()

	// --- Mode routing ---
	mode := "install" // default: first-time install
	if *updateMode {
		mode = "update"
	}
	if *pickerMode {
		mode = "picker"
	}
	if *localPkg != "" {
		mode = "local-install"
	}
	if *artifactURL != "" {
		mode = "url-install"
	}

	// --- MSIX extraction (Windows only — see main_windows.go) ---
	// On Windows, if the manager is running from inside the MSIX VFS
	// (WindowsApps path), it extracts itself to APPDATA before proceeding.
	// This is handled in init() in main_windows.go via build tags.

	// --- Start UI ---
	ui.Run(ui.Options{
		Mode:        mode,
		Version:     *version,
		WaitPID:     *waitPID,
		Token:       *token,
		Owner:       githubOwner,
		Repo:        githubRepo,
		LocalPkg:    *localPkg,
		ArtifactURL: *artifactURL,
	})
}
