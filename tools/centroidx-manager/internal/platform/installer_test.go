package platform

import (
	"errors"
	"strings"
	"testing"
)

// mockRunner records every Run call and optionally returns an error.
type mockRunner struct {
	calls  []mockCall
	errOn  int // 0 = never error, n = error on nth call (1-based)
	callN  int
	retErr error
	// started records Start calls separately from Run calls. Launching the app
	// must not block on it, so which of the two a launch used is the thing
	// under test — not merely that some command was issued.
	started  []mockCall
	startErr error
}

type mockCall struct {
	name string
	args []string
}

func (m *mockRunner) Run(name string, args ...string) ([]byte, error) {
	m.callN++
	m.calls = append(m.calls, mockCall{name: name, args: args})
	if m.errOn > 0 && m.callN == m.errOn {
		return nil, m.retErr
	}
	return nil, nil
}

func (m *mockRunner) Start(name string, args ...string) error {
	m.started = append(m.started, mockCall{name: name, args: args})
	return m.startErr
}

// hasArg returns true if any element of args equals v.
func hasArg(args []string, v string) bool {
	for _, a := range args {
		if a == v {
			return true
		}
	}
	return false
}

// hasArgContaining returns true if any element of args contains substr.
func hasArgContaining(args []string, substr string) bool {
	for _, a := range args {
		if strings.Contains(a, substr) {
			return true
		}
	}
	return false
}

// allArgs returns a single slice combining call.name and call.args.
func allArgs(c mockCall) []string {
	return append([]string{c.name}, c.args...)
}

// ---- Windows installer tests ------------------------------------------------

func TestWindowsInstaller_Install(t *testing.T) {
	runner := &mockRunner{}
	if err := installWindows(runner, "/tmp/app.msix"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) == 0 {
		t.Fatal("no commands were recorded")
	}
	call := runner.calls[0]
	all := allArgs(call)
	if !hasArg(all, "powershell") {
		t.Errorf("expected 'powershell' in command, got: %v", all)
	}
	if !hasArgContaining(all, "Add-AppxPackage") {
		t.Errorf("expected 'Add-AppxPackage' in command args, got: %v", all)
	}
	if !hasArgContaining(all, "-ForceApplicationShutdown") {
		t.Errorf("expected '-ForceApplicationShutdown' in command args, got: %v", all)
	}
	if !hasArgContaining(all, "app.msix") {
		t.Errorf("expected asset path in command args, got: %v", all)
	}
}

func TestWindowsInstaller_TrustCertificate(t *testing.T) {
	// The runner has to report the success token: silence no longer means
	// success, which is the point of the change this test now sits on top of.
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte(trustOKToken)}, errors: []error{nil}}
	if err := trustCertificateWindows(runner, "/tmp/cert.cer"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) == 0 {
		t.Fatal("no commands were recorded")
	}
	call := runner.calls[0]
	all := allArgs(call)
	if !hasArg(all, "powershell") {
		t.Errorf("expected 'powershell' in command, got: %v", all)
	}
	if !hasArgContaining(all, "Import-Certificate") {
		t.Errorf("expected 'Import-Certificate' in command args, got: %v", all)
	}
	if !hasArgContaining(all, "TrustedPeople") {
		t.Errorf("expected 'TrustedPeople' in command args, got: %v", all)
	}
	// Must be the machine store. Add-AppxPackage validates sideload signatures
	// against machine-level trust, so Cert:\CurrentUser\TrustedPeople would
	// still contain "TrustedPeople" while silently not working.
	if !hasArgContaining(all, `Cert:\LocalMachine\TrustedPeople`) {
		t.Errorf("expected the machine-level TrustedPeople store, got: %v", all)
	}
	if !hasArgContaining(all, "/tmp/cert.cer") {
		t.Errorf("expected cert path in command args, got: %v", all)
	}
}

// ---- certificate trust -----------------------------------------------------
//
// These assert on tokens the manager itself emits, never on Windows prose.
// The station locales are mixed and unknown, so any English phrase we matched
// would be unreliable in production while passing every test here — the same
// way a wrong constant passed every test until someone read the generator.

func TestWindowsInstaller_TrustCertificate_SucceedsOnOKToken(t *testing.T) {
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte("CENTROIDX_TRUST_OK\r\n")}, errors: []error{nil}}
	if err := trustCertificateWindows(runner, `C:\tmp\centroidx.cer`); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

