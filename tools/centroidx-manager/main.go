package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/centroid-is/centroidx-manager/internal/platform"
	"github.com/centroid-is/centroidx-manager/internal/ui"
	"github.com/centroid-is/centroidx-manager/internal/update"
)

// initLogFile mirrors the log into %TEMP%\centroidx-manager.log. Built as a
// GUI app the manager has no console, so stderr alone would swallow exactly
// the lines that explain a failed station install -- the trust warning Jon
// debugged from was only ever on screen because the build still had a
// console. Best effort: no log file is no reason not to run.
func initLogFile() {
	path := filepath.Join(os.TempDir(), "centroidx-manager.log")
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return
	}
	log.SetOutput(fileAndConsole{file: f})
	log.Printf("---- centroidx-manager started (pid %d) ----", os.Getpid())
}

// fileAndConsole writes the log to the file and, when there is still a
// console, to stderr as well.
//
// Not io.MultiWriter: it stops at the first writer that errors, and after
// hideOwnConsole freed the console stderr is a dead handle -- so every line
// failed on stderr and never reached the file. The file is the one that has
// to work; the console is a nicety for whoever runs the manager from a shell.
type fileAndConsole struct{ file *os.File }

func (w fileAndConsole) Write(p []byte) (int, error) {
	_, _ = os.Stderr.Write(p)
	return w.file.Write(p)
}

// Build-time variables — set via -ldflags at release time.
// Example: go build -ldflags "-X main.githubOwner=centroid-is -X main.githubRepo=tfc-hmi"
var (
	githubOwner = "centroid-is"
	githubRepo  = "tfc-hmi"
)

func main() {
	// The console window first, before anything can print into it.
	hideOwnConsole()
	initLogFile()

	// --- CLI flags ---
	updateMode := flag.Bool("update", false, "Run in update mode (called by Flutter app)")
	pickerMode := flag.Bool("picker", false, "Open version picker UI for rollback/manual install")
	version := flag.String("version", "", "Target version to install (default: newest on the channel)")
	channel := flag.String("channel", "stable", "Release channel: 'stable' (tagged releases) or 'latest' (includes main prereleases)")
	waitPID := flag.Int("wait-pid", 0, "PID of the running app to wait for before installing")
	token := flag.String("token", "", "GitHub API token (optional; falls back to CENTROIDX_GITHUB_TOKEN env var)")
	prsMode := flag.Bool("prs", false, "Show open PRs with CI artifacts to install from (dev/testing)")
	localPkg := flag.String("local-package", "", "Install from a local package file (dev/testing: skip GitHub Releases)")
	artifactURL := flag.String("artifact-url", "", "Download and install from a direct URL (dev/testing: CI artifact URLs)")
	trustCert := flag.String("trust-cert", "", "Import a signing certificate into the machine trust store (used by the elevated copy of the manager; assumes it is already elevated)")

	flag.Parse()

	// The elevated copy: import and exit, no window, no UI. Everything the
	// operator sees happens in the parent that asked Windows for approval.
	if *trustCert != "" {
		if err := platform.ImportCertificateNow(*trustCert); err != nil {
			fmt.Fprintf(os.Stderr, "trust certificate: %v\n", err)
			os.Exit(1)
		}
		return
	}

	if !update.ValidChannel(*channel) {
		fmt.Fprintf(os.Stderr, "unknown channel %q: expected %q or %q\n", *channel, update.ChannelStable, update.ChannelLatest)
		os.Exit(2)
	}

	// --- Mode routing ---
	mode := "picker" // default: show version picker
	if *updateMode {
		mode = "update"
	}
	if *pickerMode {
		mode = "picker"
	}
	if *prsMode {
		mode = "prs"
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
		Channel:     *channel,
		WaitPID:     *waitPID,
		Token:       *token,
		Owner:       githubOwner,
		Repo:        githubRepo,
		LocalPkg:    *localPkg,
		ArtifactURL: *artifactURL,
	})
}
