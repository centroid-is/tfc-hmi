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
	return launchWindowsApp(w.runner)
}

// CertificateTrusted reports whether ANY certificate issued to our sideload
// publisher is in the machine store. The wizard asks before offering the
// approval prompt, so a station that was set up once is never asked again.
//
// Reading the store needs no rights; the subject is the publisher from
// msix_config, so this does not depend on having the .cer file to hand.
func (w *windowsInstaller) CertificateTrusted() bool {
	out, err := w.runner.Run(
		"powershell", "-NoProfile", "-NonInteractive", "-Command",
		`if (Get-ChildItem `+certStoreLocation+` | Where-Object { $_.Subject -like '*`+sideloadPublisherCN+`*' }) `+
			`{ Write-Output '`+trustPresentToken+`' } else { Write-Output '`+trustAbsentToken+`' }`,
	)
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToUpper(string(out)), trustPresentToken)
}

func (w *windowsInstaller) InstalledVersion() string {
	out, err := w.runner.Run(
		"powershell", "-NoProfile", "-NonInteractive", "-Command",
		"Get-AppxPackage -Name 'Centroid.CentroidX' | Select-Object -ExpandProperty Version",
	)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
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
