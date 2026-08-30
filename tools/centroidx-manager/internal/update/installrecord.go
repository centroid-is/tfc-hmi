package update

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// The install record remembers which build the manager last installed and,
// above all, when that build was published.
//
// For a tagged release the version says everything, but the latest channel
// installs the rolling `main-latest` build, whose package version is
// 0.YYYY.M.<run number> — the run number is not a date, so once the install
// finishes, nothing on the machine says which day's main the station is
// running. The publish time recorded here is the only place that timepoint
// survives, and it is what lets the picker say "you are on the build from
// Aug 27, the newest is from Aug 30" instead of showing two opaque numbers.

// installRecordFile is the file name under the manager's state directory.
const installRecordFile = "installed.json"

// InstallRecord is what the manager knows about the build it last installed.
type InstallRecord struct {
	// ReleaseVersion is the release the build came from: a tag like
	// "2026.8.23", or "main-latest" for the rolling development build.
	ReleaseVersion string `json:"release_version"`
	// PackageVersion is what the platform reported installed right after the
	// install (the MSIX Identity version on Windows). The picker compares it
	// against the live installed version: when they differ, something other
	// than this record's install put the current build there, and the record
	// says nothing about it.
	PackageVersion string    `json:"package_version"`
	Channel        string    `json:"channel"`
	PublishedAt    time.Time `json:"published_at"`
	InstalledAt    time.Time `json:"installed_at"`
}

// DescribesCurrentInstall reports whether this record is about the build that
// is installed right now. A record survives an install made by other means
// (a manual Add-AppxPackage, an older manager); trusting it then would date
// the wrong build.
func (r *InstallRecord) DescribesCurrentInstall(installedVersion string) bool {
	return r != nil &&
		r.PackageVersion != "" &&
		r.PackageVersion == installedVersion &&
		!r.PublishedAt.IsZero()
}

// stateDir is where the manager keeps its own state — distinct from the
// application's settings, which live in the package data container and are
// removed with it. CENTROIDX_MANAGER_STATE_DIR overrides it, which is what
// keeps tests out of the real config directory.
func stateDir() (string, error) {
	if dir := os.Getenv("CENTROIDX_MANAGER_STATE_DIR"); dir != "" {
		return dir, nil
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("locate the config directory: %w", err)
	}
	return filepath.Join(dir, "centroidx-manager"), nil
}

// SaveInstallRecord writes the record, replacing any previous one.
func SaveInstallRecord(rec InstallRecord) error {
	dir, err := stateDir()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create %s: %w", dir, err)
	}
	data, err := json.MarshalIndent(rec, "", "  ")
	if err != nil {
		return fmt.Errorf("encode the install record: %w", err)
	}
	path := filepath.Join(dir, installRecordFile)
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

// LoadInstallRecord reads the last saved record. No record is (nil, nil):
// a station the manager has never installed on is a normal state, not an
// error.
func LoadInstallRecord() (*InstallRecord, error) {
	dir, err := stateDir()
	if err != nil {
		return nil, err
	}
	path := filepath.Join(dir, installRecordFile)
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var rec InstallRecord
	if err := json.Unmarshal(data, &rec); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return &rec, nil
}
