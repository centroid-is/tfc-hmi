package platform

import (
	"errors"
	"os/exec"
	"strings"
)

// Installer is the interface for platform-specific installation operations.
// Each OS has a concrete implementation (windows.go, linux.go, darwin.go).
// This file has no build tag and compiles on all platforms.
type Installer interface {
	// Install installs the application from the given asset path.
	// On Windows: runs Add-AppxPackage via PowerShell.
	// On Linux: runs dpkg -i via pkexec or sudo.
	// On macOS: mounts DMG and copies .app or runs .pkg installer.
	Install(assetPath string) error

	// TrustCertificate installs a self-signed certificate into the OS trust store.
	// On Windows: imports to LocalMachine\TrustedPeople (not Root).
	// On Linux/macOS: no-op (certificate trust handled differently or not needed).
	TrustCertificate(certPath string) error

	// LaunchApp starts the installed application after update.
	LaunchApp() error

	// IsInstalled returns true if the application package is currently installed.
	IsInstalled() bool

	// Uninstall removes the application package.
	Uninstall() error
}

// CommandRunner abstracts exec.Command for testing.
// Platform implementations receive a CommandRunner so tests can inject a mock
// and verify the exact commands constructed without executing them.
type CommandRunner interface {
	Run(name string, args ...string) ([]byte, error)

	// Start launches a command without waiting for it to exit and without
	// capturing its output.
	Start(name string, args ...string) error
}

// execRunner is the real CommandRunner that delegates to os/exec.
type execRunner struct{}

func (e execRunner) Run(name string, args ...string) ([]byte, error) {
	return exec.Command(name, args...).CombinedOutput()
}

func (e execRunner) Start(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	if err := cmd.Start(); err != nil {
		return err
	}
	// The manager exits immediately after launching the app and will never
	// Wait, so release the handle rather than leave a zombie behind if it
	// somehow outlives the child.
	return cmd.Process.Release()
}

// publisherConflictHRESULT is ERROR_INSTALL_RESOLVE_DEPENDENCY_FAILED, the
// code Windows returns when an incoming package conflicts with an installed
// one. A rig that moves between Store and sideload signing lands here: the
// PackageFullName embeds a hash of the manifest Publisher string, so a re-signed
// CentroidX is, to deployment, a different package that happens to share a
// name, and it refuses to replace what is there. Removing the installed
// package and retrying is the fix.
//
// Source: microsoft/WindowsAppSDK#650 reproduces it from both ends — two builds
// differing only in the Publisher string produce PublisherIds 0rxggyxen88sc and
// 6jx1svrqfke3r, and installing the second fails with 0x80073cf3 and the text
// quoted in publisherConflictSignal.
// https://github.com/microsoft/WindowsAppSDK/issues/650
//
// It is *not* 0x80073CFB. That is ERROR_PACKAGE_ALREADY_EXISTS — see
// alreadyInstalledHRESULT, which exists to keep the two apart.
//
// Lower case because the comparison lower-cases detail first: the hex casing
// PowerShell happens to emit is not something an update should depend on.
const publisherConflictHRESULT = "0x80073cf3"

// publisherConflictSignal narrows that HRESULT to the conflict that removal
// actually repairs. 0x80073CF3 is a bucket, not a diagnosis: Microsoft
// documents it as "the package failed update, dependency, or conflict
// validation", covering three unrelated causes — the incoming package conflicts
// with an installed package, a specified package dependency can't be found, and
// the package doesn't support the correct processor architecture.
// https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting
//
// Only the first is fixed by uninstalling. On a missing dependency or a wrong
// architecture, uninstalling destroys a working CentroidX and the retry then
// fails for the original reason, leaving the station with no application at
// all — so the HRESULT on its own is not enough to act on. Windows names the
// conflict case in the detail text, and this is that sentence, verbatim from
// the WindowsAppSDK#650 repro:
//
//	Windows cannot install package MyPackageName_1.0.7.0_neutral_~_6jx1svrqfke3r
//	because a different package MyPackageName_1.0.6.0_neutral_~_0rxggyxen88sc
//	with the same name is already installed.
//
// The match is deliberately this narrow, and English-only. A localised Windows
// says the same thing in its own words — Italian emits "È già installato un
// pacchetto ... diverso con lo stesso nome" (microsoft/winget-cli#4752) — and
// will not match, so the update simply fails and an operator retries. That is
// the right direction to fail in: failing to recognise a conflict costs one
// failed update; mistaking anything else for a conflict costs the installation.
const publisherConflictSignal = "with the same name is already installed"

