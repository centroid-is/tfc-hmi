//go:build linux

package platform

// linuxInstaller implements Installer on Linux using dpkg.
type linuxInstaller struct {
	runner CommandRunner
}

// NewInstaller returns the Linux platform installer.
// Only one NewInstaller function compiles per target platform.
func NewInstaller() Installer {
	return &linuxInstaller{runner: execRunner{}}
}

func (l *linuxInstaller) Install(assetPath string) error {
	return installLinux(l.runner, assetPath)
}

// TrustCertificate is a no-op on Linux — certificate trust is handled
// through system CA bundle updates which are outside the manager's scope.
func (l *linuxInstaller) TrustCertificate(_ string) error {
	return nil
}

func (l *linuxInstaller) LaunchApp() error {
	return launchAppDetached(l.runner, "/opt/centroidx/centroidx")
}