// The whole point: elevation is read from a boolean the OS answered, so the
// guidance is identical whatever language Windows reports the failure in.
func TestWindowsInstaller_TrustCertificate_UnelevatedIsReportedInAnyLanguage(t *testing.T) {
	cases := []struct{ name, body string }{
		{"english", "Import-Certificate : Access is denied."},
		{"icelandic", "Import-Certificate : Aðgangi er hafnað."},
		{"italian", "Import-Certificate : Accesso negato."},
		{"empty", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			out := "CENTROIDX_TRUST_FAILED ELEVATED=FALSE\r\n" + tc.body
			runner := &mockRunnerSeq{outputs: [][]byte{[]byte(out)}, errors: []error{errors.New("exit status 1")}}

			err := trustCertificateWindows(runner, `C:\tmp\centroidx.cer`)
			if err == nil {
				t.Fatal("expected an error, got nil")
			}
			if !strings.Contains(err.Error(), "administrator") {
				t.Errorf("expected the error to name elevation, got: %v", err)
			}
			if !strings.Contains(err.Error(), "Import-Certificate -FilePath") {
				t.Errorf("expected the one-time remediation command, got: %v", err)
			}
			if !strings.Contains(err.Error(), `C:\tmp\centroidx.cer`) {
				t.Errorf("expected the cert path in the remediation command, got: %v", err)
			}
		})
	}
}

// An elevated manager that still fails has a different problem, and saying
// "run as administrator" to someone who already is wastes their time.
func TestWindowsInstaller_TrustCertificate_ElevatedFailureIsNotBlamedOnAdmin(t *testing.T) {
	out := "CENTROIDX_TRUST_FAILED ELEVATED=TRUE\r\nImport-Certificate : Cannot find path 'C:\\tmp\\centroidx.cer'."
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte(out)}, errors: []error{errors.New("exit status 1")}}

	err := trustCertificateWindows(runner, `C:\tmp\centroidx.cer`)
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if strings.Contains(err.Error(), "administrator") {
		t.Errorf("an elevated failure was blamed on elevation: %v", err)
	}
	if !strings.Contains(err.Error(), "Cannot find path") {
		t.Errorf("expected the underlying detail, got: %v", err)
	}
}

// If neither token is present we do not know what happened, and the one thing
// we must not do is call it success — the engine treats trust as non-fatal, so
// a false success is silent and permanent.
func TestWindowsInstaller_TrustCertificate_UnrecognisedOutputIsNotSuccess(t *testing.T) {
	for _, tc := range []struct {
		name string
		out  string
		err  error
	}{
		{"garbage, exit 0", "the term 'Import-Certificate' is not recognized", nil},
		{"empty, exit 0", "", nil},
		{"garbage, exit 1", "something else entirely", errors.New("exit status 1")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			runner := &mockRunnerSeq{outputs: [][]byte{[]byte(tc.out)}, errors: []error{tc.err}}
			if err := trustCertificateWindows(runner, `C:\tmp\centroidx.cer`); err == nil {
				t.Fatal("unrecognised output was treated as a successful trust")
			}
		})
	}
}

// The script must ask Windows for the elevation boolean, and must make the
// cmdlet error terminating so the catch fires — otherwise both tokens could be
// emitted, or neither.
func TestWindowsInstaller_TrustCertificate_AsksWindowsForElevation(t *testing.T) {
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte("CENTROIDX_TRUST_OK")}, errors: []error{nil}}
	_ = trustCertificateWindows(runner, `C:\tmp\centroidx.cer`)

	all := allArgs(runner.calls[0])
	for _, want := range []string{"IsInRole", "WindowsBuiltInRole", "-ErrorAction Stop", "CENTROIDX_TRUST_OK", "CENTROIDX_TRUST_FAILED"} {
		if !hasArgContaining(all, want) {
			t.Errorf("expected %q in the script, got: %v", want, all)
		}
	}
}

func TestWindowsInstaller_Install_Error(t *testing.T) {
	runner := &mockRunner{
		errOn:  1,
		retErr: errors.New("exit status 1"),
	}
	err := installWindows(runner, "/tmp/app.msix")
	if err == nil {
		t.Fatal("expected error, got nil")
	}
	if !strings.Contains(err.Error(), "Add-AppxPackage failed") {
		t.Errorf("expected error to contain 'Add-AppxPackage failed', got: %v", err)
	}
}

// countRemoveAppxCalls counts how many recorded commands would uninstall the
// package. Removing a working installation is the destructive step, so tests
// assert on it directly rather than on call counts alone.
func countRemoveAppxCalls(calls []mockCall) int {
	n := 0
	for _, c := range calls {
		if hasArgContaining(allArgs(c), "Remove-AppxPackage") {
			n++
		}
	}
	return n
}

