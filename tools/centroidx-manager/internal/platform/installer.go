package platform

import (
	"os"
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
// What needs it is publisherAnswer: a distinguished name is long enough to be
// wrapped, and a publisher that arrived across two lines has to compare equal to
// the same publisher that fitted on one, or an ordinary update would read as a
// conflict and uninstall a working HMI. Wrapping breaks at spaces, so collapsing
// restores the name exactly.
//
// The HRESULT matches would survive without it — the formatter cannot break
// inside a single short hex token — but they go through it too, because
// "normalise before matching output" is the rule this file wants and the next
// matcher added here may well be a phrase.
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

	// InstalledVersion reports the version of the currently installed
	// package, empty when none is installed or the platform cannot say. The
	// UI shows it next to "is installed", so a failed update reads as "still
	// on 2026.8.22" rather than as success.
	InstalledVersion() string

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
	cmd := exec.Command(name, args...)
	hideConsole(cmd)
	return cmd.CombinedOutput()
}

func (e execRunner) Start(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	hideConsole(cmd)
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
//
// -ErrorAction Stop makes a cmdlet error terminating, which stops the script
// before it can print a token — the same reason trustCertificateScript needs it,
// where a non-terminating error would skip the catch and emit the success token
// for an import that never happened. Here it would let the script run on to
// Write-Output with whatever $p ended up being, and a token is trusted precisely
// because only a successful query can print one.
//
// The token is what makes the query safe to read at all. The manager captures
// combined output, so a PowerShell error arrives on the same channel as the
// answer; without a token to look for, that error text would be taken for a
// publisher, and a "publisher" that matches nothing reads as a difference, which
// uninstalls. The dangerous direction is the one reached by doing nothing
// special, so neither of these is optional.
func installedPublisherCommand() string {
	return "$ErrorActionPreference='Stop'; " +
		"$p = Get-AppxPackage -Name '" + windowsPackageName + "' -ErrorAction Stop | " +
		"Select-Object -ExpandProperty Publisher; " +
		"if ($p) { Write-Output ('" + publisherTokenStart + "' + $p + '" + publisherTokenEnd + "') }"
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
		"$p=([xml]$r.ReadToEnd()).Package.Identity.Publisher; " +
		"if ($p) { Write-Output ('" + publisherTokenStart + "' + $p + '" + publisherTokenEnd + "') } } } " +
		"finally { if ($z) { $z.Dispose() } }"
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

// Tokens the publisher queries emit around their answer, on the same contract as
// the trust script's: the manager reads the value only from between them, and
// their absence means "could not tell", never an answer. Two adjacent functions
// in this file deciding success two different ways is how it got into trouble.
//
// A delimited pair rather than a single marker because this carries data, not a
// verdict: the value has no fixed length, so it needs an end as well as a start.
const (
	publisherTokenStart = "CENTROIDX_PUBLISHER["
	publisherTokenEnd   = "]END"
)

// publisherDNMarker is the one thing every Appx Publisher string has: it is an
// X.500 distinguished name, and a distinguished name has a common name. Ours
// ("CN=Centroid, O=Centroid ehf., C=IS"), the GUID one stations were installed
// under before it, and Microsoft's ("CN=Microsoft Corporation, O=..., C=US")
// all carry it -- which is what lets the conflict check compare two publishers
// without knowing either.
const publisherDNMarker = "CN="

// publisherAnswer runs a query and returns the publisher it reported, or "" for
// "could not tell". Everything that is not a complete, plausible answer is the
// latter — a PowerShell error that reached stdout, a warning, a half-written
// token, an empty result.
//
// The verdict comes from the script's own tokens, and the exit code is advisory,
// exactly as in trustCertificateWindows. Only our own Write-Output can produce
// the token pair, and it only runs with a publisher in hand, so a complete token
// is better evidence than a zero exit — while a non-zero exit with no token
// stays what it always was: no answer.
//
// The value is then checked for the shape of a publisher. That is not
// redundant with the token: if Select-Object ever stopped yielding a string, the
// token would faithfully wrap something like "System.Object[]", and an
// unrecognised string is not equal to the other publisher — so it would read as
// "the publishers differ" and uninstall a working HMI. The failure direction
// here is unforgiving enough to justify checking both.
//
// Whitespace is collapsed first so that a distinguished name the formatter
// wrapped across lines compares equal to the same name that fitted on one.
func publisherAnswer(runner CommandRunner, command string) string {
	out, _ := runner.Run("powershell", "-NoProfile", "-NonInteractive", "-Command", command)

	collapsed := collapseWhitespace(string(out))
	start := strings.Index(collapsed, publisherTokenStart)
	if start < 0 {
		return ""
	}
	rest := collapsed[start+len(publisherTokenStart):]
	end := strings.Index(rest, publisherTokenEnd)
	if end < 0 {
		return ""
	}
	answer := strings.TrimSpace(rest[:end])
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

	// Say what has to happen before Windows refuses it. Deployment replaces a
	// package only with a HIGHER version -- it never looks at content -- so an
	// operator moving from a stable install to a main build (0.year.month.run,
	// deliberately below every stable version) has to uninstall first. Left to
	// Add-AppxPackage that arrives as a bare HRESULT; read out of the package
	// beforehand it can be a sentence that says what to do.
	if msg := downgradeRefusal(runner, assetPath); msg != "" {
		return &commandError{op: msg, cause: errors.New("package version is not higher than the installed one")}
	}
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
	// Only HRESULTs are read out of the message; which cause a 0x80073CF3 is gets
	// decided by asking Windows, below. detail stays raw because it is what the
	// operator reads, and matching goes through the collapsed, lower-cased copy —
	// see collapseWhitespace for why that is the house rule even where a hex code
	// could not have been split.
	matchable := collapseWhitespace(strings.ToLower(detail))

	// "Already installed" is checked first and returns, so that it can never
	// reach the removal path below however the two texts evolve. Uninstalling
	// here would remove a working CentroidX to fix a problem removal does not
	// fix. See alreadyInstalledHRESULT.
	if strings.Contains(matchable, alreadyInstalledHRESULT) {
		return &commandError{
			op: "This build carries a version already installed, so Windows blocked the " +
				"reinstall (0x80073CFB) and left the installed CentroidX alone. Uninstall " +
				"CentroidX first, then install this build. (If that is unexpected, the release " +
				"was rebuilt without a version bump.) Detail: " + detail,
			cause: err,
		}
	}

	// Only a publisher conflict justifies uninstalling what is already on the
	// machine; every other failure is reported as-is. The HRESULT narrows the
	// failure to a bucket of three causes and publisherConflict picks the one
	// removal actually repairs — by querying Windows, not by parsing it.
	if strings.Contains(matchable, publisherConflictHRESULT) && publisherConflict(runner, assetPath) {
		// Removing the package takes its data container with it, and the
		// station keeps real work in there -- key mappings, the page layout,
		// the update channel, all written through SharedPreferences, which
		// under MSIX lands inside the container rather than in the profile.
		// A publisher change is the only thing that reaches this path, so
		// this is a one-time migration, but "one-time" is the whole plant.
		saved := savePackageData(runner)

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
		if saved {
			restorePackageData(runner)
		}
		return nil
	}

	if detail != "" {
		return &commandError{op: "Add-AppxPackage failed: " + detail, cause: err}
	}
	return &commandError{op: "Add-AppxPackage failed", cause: err}
}

// downgradeRefusal returns the sentence to show the operator when Windows
// would refuse this package for its version, or "" when the install can go
// ahead.
//
// Both halves are read rather than assumed: the version inside the .msix, and
// what Get-AppxPackage reports. If either cannot be read the install is
// attempted anyway -- guessing wrong here would block an install that would
// have worked, which is worse than the HRESULT it might produce.
func downgradeRefusal(runner CommandRunner, assetPath string) string {
	incoming, err := PackageVersionOf(assetPath)
	if err != nil || incoming == "" {
		return ""
	}
	out, err := runner.Run(
		"powershell", "-NoProfile", "-NonInteractive", "-Command",
		"Get-AppxPackage -Name '"+windowsPackageName+"' | Select-Object -ExpandProperty Version",
	)
	if err != nil {
		return ""
	}
	installed := strings.TrimSpace(string(out))
	if installed == "" {
		return "" // nothing installed: any version installs
	}

	switch ComparePackageVersions(incoming, installed) {
	case 1:
		return ""
	case 0:
		return "CentroidX " + installed + " is already installed, and this build carries " +
			"the same version number, so Windows will not replace it. Uninstall CentroidX " +
			"first, then install this build."
	default:
		return "CentroidX " + installed + " is installed and this build is " + incoming +
			", which Windows treats as older -- it only ever replaces a package with a " +
			"higher version. Uninstall CentroidX first, then install this build."
	}
}

// certStoreLocation is where a sideload signing certificate has to land.
// TrustedPeople is sufficient for MSIX sideloading and avoids the extra
// security dialog that LocalMachine\Root triggers. It has to be LocalMachine:
// Add-AppxPackage validates against machine-level trust, so the per-user
// Cert:\CurrentUser\TrustedPeople store is not a substitute even though the
// manager could write to it without elevation.
const certStoreLocation = `Cert:\LocalMachine\TrustedPeople`

// codesignStoreLocation is where the certificate our own executables are
// signed with has to land. Trusted Root, not TrustedPeople: TrustedPeople
// satisfies Windows' sideloading check for a package, but only a chain to a
// trusted root makes Windows name a publisher on an elevation prompt. Until
// the root is there, an operator approving an update is asked to approve
// something Windows calls "Unknown", which is exactly the moment we want them
// paying attention to the name.
const codesignStoreLocation = `Cert:\LocalMachine\Root`

// importCertificateCommand builds the PowerShell that imports certPath. It is
// also handed to the operator verbatim when the manager cannot run it itself,
// so the two can never drift apart.
func importCertificateCommand(certPath, store string) string {
	return `Import-Certificate -FilePath '` + certPath + `' -CertStoreLocation ` + store
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
	trustPresentToken  = "CENTROIDX_TRUST_PRESENT"
	trustAbsentToken   = "CENTROIDX_TRUST_ABSENT"
	trustDeclinedToken = "CENTROIDX_TRUST_DECLINED"
)

// certPresentScript answers, in our own vocabulary, whether the certificate
// at certPath is already in the machine store. Reading the store needs no
// rights, so this runs before any elevation is considered: on a station that
// was set up once, every later update passes here and no UAC prompt is ever
// shown.
func certPresentScript(certPath, store string) string {
	return `$t = (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 '` + certPath + `').Thumbprint; ` +
		`if (Test-Path ('` + store + `\' + $t)) { Write-Output '` + trustPresentToken + `' } ` +
		`else { Write-Output '` + trustAbsentToken + `' }`
}

// elevatedTrustScript re-runs the import in an elevated PowerShell, which
// shows the operator one UAC prompt. Declining it is a legitimate answer and
// gets its own token; everything else is judged afterwards by looking in the
// store, never by the elevated child's output (it runs in another console we
// cannot read).
func elevatedTrustScript(certPath string, stores []string) string {
	// Elevate the MANAGER, not PowerShell: the approval prompt then names
	// "CentroidX Version Manager", which is the program the operator just
	// started, instead of "Windows PowerShell", which looks like something
	// they did not ask for.
	self, err := os.Executable()
	if err != nil || self == "" {
		self = "powershell"
	}

	// One elevated run for every store that still needs the certificate:
	// the operator is asked once, not once per store. Which store the
	// elevated copy writes to travels as the flag it is given, so it cannot
	// import somewhere the caller did not ask for.
	var flags []string
	var direct []string
	for _, store := range stores {
		flag := "-trust-cert"
		if store == codesignStoreLocation {
			flag = "-trust-root"
		}
		flags = append(flags, `'`+flag+`','`+certPath+`'`)
		direct = append(direct, importCertificateCommand(certPath, store))
	}
	args := strings.Join(flags, ",")
	if self == "powershell" {
		args = `'-NoProfile','-NonInteractive','-Command','` + strings.Join(direct, "; ") + `'`
	}
	return `try { ` +
		`$p = Start-Process -FilePath '` + self + `' -Verb RunAs -Wait -PassThru -WindowStyle Hidden ` +
		`-ArgumentList ` + args + `; ` +
		`Write-Output ('CENTROIDX_ELEVATED_EXIT=' + $p.ExitCode) } ` +
		`catch { Write-Output '` + trustDeclinedToken + `'; Write-Output $_.Exception.Message }`
}

// certAlreadyTrusted reports whether the certificate is in the store.
// Unknown (script failed, no token) counts as not trusted, so the flow falls
// through to the import which produces the better diagnostics.
func certAlreadyTrusted(runner CommandRunner, certPath, store string) bool {
	out, err := runner.Run(
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		certPresentScript(certPath, store),
	)
	return err == nil && strings.Contains(strings.ToUpper(string(out)), trustPresentToken)
}

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
func trustCertificateScript(certPath, store string) string {
	return `$e = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); ` +
		`try { ` + importCertificateCommand(certPath, store) + ` -ErrorAction Stop ` + trustScriptSuccess + `; ` +
		`Write-Output '` + trustOKToken + `' } ` +
		`catch { Write-Output ('` + trustFailedToken + ` ELEVATED=' + $e.ToString().ToUpper()); ` +
		`Write-Output $_.Exception.Message; exit 1 }`
}

// ImportCertificateNow performs the import with no elevation attempt and no
// store check: it is what the elevated copy of the manager runs. Exported so
// main can route -trust-cert straight to it; going through
// trustCertificateWindows there would ask for elevation again from a process
// that already has it.
func ImportCertificateNow(certPath string) error {
	return importCertificateUnelevated(execRunner{}, certPath, certStoreLocation)
}

// ImportRootCertificateNow is the same for the code-signing certificate,
// which belongs in the root store -- see codesignStoreLocation. Routed from
// main's -trust-root, the flag the elevated copy of the manager is started
// with.
func ImportRootCertificateNow(certPath string) error {
	return importCertificateUnelevated(execRunner{}, certPath, codesignStoreLocation)
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
	// Two stores, one certificate: TrustedPeople is what makes Windows accept
	// the package, Root is what makes it name Centroid instead of "Unknown"
	// on the approval prompts an install and its updates raise. The same
	// certificate signs both, so both stores are filled in one go and the
	// operator is asked for approval once.
	return trustCertificateInStores(runner, certPath, certStoreLocation, codesignStoreLocation)
}

// trustCertificateInStores imports certPath into every store that does not
// already hold it, asking Windows for elevation at most once no matter how
// many stores are missing.
//
// The presence check runs first and needs no rights, so a station that was
// set up once never sees a prompt again on a routine update. What cannot be
// done unelevated is collected and handed to a single elevated run rather
// than elevating per store, because two consecutive UAC dialogs read as
// something going wrong.
func trustCertificateInStores(runner CommandRunner, certPath string, stores ...string) error {
	var missing []string
	for _, store := range stores {
		if !certAlreadyTrusted(runner, certPath, store) {
			missing = append(missing, store)
		}
	}
	if len(missing) == 0 {
		return nil
	}

	var needElevation []string
	var firstErr error
	for _, store := range missing {
		err := importCertificateUnelevated(runner, certPath, store)
		switch {
		case err == nil:
		case errors.Is(err, errNeedsElevation):
			needElevation = append(needElevation, store)
		case firstErr == nil:
			firstErr = err
		}
	}

	if len(needElevation) > 0 {
		if err := elevateTrust(runner, certPath, needElevation); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}

// errNeedsElevation marks the one failure elevation can repair. It is a
// sentinel rather than a message match because the message is Windows' and
// comes in whatever language the station runs.
var errNeedsElevation = errors.New("the machine certificate store needs administrator rights")

// elevateTrust runs one elevated import covering every store in stores, then
// believes only the store itself -- the elevated child runs in a console we
// cannot read, so its exit code says nothing we can rely on.
func elevateTrust(runner CommandRunner, certPath string, stores []string) error {
	elevOut, _ := runner.Run(
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		elevatedTrustScript(certPath, stores),
	)

	var stillMissing bool
	for _, store := range stores {
		if !certAlreadyTrusted(runner, certPath, store) {
			stillMissing = true
			break
		}
	}
	if !stillMissing {
		return nil
	}

	elevDetail := strings.TrimSpace(string(elevOut))
	if strings.Contains(strings.ToUpper(elevDetail), trustDeclinedToken) {
		return &commandError{
			op:    "Approval was declined, so the publisher is still not approved.",
			cause: errNeedsElevation,
		}
	}
	return &commandError{
		op:    "Approving the publisher failed: " + firstLine(elevDetail),
		cause: errNeedsElevation,
	}
}

// importCertificateUnelevated runs the import once, as this process. Rights
// are the one failure it reports as a sentinel instead of a message, so the
// caller can gather every store that needs the same single elevation.
func importCertificateUnelevated(runner CommandRunner, certPath, store string) error {
	out, err := runner.Run(
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		trustCertificateScript(certPath, store),
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
			return errNeedsElevation
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

// Tokens the data-migration scripts speak, for the same reason the trust
// scripts have their own: what Windows says depends on the locale a station
// runs, and nothing here may depend on that.
const (
	dataSavedToken    = "CENTROIDX_DATA_SAVED"
	dataNoneToken     = "CENTROIDX_DATA_NONE"
	dataRestoredToken = "CENTROIDX_DATA_RESTORED"
)

// packageDataBackupDir is where the container's contents wait between the
// uninstall and the install that replaces it. TEMP, not the container's own
// parent: the parent is deleted along with the package.
const packageDataBackupDir = `centroidx-package-data`

// savePackageDataScript copies the installed package's roaming data aside.
//
// Under MSIX a write to %APPDATA% is redirected into the package container,
// so everything the app saved through SharedPreferences lives at
// Packages\<family>\LocalCache\Roaming and dies with the package. The family
// name embeds a hash of the publisher, which is precisely what is changing,
// so it is read from Windows rather than assumed.
func savePackageDataScript() string {
	return `$ErrorActionPreference='Stop'; ` +
		`$p = Get-AppxPackage -Name '` + windowsPackageName + `'; ` +
		`if (-not $p) { Write-Output '` + dataNoneToken + `'; exit 0 }; ` +
		`$src = Join-Path $env:LOCALAPPDATA ('Packages\' + $p.PackageFamilyName + '\LocalCache\Roaming'); ` +
		`if (-not (Test-Path $src)) { Write-Output '` + dataNoneToken + `'; exit 0 }; ` +
		`$dst = Join-Path $env:TEMP '` + packageDataBackupDir + `'; ` +
		`if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }; ` +
		`Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force; ` +
		// Say saved only if something was actually written. A token that
		// reports a copy that did not happen is worse than no token: the
		// restore afterwards would find nothing and also say nothing.
		`if (@(Get-ChildItem -Recurse -File -LiteralPath $dst).Count -gt 0) { Write-Output '` + dataSavedToken + `' } ` +
		`else { Write-Output '` + dataNoneToken + `' }`
}

// restorePackageDataScript copies the saved data into the newly installed
// package's container.
//
// The saved copy wins (-Force): it is the station's real configuration, and
// the package it is being restored into is one that has just been installed
// and not yet launched, so anything already there is a default.
func restorePackageDataScript() string {
	return `$ErrorActionPreference='Stop'; ` +
		`$p = Get-AppxPackage -Name '` + windowsPackageName + `'; ` +
		`if (-not $p) { exit 0 }; ` +
		`$src = Join-Path $env:TEMP '` + packageDataBackupDir + `'; ` +
		`if (-not (Test-Path $src)) { exit 0 }; ` +
		`$dst = Join-Path $env:LOCALAPPDATA ('Packages\' + $p.PackageFamilyName + '\LocalCache\Roaming'); ` +
		`New-Item -ItemType Directory -Force -Path $dst | Out-Null; ` +
		// -Path, not -LiteralPath: the wildcard has to expand. -LiteralPath
		// takes it as a file actually named "*", finds nothing, and copies
		// nothing -- which is what this did until a simulated container
		// came out empty on the other side.
		`Copy-Item -Path (Join-Path $src '*') -Destination $dst -Recurse -Force; ` +
		// And the token is earned, not announced: an empty destination is a
		// station that just lost its settings, and it must not read as done.
		`if (@(Get-ChildItem -Recurse -File -LiteralPath $dst).Count -gt 0) { Write-Output '` + dataRestoredToken + `' }`
}

// savePackageData reports whether there is anything to put back afterwards.
// Failure is not fatal: the alternative to a station losing its local
// settings is a station that cannot install at all, which is worse.
func savePackageData(runner CommandRunner) bool {
	out, err := runner.Run(
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		savePackageDataScript(),
	)
	return err == nil && strings.Contains(string(out), dataSavedToken)
}

// restorePackageData puts the saved data into the new container.
func restorePackageData(runner CommandRunner) bool {
	out, err := runner.Run(
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		restorePackageDataScript(),
	)
	return err == nil && strings.Contains(string(out), dataRestoredToken)
}

// windowsPackageName is the MSIX identity name from centroid-hmi's msix_config.
const windowsPackageName = "Centroid.CentroidX"

// sideloadPublisherCN is the subject of the certificate releases are signed
// with (centroid-hmi/pubspec.yaml, msix_config.publisher). Used to ask the
// machine store whether this station already trusts us.
//
// It was a GUID until the publisher became a name -- a package publisher has
// to equal the certificate subject exactly, and the GUID was what Windows
// read out on every approval prompt. TestPublisherMatchesPubspec keeps this
// and the pubspec from drifting apart; drift would mean a station reporting
// that it trusts nothing while the certificate sits in the store.
const sideloadPublisherCN = "CN=Centroid, O=Centroid ehf., C=IS"

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

// firstLine keeps an error to its first line: the rest of a PowerShell error
// record is the script that produced it, which an operator has no use for.
func firstLine(s string) string {
	if i := strings.IndexAny(s, "\r\n"); i >= 0 {
		return strings.TrimSpace(s[:i])
	}
	return strings.TrimSpace(s)
}
