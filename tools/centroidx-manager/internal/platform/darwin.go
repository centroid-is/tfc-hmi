//go:build darwin

package platform

// darwinInstaller implements Installer on macOS using hdiutil and xattr.
type darwinInstaller struct {
	runner CommandRunner
}

// NewInstaller returns the macOS platform installer.
// Only one NewInstaller function compiles per target platform.
func NewInstaller() Installer {
	return &darwinInstaller{runner: execRunner{}}
}

func (d *darwinInstaller) Install(assetPath string) error {
	return installDarwin(d.runner, assetPath)
}

// TrustCertificate is a no-op on macOS — certificate trust for internal apps
// is handled via user acceptance on first launch (Gatekeeper dialog).
func (d *darwinInstaller) TrustCertificate(_ string) error {
	return nil
}

func (d *darwinInstaller) LaunchApp() error {
	return launchAppDetached(d.runner, "/Applications/CentroidX.app/Contents/MacOS/centroidx")
}