// Windows prefixes essentially every deployment error with "Deployment failed
// with HRESULT: 0x...", so that phrase says nothing about *why* an install
// failed. Treating it as a publisher-conflict signal uninstalls a working
// CentroidX on any failure — a rejected certificate, a full disk, a bad
// download — and the retry then fails for the same reason, leaving the rig
// with no application at all. None of these may remove anything.
func TestWindowsInstaller_Install_NonConflictFailureKeepsInstalledPackage(t *testing.T) {
	cases := []struct {
		name   string
		output string
	}{
		{
			"untrusted certificate",
			"Add-AppxPackage : Deployment failed with HRESULT: 0x800B0109, A certificate chain " +
				"processed, but terminated in a root certificate which is not trusted by the trust provider.",
		},
		{
			"out of disk space",
			"Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF4, Windows cannot install " +
				"package Centroid.CentroidX because there is not enough disk space.",
		},
		{
			"network failure",
			"Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF5, Windows cannot install " +
				"package Centroid.CentroidX because it requires a network resource that is unavailable.",
		},
		{
			"generic install failure",
			"Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF9, Install failed. " +
				"Please contact your software vendor.",
		},
		{
			"package could not be opened",
			"Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF0, The package could not be opened.",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			// Whatever the cause, it is still there on a second attempt: an
			// untrusted certificate is still untrusted, a full disk is still
			// full. The third entry is only reached if the installer wrongly
			// removes the package and retries.
			runner := &mockRunnerSeq{
				outputs: [][]byte{[]byte(tc.output), nil, []byte(tc.output)},
				errors:  []error{errors.New("exit status 1"), nil, errors.New("exit status 1")},
			}

			err := installWindows(runner, "/tmp/app.msix")
			if err == nil {
				t.Fatal("expected an error, got nil")
			}
			if n := countRemoveAppxCalls(runner.calls); n != 0 {
				t.Errorf("a non-conflict failure uninstalled the working package (%d Remove-AppxPackage call(s)); calls: %v", n, runner.calls)
			}
			if len(runner.calls) != 1 {
				t.Errorf("expected the install to stop after one attempt, got %d calls: %v", len(runner.calls), runner.calls)
			}
		})
	}
}

// The operator has to be able to tell a certificate rejection from anything
// else, so the HRESULT and its text must survive into the returned error.
func TestWindowsInstaller_Install_UntrustedCertReportsHRESULT(t *testing.T) {
	const detail = "Add-AppxPackage : Deployment failed with HRESULT: 0x800B0109, A certificate chain " +
		"processed, but terminated in a root certificate which is not trusted by the trust provider."
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(detail), nil, []byte(detail)},
		errors:  []error{errors.New("exit status 1"), nil, errors.New("exit status 1")},
	}

	err := installWindows(runner, "/tmp/app.msix")
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if !strings.Contains(err.Error(), "0x800B0109") {
		t.Errorf("expected the HRESULT in the error, got: %v", err)
	}
	if strings.Contains(err.Error(), "after removing conflict") {
		t.Errorf("a certificate rejection was reported as a conflict: %v", err)
	}
}

// ---- Recorded Windows output ------------------------------------------------
//
// Every fixture below is a message Windows actually emitted, copied from a
// traced source rather than composed to fit the matcher. Matching text produced
// outside this repo against a plausible-looking guess is what put the wrong
// HRESULT in installWindows in the first place: the constant said
// ERROR_PACKAGE_ALREADY_EXISTS and the fixture agreed with it, because both came
// from the same assumption.
//
// The package names in these are the reporters', not ours. That is deliberate —
// the matcher looks only at the HRESULT and at Windows' own sentence, neither of
// which depends on which package failed.

// conflictFliteDeck is a complete Add-AppxPackage failure line for the identity
// conflict, quoted in Jeppesen's support note for FliteDeck Pro X and in
// microsoft/winget-cli#4752. The two package full names differ only in their
// trailing PublisherId hash.
const conflictFliteDeck = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF3, Package failed " +
	"updates, dependency or conflict validation. Windows cannot install package " +
	"Jeppesen.FliteDeck_10.3.1.10593_neutral_~_8gk7v4trkh4pt because a different package " +
	"Jeppesen.FliteDeck_10.2.1.9678_neutral_~_g4095tshxnsa8 with the same name is already installed."

// conflictRepublished is the same failure reproduced deliberately in
// microsoft/WindowsAppSDK#650 by changing nothing but the manifest Publisher
// string: PublisherId 0rxggyxen88sc becomes 6jx1svrqfke3r and the install is
// rejected. This is the CentroidX case — a rig moving between Store and
// sideload signing — and it is the evidence that 0x80073CF3, not 0x80073CFB, is
// the publisher conflict.
// https://github.com/microsoft/WindowsAppSDK/issues/650
const conflictRepublished = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073cf3, Package failed " +
	"updates, dependency or conflict validation. Windows cannot install package " +
	"MyPackageName_1.0.7.0_neutral_~_6jx1svrqfke3r because a different package " +
	"MyPackageName_1.0.6.0_neutral_~_0rxggyxen88sc with the same name is already installed."