// alreadyInstalledHRESULT is ERROR_PACKAGE_ALREADY_EXISTS: "The provided
// package is already installed, and reinstallation of the package is blocked."
// Microsoft's documented cause is installing a package that is not bitwise
// identical to the one already on the machine — a rebuild or a re-sign under an
// unchanged version number, since the signature is part of the package — and
// the documented fixes are to increment the version or to remove the old
// package for every user first.
// https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting
//
// This is not a publisher conflict, and it is matched here only to guarantee it
// is never treated as one. What Windows is refusing to replace is a working
// CentroidX already at the version we were told to install; uninstalling it to
// retry would risk ending with nothing installed in order to fix nothing.
//
// It is reported rather than swallowed as success. The station is arguably
// already where the update wanted it, but a release re-cut under a version
// number that has already shipped is a build-pipeline fault that has to be
// fixed centrally, and reporting success would hide it on every rig at once.
const alreadyInstalledHRESULT = "0x80073cfb"

// installWindows runs Add-AppxPackage via PowerShell to install an MSIX.
// -ForceApplicationShutdown ensures any running package processes are stopped first.
func installWindows(runner CommandRunner, assetPath string) error {
	// Normalize path to Windows backslashes for PowerShell
	assetPath = strings.ReplaceAll(assetPath, "/", "\\")
	// First attempt: install directly.
	out, err := runner.Run(
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		"Add-AppxPackage -Path '"+assetPath+"' -ForceApplicationShutdown",
	)
	if err == nil {
		return nil
	}

	detail := strings.TrimSpace(string(out))
	lower := strings.ToLower(detail)

	// "Already installed" is checked first and returns, so that it can never
	// reach the removal path below however the two texts evolve. Uninstalling
	// here would remove a working CentroidX to fix a problem removal does not
	// fix. See alreadyInstalledHRESULT.
	if strings.Contains(lower, alreadyInstalledHRESULT) {
		return &commandError{
			op: "Add-AppxPackage failed: this package is already installed and Windows blocked " +
				"the reinstall (0x80073CFB). The installed CentroidX was left alone. This means " +
				"the release was rebuilt or re-signed without a version bump — cut a new version " +
				"rather than re-cutting this one — detail: " + detail,
			cause: err,
		}
	}

	// Only a publisher conflict justifies uninstalling what is already on the
	// machine; every other failure is reported as-is. Both the HRESULT and the
	// conflict sentence have to be present — see publisherConflictSignal for
	// why the code alone is not enough.
	if strings.Contains(lower, publisherConflictHRESULT) && strings.Contains(lower, publisherConflictSignal) {
		// Remove conflicting package(s) with the same identity name
		runner.Run(
			"powershell",
			"-NoProfile", "-NonInteractive",
			"-Command",
			"Get-AppxPackage -Name '"+windowsPackageName+"' | Remove-AppxPackage",
		)
		// Retry install
		out2, err2 := runner.Run(
			"powershell",
			"-NoProfile", "-NonInteractive",
			"-Command",
			"Add-AppxPackage -Path '"+assetPath+"' -ForceApplicationShutdown",
		)
		if err2 != nil {
			detail2 := strings.TrimSpace(string(out2))
			if detail2 != "" {
				return &commandError{op: "Add-AppxPackage failed after removing conflict: " + detail2, cause: err2}
			}
			return &commandError{op: "Add-AppxPackage failed after removing conflict", cause: err2}
		}
		return nil
	}

	if detail != "" {
		return &commandError{op: "Add-AppxPackage failed: " + detail, cause: err}
	}
	return &commandError{op: "Add-AppxPackage failed", cause: err}
}

// certStoreLocation is where a sideload signing certificate has to land.
// TrustedPeople is sufficient for MSIX sideloading and avoids the extra
// security dialog that LocalMachine\Root triggers. It has to be LocalMachine:
// Add-AppxPackage validates against machine-level trust, so the per-user
// Cert:\CurrentUser\TrustedPeople store is not a substitute even though the
// manager could write to it without elevation.
const certStoreLocation = `Cert:\LocalMachine\TrustedPeople`

// importCertificateCommand builds the PowerShell that imports certPath. It is
// also handed to the operator verbatim when the manager cannot run it itself,
// so the two can never drift apart.
func importCertificateCommand(certPath string) string {
	return `Import-Certificate -FilePath '` + certPath + `' -CertStoreLocation ` + certStoreLocation
}

