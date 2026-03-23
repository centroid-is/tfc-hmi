//go:build windows

package platform

// windowsInstaller implements Installer on Windows using PowerShell commands.
type windowsInstaller struct {
	runner CommandRunner
}

// NewInstaller returns the Windows platform installer.
// Only one NewInstaller function compiles per target platform.
func NewInstaller() Installer {
	return &windowsInstaller{runner: execRunner{}}
}

func (w *windowsInstaller) Install(assetPath string) error {
	return installWindows(w.runner, assetPath)
}

func (w *windowsInstaller) TrustCertificate(certPath string) error {
	return trustCertificateWindows(w.runner, certPath)
}

func (w *windowsInstaller) LaunchApp() error {
	// Launch via shell:AppsFolder so Windows resolves the MSIX app by package family name.
	return launchAppDetached(w.runner, `explorer.exe`)
}