// alreadyInstalled is what Windows says for ERROR_PACKAGE_ALREADY_EXISTS,
// quoted in microsoft/WindowsAppSDK#1871 and matching the description Microsoft
// documents for 0x80073CFB. Note what it does *not* say: nothing about a
// publisher, and nothing about a different package. It means the package on the
// machine is not bitwise identical to the one being installed — a rebuild or a
// re-sign at an unchanged version — and the installed copy is working.
// https://github.com/microsoft/WindowsAppSDK/issues/1871
// https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting
const alreadyInstalled = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073CFB, The provided package " +
	"is already installed, and reinstallation of the package was blocked. Check the " +
	"AppXDeployment-Server event log for details."

// conflictWrapped is a conflict as PowerShell actually delivers it: rendered
// through the formatter, wrapped to the 120-column default that applies when no
// console is attached, continuations indented. The wrap falls between "already"
// and "installed.", splitting publisherConflictSignal in half — which is why
// installWindows matches a whitespace-collapsed copy and never the raw bytes.
//
// Two recordings joined, no invented text: the deployment line is Windows' own
// as quoted for FliteDeck above, and the package names and conflict sentence are
// the Windows App Certification Kit failure recorded at
// stegriff.co.uk/upblog/windows-app-certification-kit-cannot-install-package/
// (also MSDN forum 67b1a081). No single published recording shows both the
// HRESULT line and names long enough to reach the wrap, because where the wrap
// bites is purely a function of package-name length — with the FliteDeck names
// the phrase survives on one line, with these it does not. Which recording it
// happens to hit is luck, and luck is what this test removes.
const conflictWrapped = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF3, Package failed updates, dependency or conflict validation.\n" +
	"    Windows cannot install package 780a2c2f-f4be-4a7d-83bf-212522026da9_1.0.0.0_neutral_~_m56gs6vrxbyza because a\n" +
	"    different package 780a2c2f-f4be-4a7d-83bf-212522026da9_1.0.0.0_x64__gf73qhakswkrp with the same name is already\n" +
	"    installed."

// conflictLocalised is the same conflict on a non-English Windows, and the
// reason the structural arm exists: an Icelandic plant station running a
// localised Windows would otherwise never recover, while passing every English
// test in this file.
//
// The body is verbatim Italian from microsoft/winget-cli#4752 — winget drives
// the same deployment API, and its log records the failure as 0x80073CF3. The
// "Add-AppxPackage : Deployment failed with HRESULT:" prefix is ours: no
// verbatim localised copy of PowerShell's wrapper line turned up, and the
// wrapper is not what this fixture tests. What must not be faked is the text
// under test — the sentence the matcher has to cope with not understanding —
// and that is Windows', unaltered.
const conflictLocalised = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF3, Convalida degli aggiornamenti, " +
	"delle dipendenze e dei conflitti del pacchetto non eseguita. Impossibile installare il pacchetto " +
	"Mozilla.MozillaFirefox_129.0.2.0_x64__jag0gd4e3s9p2. È già installato un pacchetto " +
	"Mozilla.MozillaFirefox_126.0.1.0_x64__gmpnhwe7bv608 diverso con lo stesso nome. Prima di eseguire " +
	"l'installazione, rimuovere il pacchetto Mozilla.MozillaFirefox_126.0.1.0_x64__gmpnhwe7bv608."

// missingDependency is 0x80073CF3 for a cause removal cannot fix, quoted in
// WSA-Community/WSAGAScript#293. Microsoft documents the code as covering three
// causes — conflict, missing dependency, wrong processor architecture — so the
// HRESULT alone must never trigger the uninstall. Note that this text names a
// publisher ("published by 'CN=Microsoft Corporation, ...'"), so looking for the
// word "publisher" would not have separated it either.
//
// No verbatim recording of the wrong-architecture variant turned up, so it is
// not asserted here rather than invented.
const missingDependency = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF3, Package failed " +
	"updates, dependency or conflict validation. Windows cannot install package " +
	"Microsoft.Lovika_1.17.0.0_x64__8wekyb3d8bbwe because this package depends on a framework " +
	"that could not be found. Provide the framework 'Microsoft.DirectXRuntime' published by " +
	"'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US', with " +
	"neutral or x64 processor architecture and minimum version 9.29.952.0, along with this " +
	"package to install."

