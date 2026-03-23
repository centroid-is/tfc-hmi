package update

import (
	"fmt"
	"strings"

	"github.com/Masterminds/semver/v3"
)

// ParseVersion parses a CalVer version string (e.g. "2026.3.6", "v2026.3.6", "2026.3.6+1").
// It strips the leading "v" prefix and any "+buildMetadata" suffix before parsing,
// because Masterminds/semver NewVersion handles these but stripping avoids ambiguity.
// NOTE: Use NewVersion (not StrictNewVersion) — StrictNewVersion rejects CalVer like "2026.3.6".
func ParseVersion(raw string) (*semver.Version, error) {
	if raw == "" {
		return nil, fmt.Errorf("version string is empty")
	}
	// Strip build metadata (Flutter uses YYYY.MM.DD+buildNumber format)
	if idx := strings.Index(raw, "+"); idx != -1 {
		raw = raw[:idx]
	}
	// Strip leading "v" if present (GitHub tags often use "v2026.3.6")
	raw = strings.TrimPrefix(raw, "v")

	v, err := semver.NewVersion(raw)
	if err != nil {
		return nil, fmt.Errorf("parse version %q: %w", raw, err)
	}
	return v, nil
}

// IsNewer returns true if candidate is a newer version than current.
// Both strings are parsed through ParseVersion, so "v" prefix and build metadata are handled.
func IsNewer(candidate, current string) (bool, error) {
	c, err := ParseVersion(candidate)
	if err != nil {
		return false, fmt.Errorf("parse candidate version %q: %w", candidate, err)
	}
	cur, err := ParseVersion(current)
	if err != nil {
		return false, fmt.Errorf("parse current version %q: %w", current, err)
	}
	return c.GreaterThan(cur), nil
}