// Tokens the trust script emits about itself. Everything the manager decides
// about a trust attempt is read from these, never from Windows' own wording:
// the stations run mixed and unknown locales, so any English phrase would be
// unreliable in production while passing every test we can write here.
const (
	trustOKToken       = "CENTROIDX_TRUST_OK"
	trustFailedToken   = "CENTROIDX_TRUST_FAILED"
	trustNotElevated   = "ELEVATED=FALSE"
	trustScriptSuccess = "> $null"
)

// trustCertificateScript imports the certificate and reports, in its own
// vocabulary, what happened.
//
// Elevation is asked of Windows rather than inferred from a failure message:
// IsInRole returns a boolean that means the same thing in every language. It is
// evaluated before the import so the answer is available even when the import
// throws.
//
// -ErrorAction Stop makes the cmdlet error terminating so the catch fires;
// without it a non-terminating error would skip the catch and emit the success
// token for an import that did not happen. (This is deliberately scoped to this
// script — the same flag is missing from Add-AppxPackage in installWindows, but
// that changes which installs count as failures and is tracked separately.)
func trustCertificateScript(certPath string) string {
	return `$e = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); ` +
		`try { ` + importCertificateCommand(certPath) + ` -ErrorAction Stop ` + trustScriptSuccess + `; ` +
		`Write-Output '` + trustOKToken + `' } ` +
		`catch { Write-Output ('` + trustFailedToken + ` ELEVATED=' + $e.ToString().ToUpper()); ` +
		`Write-Output $_.Exception.Message; exit 1 }`
}

// trustCertificateWindows imports a certificate into LocalMachine\TrustedPeople.
//
// Writing to a machine-level store requires administrator rights, and the
// manager never elevates itself, so on an ordinary station this fails. The
// engine treats that as non-fatal, which makes this error message the only
// thing an operator has to work from — so when the cause is rights, it says so
// and carries the one-time command, and when it is not, it does not.
//
// The verdict comes from the script's own tokens rather than the exit code or
// the message text. A missing token means we could not tell what happened, and
// that is reported as a failure: the caller treats trust as best-effort, so a
// false success would be silent and permanent.
func trustCertificateWindows(runner CommandRunner, certPath string) error {
	out, err := runner.Run(
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		trustCertificateScript(certPath),
	)

	detail := strings.TrimSpace(string(out))
	upper := strings.ToUpper(detail)

	if err == nil && strings.Contains(upper, trustOKToken) {
		return nil
	}

	// Keep a non-nil cause even when PowerShell exited 0 but told us it failed.
	cause := err
	if cause == nil {
		cause = errors.New("no exit status")
	}

	if strings.Contains(upper, trustFailedToken) {
		if strings.Contains(upper, trustNotElevated) {
			return &commandError{
				op: "Import-Certificate failed: the manager is not running as administrator and " +
					certStoreLocation + " requires it. Run this once from an elevated PowerShell: " +
					importCertificateCommand(certPath) + " — detail: " + detail,
				cause: cause,
			}
		}
		return &commandError{op: "Import-Certificate failed: " + detail, cause: cause}
	}

	// Neither token: the script did not run, or did not run to either end.
	if detail != "" {
		return &commandError{
			op:    "Import-Certificate produced no recognisable result, so the certificate cannot be assumed trusted: " + detail,
			cause: cause,
		}
	}
	return &commandError{
		op:    "Import-Certificate produced no output, so the certificate cannot be assumed trusted",
		cause: cause,
	}
}

// installLinux runs dpkg -i with pkexec (GUI elevation) or sudo (fallback).
func installLinux(runner CommandRunner, assetPath string) error {
	elevator := "pkexec"
	if _, err := exec.LookPath("pkexec"); err != nil {
		elevator = "sudo"
	}
	_, err := runner.Run(elevator, "dpkg", "-i", assetPath)
	if err != nil {
		return &commandError{op: "dpkg install failed", cause: err}
	}
	return nil
}