// The genuine publisher conflict — same package name, different PublisherId
// because the signing identity changed — is the one case where removing the
// installed package is the fix.
func TestWindowsInstaller_Install_PublisherConflictRemovesAndRetries(t *testing.T) {
	// Both spellings of the HRESULT appear in the wild; the second fixture is
	// lower case, which also covers the case-insensitive match.
	for _, tc := range []struct {
		name   string
		output string
	}{
		{"different package with the same name", conflictFliteDeck},
		{"republished under a different signing identity", conflictRepublished},
		// The formatter split publisherConflictSignal across a line break.
		{"wrapped by the PowerShell formatter", conflictWrapped},
		// No English sentence at all; only the structural arm can see this one.
		{"reported by a localised Windows", conflictLocalised},
	} {
		t.Run(tc.name, func(t *testing.T) {
			runner := &mockRunnerSeq{
				outputs: [][]byte{[]byte(tc.output), nil, nil},
				errors:  []error{errors.New("exit status 1"), nil, nil},
			}

			if err := installWindows(runner, "/tmp/app.msix"); err != nil {
				t.Fatalf("expected the retry to succeed, got: %v", err)
			}
			if len(runner.calls) != 3 {
				t.Fatalf("expected install, remove, install; got %d calls: %v", len(runner.calls), runner.calls)
			}
			if !hasArgContaining(allArgs(runner.calls[0]), "Add-AppxPackage") {
				t.Errorf("call 0: expected Add-AppxPackage, got: %v", allArgs(runner.calls[0]))
			}
			if !hasArgContaining(allArgs(runner.calls[1]), "Remove-AppxPackage") {
				t.Errorf("call 1: expected Remove-AppxPackage, got: %v", allArgs(runner.calls[1]))
			}
			if !hasArgContaining(allArgs(runner.calls[1]), "Centroid.CentroidX") {
				t.Errorf("call 1: expected the removal scoped to Centroid.CentroidX, got: %v", allArgs(runner.calls[1]))
			}
			if !hasArgContaining(allArgs(runner.calls[2]), "Add-AppxPackage") {
				t.Errorf("call 2: expected the install retry, got: %v", allArgs(runner.calls[2]))
			}
		})
	}
}

// isPublisherConflict has two independent arms, and a table over the recorded
// messages is the only place their division of labour is visible. Each row
// states which arm carries which real failure, so breaking either arm fails
// here and says which one broke.
func TestPublisherConflictArms(t *testing.T) {
	for _, tc := range []struct {
		name      string
		output    string
		sentence  bool // publisherConflictSignal, Windows' English wording
		structure bool // two package full names, one Name, two PublisherIds
	}{
		{"conflict, FliteDeck", conflictFliteDeck, true, true},
		{"conflict, republished (WindowsAppSDK#650)", conflictRepublished, true, true},
		{"conflict, wrapped by the formatter", conflictWrapped, true, true},
		// The row that justifies the structural arm: Windows said it in
		// Italian, so the sentence arm is blind and the structure is not.
		{"conflict, localised", conflictLocalised, false, true},
		// And the rows that keep both arms honest — same HRESULT for the
		// first, and neither may be mistaken for a conflict.
		{"missing dependency", missingDependency, false, false},
		{"already installed", alreadyInstalled, false, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			matchable := collapseWhitespace(strings.ToLower(tc.output))
			if got := strings.Contains(matchable, publisherConflictSignal); got != tc.sentence {
				t.Errorf("sentence arm = %v, want %v", got, tc.sentence)
			}
			if got := hasConflictingPublisherIDs(matchable); got != tc.structure {
				t.Errorf("structural arm = %v, want %v", got, tc.structure)
			}
			if got := isPublisherConflict(matchable); got != (tc.sentence || tc.structure) {
				t.Errorf("isPublisherConflict = %v, want %v", got, tc.sentence || tc.structure)
			}
		})
	}
}

// The sentence arm only works because the output is collapsed first. On the raw
// bytes PowerShell hands back, the formatter's line break sits inside the
// phrase and the match silently misses — which is the whole defect this file is
// about, reached by a different route.
func TestPublisherConflictSentenceNeedsCollapsedWhitespace(t *testing.T) {
	raw := strings.ToLower(conflictWrapped)
	if strings.Contains(raw, publisherConflictSignal) {
		t.Fatal("the fixture is not actually wrapped through the phrase; it cannot prove anything")
	}
	if !strings.Contains(collapseWhitespace(raw), publisherConflictSignal) {
		t.Error("collapsing whitespace did not rejoin the phrase the formatter split")
	}
}

// The structural arm keys on two package full names that share an identity Name
// and differ in the trailing PublisherId. One name is not a conflict however
// much else the message says, or a missing dependency would take the removal
// path in every locale.
func TestConflictingPublisherIDs_NeedsTwoNamesUnderOneIdentity(t *testing.T) {
	for _, tc := range []struct {
		name string
		text string
		want bool
	}{
		{"one package named", missingDependency, false},
		{"two names, two publisher ids", conflictFliteDeck, true},
		{
			// A package updating itself normally: same Name, same
			// PublisherId, different version. Not a conflict.
			"same publisher id, different version",
			"windows cannot install package jeppesen.flitedeck_10.3.1.10593_neutral_~_8gk7v4trkh4pt " +
				"over jeppesen.flitedeck_10.2.1.9678_neutral_~_8gk7v4trkh4pt.",
			false,
		},
		{
			// Two unrelated packages, each mentioned once. Different Names,
			// so nothing here says one is displacing the other.
			"different names, different publisher ids",
			"windows cannot install package contoso.one_1.0.0.0_x64__8gk7v4trkh4pt because " +
				"fabrikam.two_2.0.0.0_x64__g4095tshxnsa8 is in the way.",
			false,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := hasConflictingPublisherIDs(collapseWhitespace(strings.ToLower(tc.text)))
			if got != tc.want {
				t.Errorf("hasConflictingPublisherIDs = %v, want %v", got, tc.want)
			}
		})
	}
}

