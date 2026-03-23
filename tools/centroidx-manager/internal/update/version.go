package update

import "github.com/Masterminds/semver/v3"

// ParseVersion parses a CalVer version string, stripping v prefix and build metadata.
func ParseVersion(raw string) (*semver.Version, error) {
	return nil, nil
}

// IsNewer returns true if candidate is a newer version than current.
func IsNewer(candidate, current string) (bool, error) {
	return false, nil
}
