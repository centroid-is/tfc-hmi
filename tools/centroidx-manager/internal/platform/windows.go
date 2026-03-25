//go:build windows

package platform

import "strings"

// windowsInstaller implements Installer on Windows using PowerShell commands.
type windowsInstaller struct {
	runner CommandRunner
}

// NewInstaller returns the Windows platform installer.
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
	return launchAppDetached(w.runner, `explorer.exe`)
}

func (w *windowsInstaller) IsInstalled() bool {
	out, err := w.runner.Run(
		"powershell", "-NoProfile", "-NonInteractive", "-Command",
		"Get-AppxPackage -Name 'Centroid.CentroidX' | Select-Object -ExpandProperty Status",
	)
	if err != nil {
		return false
	}
	return strings.TrimSpace(string(out)) == "Ok"
}

func (w *windowsInstaller) Uninstall() error {
	out, err := w.runner.Run(
		"powershell", "-NoProfile", "-NonInteractive", "-Command",
		"Get-AppxPackage -Name 'Centroid.CentroidX' | Remove-AppxPackage",
	)
	if err != nil {
		detail := strings.TrimSpace(string(out))
		if detail != "" {
			return &commandError{op: "Remove-AppxPackage failed: " + detail, cause: err}
		}
		return &commandError{op: "Remove-AppxPackage failed", cause: err}
	}
	return nil
}