// The regression that matters. ERROR_PACKAGE_ALREADY_EXISTS means a working
// CentroidX at this very version is on the machine and Windows will not
// overwrite it. Removing it to retry gambles the whole installation on a retry
// that fixes nothing, and if that retry fails — Defender holding a file, a full
// disk, a payload already deleted — the station is left with no application.
// PR #290 bound the uninstall to exactly this code; nothing may put it back.
func TestWindowsInstaller_Install_AlreadyInstalledKeepsInstalledPackage(t *testing.T) {
	// A third response is supplied so that a wrongly-taken removal path would
	// run to completion and be visible in the call log, rather than erroring
	// out for an unrelated reason.
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(alreadyInstalled), nil, nil},
		errors:  []error{errors.New("exit status 1"), nil, nil},
	}

	err := installWindows(runner, "/tmp/app.msix")
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if n := countRemoveAppxCalls(runner.calls); n != 0 {
		t.Errorf("an already-installed package was uninstalled (%d Remove-AppxPackage call(s)); calls: %v", n, runner.calls)
	}
	if len(runner.calls) != 1 {
		t.Errorf("expected the install to stop after one attempt, got %d calls: %v", len(runner.calls), runner.calls)
	}
	if strings.Contains(err.Error(), "after removing conflict") {
		t.Errorf("an already-installed package was reported as a publisher conflict: %v", err)
	}
	// The operator has to be able to act on this: it is a release cut twice
	// under one version number, not something to retry on the rig.
	if !strings.Contains(err.Error(), "0x80073CFB") {
		t.Errorf("expected the HRESULT in the error, got: %v", err)
	}
	if !strings.Contains(err.Error(), "left alone") {
		t.Errorf("expected the error to say the installation was kept, got: %v", err)
	}
}

// 0x80073CF3 is a bucket code. A missing framework dependency reports it too,
// and uninstalling CentroidX does not conjure the framework — it just removes
// the application. Only Windows' conflict sentence may open the removal path.
func TestWindowsInstaller_Install_DependencyFailureKeepsInstalledPackage(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(missingDependency), nil, []byte(missingDependency)},
		errors:  []error{errors.New("exit status 1"), nil, errors.New("exit status 1")},
	}

	err := installWindows(runner, "/tmp/app.msix")
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if n := countRemoveAppxCalls(runner.calls); n != 0 {
		t.Errorf("a missing dependency uninstalled the working package (%d Remove-AppxPackage call(s)); calls: %v", n, runner.calls)
	}
	if len(runner.calls) != 1 {
		t.Errorf("expected the install to stop after one attempt, got %d calls: %v", len(runner.calls), runner.calls)
	}
	if !strings.Contains(err.Error(), "Microsoft.DirectXRuntime") {
		t.Errorf("expected the missing framework named in the error, got: %v", err)
	}
}

// When the retry after a conflict removal also fails, the error must say so —
// this is the state where the machine has no CentroidX installed and the
// message is all the operator has to go on.
func TestWindowsInstaller_Install_PublisherConflictRetryFailure(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{
			[]byte(conflictFliteDeck),
			nil,
			[]byte("Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF9, Install failed. " +
				"Please contact your software vendor."),
		},
		errors: []error{errors.New("exit status 1"), nil, errors.New("exit status 1")},
	}

	err := installWindows(runner, "/tmp/app.msix")
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if !strings.Contains(err.Error(), "after removing conflict") {
		t.Errorf("expected the error to name the retry, got: %v", err)
	}
	if !strings.Contains(err.Error(), "0x80073CF9") {
		t.Errorf("expected the retry's HRESULT in the error, got: %v", err)
	}
}

// ---- Linux installer tests --------------------------------------------------

func TestLinuxInstaller_Install(t *testing.T) {
	runner := &mockRunner{}
	if err := installLinux(runner, "/tmp/app.deb"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) == 0 {
		t.Fatal("no commands were recorded")
	}
	call := runner.calls[0]
	all := allArgs(call)
	// Elevator is either pkexec or sudo depending on PATH; check for dpkg.
	hasPkexec := hasArg(all, "pkexec")
	hasSudo := hasArg(all, "sudo")
	if !hasPkexec && !hasSudo {
		t.Errorf("expected 'pkexec' or 'sudo' in command, got: %v", all)
	}
	if !hasArg(all, "dpkg") {
		t.Errorf("expected 'dpkg' in command args, got: %v", all)
	}
	if !hasArg(all, "-i") {
		t.Errorf("expected '-i' in command args, got: %v", all)
	}
	if !hasArg(all, "/tmp/app.deb") {
		t.Errorf("expected asset path in command args, got: %v", all)
	}
}

