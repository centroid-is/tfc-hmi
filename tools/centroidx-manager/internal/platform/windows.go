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
	// Removing the package removes its data container with it, and that is
	// where the station's own configuration lives -- key mappings, the page
	// layout, the update channel, everything written through
	// SharedPreferences, because under MSIX a write to %APPDATA% is
	// redirected inside the container.
	//
	// An uninstall from here is nearly always a step in something else: going
	// back to an older release, or moving to a build Windows will not install
	// over the current one. Both end in an install, and the operator does not
	// expect to reconfigure the station on the way. So the container is put
	// aside first, and the next install that finds no package installed puts
	// it back (see installWindows).
	savePackageData(w.runner)

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
