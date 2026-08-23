package platform

import (
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
}

// execRunner is the real CommandRunner that delegates to os/exec.
type execRunner struct{}

func (e execRunner) Run(name string, args ...string) ([]byte, error) {
	return exec.Command(name, args...).CombinedOutput()
}

// publisherConflictHRESULT is ERROR_PACKAGE_ALREADY_EXISTS: a package with
// this identity is installed but was signed by a different publisher, so
// deployment refuses to replace it — what happens when a rig switches between
// Store and sideload signing. Removing the installed package and retrying is
// the fix, and it is the only failure for which it is the fix.
//
// The match is deliberately this narrow. Windows prefixes nearly every
// deployment error with "Deployment failed with HRESULT: 0x...", and the
// neighbouring 0x80073CFx codes are unrelated causes — out of disk space
// (…CF4), network failure (…CF5), plain install failure (…CF9). Matching any
// of those uninstalls a working CentroidX and then fails the retry for the
// original reason, leaving the machine with no application at all. Failing to
// recognise a conflict costs one failed update that an operator can retry;
// mistaking anything else for a conflict costs the installation, so the tie
// goes to matching too little.
//
// Lower case because the comparison lower-cases detail first: the hex casing
// PowerShell happens to emit is not something an update should depend on.
const publisherConflictHRESULT = "0x80073cfb"

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

	// Only a publisher conflict justifies uninstalling what is already on the
	// machine; every other failure is reported as-is. See
	// publisherConflictHRESULT for why the match is not broader.
	if strings.Contains(strings.ToLower(detail), publisherConflictHRESULT) {
		// Remove conflicting package(s) with the same identity name
		runner.Run(
			"powershell",
			"-NoProfile", "-NonInteractive",
			"-Command",
			"Get-AppxPackage -Name 'Centroid.CentroidX' | Remove-AppxPackage",
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

// elevationRequiredSignals are the ways Windows says "you are not an
// administrator". Unlike the publisher-conflict match in installWindows, a
// false positive here is harmless — it only changes the wording of an error
// that has already happened, and never destroys anything — so this errs
// towards matching, where that one errs away from it.
var elevationRequiredSignals = []string{
	"access is denied",
	"unauthorizedaccessexception",
	"requested registry access is not allowed",
	"0x80070005",
}

// trustCertificateWindows imports a certificate into LocalMachine\TrustedPeople.
//
// Writing to a machine-level store requires administrator rights, and the
// manager never requests elevation, so on an ordinary station this fails. The
// engine treats that as non-fatal, which makes this error message the only
// thing an operator has to work from — hence the command output is folded in,
// and a rights failure says so and carries the one-time manual fix.
func trustCertificateWindows(runner CommandRunner, certPath string) error {
	out, err := runner.Run(
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		importCertificateCommand(certPath),
	)
	if err == nil {
		return nil
	}

	detail := strings.TrimSpace(string(out))
	lower := strings.ToLower(detail)
	for _, signal := range elevationRequiredSignals {
		if strings.Contains(lower, signal) {
			return &commandError{
				op: "Import-Certificate failed: the manager is not running as administrator and " +
					certStoreLocation + " requires it. Run this once from an elevated PowerShell: " +
					importCertificateCommand(certPath) + " — detail: " + detail,
				cause: err,
			}
		}
	}
	if detail != "" {
		return &commandError{op: "Import-Certificate failed: " + detail, cause: err}
	}
	return &commandError{op: "Import-Certificate failed", cause: err}
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

// launchAppDetached starts the app as a detached process so the manager can exit.
// appPath is platform-specific: shell:AppsFolder URI on Windows, binary path elsewhere.
func launchAppDetached(runner CommandRunner, appPath string) error {
	_, err := runner.Run(appPath)
	return err
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