// ---- Darwin installer tests -------------------------------------------------

// mockRunnerSeq lets each Run call return different data.
type mockRunnerSeq struct {
	calls    []mockCall
	outputs  [][]byte
	errors   []error
	started  []mockCall
	startErr error
}

func (m *mockRunnerSeq) Start(name string, args ...string) error {
	m.started = append(m.started, mockCall{name: name, args: args})
	return m.startErr
}

func (m *mockRunnerSeq) Run(name string, args ...string) ([]byte, error) {
	idx := len(m.calls)
	m.calls = append(m.calls, mockCall{name: name, args: args})
	var out []byte
	var err error
	if idx < len(m.outputs) {
		out = m.outputs[idx]
	}
	if idx < len(m.errors) {
		err = m.errors[idx]
	}
	return out, err
}

func TestDarwinInstaller_Install(t *testing.T) {
	// Sequence: hdiutil attach → rm old bundle → cp → xattr → detach (deferred)
	runner := &mockRunnerSeq{
		outputs: [][]byte{
			[]byte(`<string>/Volumes/CentroidX</string>`), // hdiutil output
			nil, // rm -rf old bundle
			nil, // cp
			nil, // xattr
			nil, // hdiutil detach (deferred)
		},
		errors: []error{nil, nil, nil, nil, nil},
	}

	if err := installDarwin(runner, "/tmp/app.dmg"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(runner.calls) < 4 {
		t.Fatalf("expected at least 4 calls, got %d: %v", len(runner.calls), runner.calls)
	}

	// Call 0: hdiutil attach
	call0 := allArgs(runner.calls[0])
	if !hasArg(call0, "hdiutil") {
		t.Errorf("call 0: expected 'hdiutil', got: %v", call0)
	}
	if !hasArg(call0, "attach") {
		t.Errorf("call 0: expected 'attach', got: %v", call0)
	}

	// Call 1: rm -rf of the old bundle — cp -R onto an existing .app merges
	// instead of replacing, leaving stale files that break the code signature.
	call1 := allArgs(runner.calls[1])
	if !hasArg(call1, "rm") {
		t.Errorf("call 1: expected 'rm', got: %v", call1)
	}
	if !hasArgContaining(call1, "/Applications/CentroidX.app") {
		t.Errorf("call 1: expected old bundle path in args, got: %v", call1)
	}

	// Call 2: cp to /Applications/
	call2 := allArgs(runner.calls[2])
	if !hasArg(call2, "cp") {
		t.Errorf("call 2: expected 'cp', got: %v", call2)
	}
	if !hasArgContaining(call2, "/Applications/") {
		t.Errorf("call 2: expected '/Applications/' in args, got: %v", call2)
	}

	// Call 3: xattr
	call3 := allArgs(runner.calls[3])
	if !hasArg(call3, "xattr") {
		t.Errorf("call 3: expected 'xattr', got: %v", call3)
	}
	if !hasArgContaining(call3, "com.apple.quarantine") {
		t.Errorf("call 3: expected 'com.apple.quarantine' in args, got: %v", call3)
	}
}

func TestDarwinInstaller_Install_CleanupOnError(t *testing.T) {
	// hdiutil attach succeeds, cp fails — detach must still be called
	runner := &mockRunnerSeq{
		outputs: [][]byte{
			[]byte(`<string>/Volumes/CentroidX</string>`), // hdiutil attach
			nil, // rm -rf old bundle
			nil, // cp (will error)
			nil, // hdiutil detach (deferred)
		},
		errors: []error{
			nil,                                 // hdiutil attach succeeds
			nil,                                 // rm -rf succeeds
			errors.New("cp: permission denied"), // cp fails
			nil,                                 // hdiutil detach succeeds
		},
	}

	err := installDarwin(runner, "/tmp/app.dmg")
	if err == nil {
		t.Fatal("expected error from cp failure, got nil")
	}

	// Find hdiutil detach call
	detachFound := false
	for _, c := range runner.calls {
		all := allArgs(c)
		if hasArg(all, "hdiutil") && hasArg(all, "detach") {
			detachFound = true
			break
		}
	}
	if !detachFound {
		t.Errorf("expected hdiutil detach to be called on cp error; calls: %v", runner.calls)
	}
}

// ---- LaunchApp tests --------------------------------------------------------

func TestInstaller_LaunchApp(t *testing.T) {
	runner := &mockRunner{}
	err := launchAppDetached(runner, "/Applications/CentroidX.app/Contents/MacOS/centroidx")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.started) == 0 {
		t.Fatal("no command was started")
	}
	call := runner.started[0]
	if call.name != "/Applications/CentroidX.app/Contents/MacOS/centroidx" {
		t.Errorf("expected app path as command, got: %v", call.name)
	}
}

