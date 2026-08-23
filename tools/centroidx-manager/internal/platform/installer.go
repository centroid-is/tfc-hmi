package platform

import (
	"errors"
	"os/exec"
	"strings"
)

// collapseWhitespace reduces every run of whitespace to a single space, undoing
// the line breaks and continuation indents PowerShell's formatter inserts when
// it wraps an error record to the host width — 120 columns when no console is
// attached, which is how the manager runs it. Any phrase long enough to be worth
// matching is long enough to be split in half by that.
//
// The HRESULT matches below would survive without it: the formatter breaks at
// spaces and a hex code is one short token, so nothing can land inside it. It is
// applied anyway, because "normalise before matching output" is the rule this
// file wants, and the next matcher added here may well be a phrase. The case
// that genuinely needs it today is elevationRequiredSignals in
// trustCertificateWindows, whose signals are multi-word — that belongs to the
// change fixing #300 and is deliberately left alone here.
func collapseWhitespace(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

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

// publisherConflictHRESULT is ERROR_INSTALL_RESOLVE_DEPENDENCY_FAILED, the code
// Windows returns when deployment fails update, dependency, or conflict
// validation. A rig that moves between Store and sideload signing lands here:
// the PackageFullName embeds a hash of the manifest Publisher string, so a
// re-signed CentroidX is, to deployment, a different package that happens to
// share a name, and it refuses to replace what is there.
//
// Source: microsoft/WindowsAppSDK#650 reproduces it from both ends — two builds
// differing only in the Publisher string produce PublisherIds 0rxggyxen88sc and
// 6jx1svrqfke3r, and installing the second fails with 0x80073cf3.
// https://github.com/microsoft/WindowsAppSDK/issues/650
//
// It is *not* 0x80073CFB. That is ERROR_PACKAGE_ALREADY_EXISTS — see
// alreadyInstalledHRESULT, which exists to keep the two apart.
//
// The code alone is not a diagnosis, though. Microsoft documents the same
// HRESULT for three unrelated causes — the incoming package conflicts with an
// installed package, a dependency can't be found, and the package doesn't
// support the correct processor architecture — and uninstalling CentroidX
// repairs only the first, while destroying it in the other two.
// https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting
// So this narrows the failure; publisherConflict decides.
//
// Matched without the "0x" and in lower case. The hex digits are the only part
// of the message guaranteed not to change with the system locale: the sentence
// around them is translated, and even the prefix varies by producer — PowerShell
// prints "0x80073CF3" while winget's log prints a bare "80073CF3"
// (microsoft/winget-cli#4752). Matching the digits alone depends on neither.
const publisherConflictHRESULT = "80073cf3"

// installedPublisherCommand reads the Publisher of the installed package that
// carries our identity name.
//
// -Name filters on the package identity Name alone: Get-AppxPackage takes -Name
// and -Publisher as separate, independent parameters, so a package installed
// under a *different* publisher is still returned by a -Name query. That is
// what makes this whole approach possible, and it is not obvious — if -Name had
// implied the family name (which embeds the publisher hash) the conflicting
// package would have been invisible here.
// https://learn.microsoft.com/en-us/powershell/module/appx/get-appxpackage
//
// Windows permits at most one package per identity Name per user — that is the
// conflict — so this yields a single value, not a list.
// -ErrorAction Stop makes any cmdlet error terminating, so PowerShell exits
// non-zero and the answer is discarded. Without it a non-terminating error is
// written to stderr while the process still exits 0, and because the manager
// captures combined output that error text would arrive here looking like an
// answer — a "publisher" that matches nothing, which reads as a difference,
// which uninstalls. The dangerous direction is reached by doing nothing special,
// so this is not optional.
func installedPublisherCommand() string {
	return "Get-AppxPackage -Name '" + windowsPackageName + "' -ErrorAction Stop | " +
		"Select-Object -ExpandProperty Publisher"
}

// assetPublisherCommand reads Identity/@Publisher out of the .msix about to be
// installed, by opening it as the zip archive it is and reading AppxManifest.xml
// from the root.
//
// The publisher has to come from the asset and cannot be a constant in this
// repo, which is worth stating because a constant is the obvious move and it is
// wrong. A baked-in "our publisher" reflects the manager's build time, not the
// asset's, and the conflict arises precisely when those disagree: at the moment
// signing changes, a rig is still running the manager built before the change,
// whose constant still holds the old publisher — the same value it would read
// off the installed package. It would compare them equal, conclude "no
// conflict", and skip the recovery in the one scenario the recovery exists for.
// Reading the asset has no such ordering assumption.
//
// If anything here fails — the file is not a zip, the entry is missing, the XML
// will not parse — the command produces no output and publisherConflict returns
// false, so the failure direction is "do not uninstall".
func assetPublisherCommand(assetPath string) string {
	return "$ErrorActionPreference='Stop'; " +
		"Add-Type -AssemblyName System.IO.Compression.FileSystem; " +
		"$z=[IO.Compression.ZipFile]::OpenRead('" + assetPath + "'); " +
		"try { $e=$z.GetEntry('AppxManifest.xml'); if ($e) { " +
		"$r=New-Object IO.StreamReader($e.Open()); " +
		"([xml]$r.ReadToEnd()).Package.Identity.Publisher } } finally { $z.Dispose() }"
}

// publisherConflict reports whether the failed install is the publisher
// conflict, by asking Windows what is installed rather than by reading what it
// said about it.
//
// Every earlier version of this matched the error text — an English sentence,
// or the shape of the package full names inside it. Both depend on Windows
// putting the answer in prose, and the station locales are mixed or unknown, so
// both were a guess about phrasing standing between a working HMI and an
// uninstall. This asks instead: it is locale-independent by construction,
// because no part of the answer comes from a message.
//
// Publishers are compared byte for byte, not case-insensitively and not
// normalised. That is Windows' own semantics: the PublisherId hash is computed
// over the exact Publisher string, with no normalisation, and even the order of
// the distinguished-name elements changes it (WindowsAppSDK#650). Two spellings
// that differ only in case really are two different packages to deployment, so
// treating them as equal here would skip a genuine conflict.
//
// Both unknowns fail towards not uninstalling: if our identity is not installed
// there is nothing to conflict with, and if the asset's publisher cannot be read
// there is nothing to compare. A failed update is retryable; a destroyed
// installation is not.
func publisherConflict(runner CommandRunner, assetPath string) bool {
	installed := publisherAnswer(runner, installedPublisherCommand())
	if installed == "" {
		return false
	}
	incoming := publisherAnswer(runner, assetPublisherCommand(assetPath))
	if incoming == "" {
		return false
	}
	return installed != incoming
}

// publisherDNMarker is the one thing every Appx Publisher string has: it is an
// X.500 distinguished name, and a distinguished name has a common name. Both
// CentroidX's own "CN=2F2634E3-C7B6-45A4-A112-0D039FC2ECDB" and Microsoft's
// "CN=Microsoft Corporation, O=..., C=US" carry it.
const publisherDNMarker = "CN="

// publisherAnswer runs a query and returns its answer only if the answer could
// be a publisher at all. Anything else — a PowerShell error that reached stdout,
// a warning, an empty result — is "could not determine", never an answer.
//
// The check is here because the failure direction is asymmetric and unforgiving.
// An unrecognised string is not equal to the other publisher, so passing it
// through would read as "the publishers differ" and uninstall a working HMI on
// the strength of a diagnostic message. Requiring the shape of a publisher turns
// every such surprise into a refusal to act.
//
// Whitespace is collapsed first so that a distinguished name the formatter
// wrapped across lines compares equal to the same name that fitted on one.
func publisherAnswer(runner CommandRunner, command string) string {
	out, err := runner.Run("powershell", "-NoProfile", "-NonInteractive", "-Command", command)
	if err != nil {
		return ""
	}
	answer := collapseWhitespace(string(out))
	if !strings.Contains(strings.ToUpper(answer), publisherDNMarker) {
		return ""
	}
	return answer
}

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
// is never treated as one.
//
// It must not be reported as success either, and the reason is definitional
// rather than a matter of taste. CFB fires only when the incoming package is
// not bitwise identical to the installed one, because if it were identical
// Add-AppxPackage would have succeeded and this code would never appear. So CFB
// is Windows saying "you do not have what you are trying to install". It can
// never mean "already where we wanted to be": calling it success would report an
// update as applied while the station keeps running the old build, and LaunchApp
// would then dutifully relaunch that old build.
//
// Nor may it uninstall, and here the reasoning is an asymmetry rather than a
// definition — Microsoft's second documented remedy for CFB *is* to remove the
// old package for every user before installing the new one, so removal is not
// wrong for CFB in the abstract. It is wrong for us. CFB fires on a re-signed
// package, which is exactly the situation where our retry is most likely to hit
// an untrusted certificate and fail. We would be staking the whole installation
// on that retry in exchange for reinstalling a version that is already present.
const alreadyInstalledHRESULT = "80073cfb"

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
	// Everything below matches against matchable, never against detail: PowerShell
	// hard-wraps error records to the host width and indents the continuations, so
	// any phrase long enough to be worth matching is long enough to be split in
	// half. Collapsing runs of whitespace to single spaces undoes the formatter's
	// line breaks and its indent in one step. detail stays raw, because it is what
	// the operator reads.
	matchable := collapseWhitespace(strings.ToLower(detail))

	// "Already installed" is checked first and returns, so that it can never
	// reach the removal path below however the two texts evolve. Uninstalling
	// here would remove a working CentroidX to fix a problem removal does not
	// fix. See alreadyInstalledHRESULT.
	if strings.Contains(matchable, alreadyInstalledHRESULT) {
		return &commandError{
			op: "Add-AppxPackage failed: this package is already installed and Windows blocked " +
				"the reinstall (0x80073CFB). The installed CentroidX was left alone. This means " +
				"the release was rebuilt or re-signed without a version bump — cut a new version " +
				"rather than re-cutting this one — detail: " + detail,
			cause: err,
		}
	}

	// Only a publisher conflict justifies uninstalling what is already on the
	// machine; every other failure is reported as-is. The HRESULT narrows the
	// failure to a bucket of three causes and publisherConflict picks the one
	// removal actually repairs — by querying Windows, not by parsing it.
	if strings.Contains(matchable, publisherConflictHRESULT) && publisherConflict(runner, assetPath) {
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