// installDarwin mounts a DMG, copies the .app to /Applications, strips the
// quarantine attribute, and unmounts the DMG.
func installDarwin(runner CommandRunner, assetPath string) error {
	out, err := runner.Run("hdiutil", "attach", assetPath, "-nobrowse", "-plist")
	if err != nil {
		return &commandError{op: "hdiutil attach failed", cause: err}
	}

	mountPoint := parseMountPoint(out)
	// Always detach on exit, even if a later step fails.
	defer runner.Run("hdiutil", "detach", mountPoint, "-quiet") //nolint:errcheck

	// Remove the old bundle first: cp -R onto an existing .app merges into it,
	// and files left over from the previous version break the new bundle's
	// code signature — macOS kills a hardened-runtime app whose seal no longer
	// matches its contents. Non-fatal so a fresh install (nothing to remove)
	// proceeds.
	runner.Run("rm", "-rf", "/Applications/CentroidX.app") //nolint:errcheck

	_, err = runner.Run("cp", "-R", mountPoint+"/CentroidX.app", "/Applications/")
	if err != nil {
		return &commandError{op: "cp .app failed", cause: err}
	}

	// Strip quarantine — failure is non-fatal (app may still launch with a dialog)
	runner.Run("xattr", "-r", "-d", "com.apple.quarantine", "/Applications/CentroidX.app") //nolint:errcheck
	return nil
}

// launchAppDetached starts the app without waiting for it to exit, so the
// manager can finish its update and quit.
//
// It must not go through Run: that captures combined output, which does not
// return until the child closes its pipes — i.e. until the app exits. Launching
// the HMI that way left the manager sitting on "installing" for as long as the
// HMI ran. Windows only escaped it by launching explorer.exe, which returns at
// once; fixing that alone would have turned this into a Windows bug too.
func launchAppDetached(runner CommandRunner, appPath string, args ...string) error {
	return runner.Start(appPath, args...)
}

// windowsPackageName is the MSIX identity name from centroid-hmi's msix_config.
const windowsPackageName = "Centroid.CentroidX"

// windowsAppID is the Application Id in the generated AppxManifest, which the
// AppsFolder URI needs after the "!".
//
// It is not a free choice and it is not "App": the msix builder writes the
// Application Id as the app name with underscores stripped (msix 3.16.13,
// lib/src/appx_manifest.dart:59) and takes that name from the Flutter package
// name (lib/src/configuration.dart:83). centroid-hmi's pubspec declares
// `name: centroidx`, so the id is "centroidx".
//
// If centroid-hmi's package name ever changes, this must change with it — the
// launch would otherwise fail with a URI that resolves to nothing.
const windowsAppID = "centroidx"

// launchWindowsApp starts the installed MSIX through its AppsFolder URI.
//
// A packaged app cannot be launched by path — there is no plain executable to
// run — so it goes through the shell:AppsFolder alias, which needs the package
// family name. That name embeds a hash derived from the publisher, so it
// changes whenever the signing identity does and must be read back from the
// installed package rather than baked in.
//
// The previous implementation ran "explorer.exe" with no arguments at all,
// which simply opens a File Explorer window: every successful update ended
// with the HMI gone and a file browser on the screen.
func launchWindowsApp(runner CommandRunner) error {
	out, err := runner.Run(
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		"(Get-AppxPackage -Name '"+windowsPackageName+"').PackageFamilyName",
	)
	if err != nil {
		detail := strings.TrimSpace(string(out))
		if detail != "" {
			return &commandError{op: "could not read the installed package family name: " + detail, cause: err}
		}
		return &commandError{op: "could not read the installed package family name", cause: err}
	}

	familyName := strings.TrimSpace(string(out))
	if familyName == "" {
		return &commandError{
			op:    "cannot launch " + windowsPackageName + ": it does not appear to be installed",
			cause: errors.New("Get-AppxPackage returned no package family name"),
		}
	}

	return launchAppDetached(runner, "explorer.exe", `shell:AppsFolder\`+familyName+"!"+windowsAppID)
}

// parseMountPoint extracts the /Volumes/... path from hdiutil -plist output.
// Looks for the last occurrence of a string starting with /Volumes/.
func parseMountPoint(plistOutput []byte) string {
	// Simple scan: find lines containing /Volumes/
	data := string(plistOutput)
	const needle = "/Volumes/"
	idx := -1
	for i := 0; i <= len(data)-len(needle); i++ {
		if data[i:i+len(needle)] == needle {
			idx = i
		}
	}
	if idx < 0 {
		return ""
	}
	// Consume until whitespace or XML tag end
	end := idx
	for end < len(data) && data[end] != '<' && data[end] != '\n' && data[end] != '\r' {
		end++
	}
	return data[idx:end]
}

// commandError wraps a command failure with its operation context.
type commandError struct {
	op    string
	cause error
}

func (e *commandError) Error() string {
	return e.op + ": " + e.cause.Error()
}

func (e *commandError) Unwrap() error { return e.cause }