// The launch must not wait for the app to exit. runner.Run buffers the child's
// output until it terminates, so launching the HMI through it pins the manager
// open for the HMI's entire lifetime — on Linux the update never reports
// finished. Only Windows escaped that, and only because it was launching
// explorer.exe, which returns immediately (see the AppsFolder test below).
func TestInstaller_LaunchApp_DoesNotWaitForTheApp(t *testing.T) {
	runner := &mockRunner{}
	if err := launchAppDetached(runner, "/opt/centroidx/centroidx"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) != 0 {
		t.Errorf("launch used the blocking Run path: %v", runner.calls)
	}
	if len(runner.started) != 1 {
		t.Fatalf("expected exactly one started process, got %d: %v", len(runner.started), runner.started)
	}
}

func TestInstaller_LaunchApp_ReportsStartFailure(t *testing.T) {
	runner := &mockRunner{startErr: errors.New("no such file or directory")}
	if err := launchAppDetached(runner, "/opt/centroidx/centroidx"); err == nil {
		t.Fatal("expected an error when the process cannot be started, got nil")
	}
}

// ---- Windows launch ---------------------------------------------------------

// LaunchApp ran "explorer.exe" with no arguments, which just opens a File
// Explorer window: after a successful update the HMI exited, the install
// succeeded, a file browser appeared, and the operator was left with no HMI on
// a running line. An MSIX app is launched through its AppsFolder URI.
func TestWindowsInstaller_LaunchApp_UsesAppsFolderURI(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte("Centroid.CentroidX_8wekyb3d8bbwe\r\n")},
		errors:  []error{nil},
	}

	if err := launchWindowsApp(runner); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.started) != 1 {
		t.Fatalf("expected exactly one started process, got %d: %v", len(runner.started), runner.started)
	}
	all := allArgs(runner.started[0])
	if !hasArgContaining(all, `shell:AppsFolder\Centroid.CentroidX_8wekyb3d8bbwe!centroidx`) {
		t.Errorf("expected the AppsFolder URI for the installed package, got: %v", all)
	}
	// Bare explorer.exe is the bug: it opens a file browser and nothing else.
	if len(runner.started[0].args) == 0 {
		t.Errorf("explorer.exe was started with no arguments — that just opens a File Explorer window")
	}
}

// The package family name embeds a hash of the publisher, so it changes when
// the signing identity does. It has to be read from the installed package
// rather than baked in, or a publisher change silently launches nothing.
func TestWindowsInstaller_LaunchApp_ReadsFamilyNameFromInstalledPackage(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte("Centroid.CentroidX_differenthash\r\n")},
		errors:  []error{nil},
	}

	if err := launchWindowsApp(runner); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) == 0 || len(runner.started) == 0 {
		t.Fatalf("expected a query then a launch, got calls=%v started=%v", runner.calls, runner.started)
	}
	query := allArgs(runner.calls[0])
	if !hasArgContaining(query, "PackageFamilyName") {
		t.Errorf("expected the family name to be queried, got: %v", query)
	}
	if !hasArgContaining(allArgs(runner.started[0]), `Centroid.CentroidX_differenthash!centroidx`) {
		t.Errorf("expected the queried family name to be used, got: %v", allArgs(runner.started[0]))
	}
}

// If the package is not installed the query returns nothing. Launching
// "shell:AppsFolder\!App" would silently do nothing, so this must be an error
// the engine can report instead.
func TestWindowsInstaller_LaunchApp_ErrorsWhenPackageNotFound(t *testing.T) {
	for _, tc := range []struct {
		name   string
		output []byte
		err    error
	}{
		{"empty output", []byte("  \r\n"), nil},
		{"query failed", nil, errors.New("exit status 1")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			runner := &mockRunnerSeq{outputs: [][]byte{tc.output}, errors: []error{tc.err}}

			if err := launchWindowsApp(runner); err == nil {
				t.Fatal("expected an error, got nil")
			}
			if len(runner.started) != 0 {
				t.Errorf("expected nothing to be launched, got: %v", runner.started)
			}
		})
	}
}

// ---- parseMountPoint tests --------------------------------------------------

func TestParseMountPoint(t *testing.T) {
	plist := []byte(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<array>
<dict>
<key>mount-point</key>
<string>/Volumes/CentroidX 1.0</string>
</dict>
</array>
</plist>`)
	got := parseMountPoint(plist)
	if got != "/Volumes/CentroidX 1.0" {
		t.Errorf("unexpected mount point: %q", got)
	}
}

func TestParseMountPoint_Empty(t *testing.T) {
	got := parseMountPoint([]byte("no volumes here"))
	if got != "" {
		t.Errorf("expected empty string, got: %q", got)
	}
}
