//go:build !windows

package update

import "errors"

// Elevated unpacking and Start-menu shortcuts are Windows notions; the
// portable install is a Windows path today.
func unpackElevated(src, dst, version string) error {
	return errors.New("elevated unpack is only implemented on Windows")
}

func createShortcut(exePath, name string) error { return nil }
