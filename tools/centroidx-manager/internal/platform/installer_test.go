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
// The HRESULT is the only thing installWindows reads out of these; which cause
// within 0x80073CF3 it is gets decided by querying Windows, not by the wording.
// They are still real messages, quoted from traced sources, because a fixture
// that drifts from what Windows emits stops testing anything — that is how
// 0x80073CFB came to be labelled a publisher conflict in the first place: the
// constant and the fixture were guessed from each other.

// conflict0x80073CF3 is a complete Add-AppxPackage failure line for the identity
// conflict, quoted in Jeppesen's support note for FliteDeck Pro X and in
// microsoft/winget-cli#4752. The two package full names differ only in their
// trailing PublisherId hash — which is the conflict, and which is exactly what
// installWindows no longer tries to read.
const conflict0x80073CF3 = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF3, Package failed " +
	"updates, dependency or conflict validation. Windows cannot install package " +
	"Jeppesen.FliteDeck_10.3.1.10593_neutral_~_8gk7v4trkh4pt because a different package " +
	"Jeppesen.FliteDeck_10.2.1.9678_neutral_~_g4095tshxnsa8 with the same name is already installed."

// alreadyInstalled is what Windows says for ERROR_PACKAGE_ALREADY_EXISTS,
// quoted in microsoft/WindowsAppSDK#1871 and matching the description Microsoft
// documents for 0x80073CFB. Note what it does *not* say: nothing about a
// publisher, and nothing about a different package. The package on the machine
// is not bitwise identical to the one being installed — a rebuild or a re-sign
// at an unchanged version — and the installed copy is working.
// https://github.com/microsoft/WindowsAppSDK/issues/1871
// https://learn.microsoft.com/en-us/windows/win32/appxpkg/troubleshooting
const alreadyInstalled = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073CFB, The provided package " +
	"is already installed, and reinstallation of the package was blocked. Check the " +
	"AppXDeployment-Server event log for details."

// missingDependency is 0x80073CF3 for a cause removal cannot fix, quoted in
// WSA-Community/WSAGAScript#293. It is the same HRESULT as the conflict, which
// is the whole reason the code cannot act on the HRESULT alone.
const missingDependency = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF3, Package failed " +
	"updates, dependency or conflict validation. Windows cannot install package " +
	"Microsoft.Lovika_1.17.0.0_x64__8wekyb3d8bbwe because this package depends on a framework " +
	"that could not be found. Provide the framework 'Microsoft.DirectXRuntime' published by " +
	"'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US', with " +
	"neutral or x64 processor architecture and minimum version 9.29.952.0, along with this " +
	"package to install."

// The two publishers a conflict is made of. The installed one is CentroidX's
// current sideload identity, traced to centroid-hmi/pubspec.yaml's
// msix_config.publisher; the other is any second signing identity, which is what
// moving between Store and sideload signing produces.
const (
	sideloadPublisher = "CN=2F2634E3-C7B6-45A4-A112-0D039FC2ECDB"
	otherPublisher    = "CN=Centroid ehf., O=Centroid ehf., L=Reykjavik, C=IS"
)

// conflictRunner builds a runner for a 0x80073CF3 install failure, answering the
// two publisher queries with what the test wants Windows to say. A nil entry
// means the query produced no output; errored says it failed outright.
func conflictRunner(installed, incoming string, retryOK bool) *mockRunnerSeq {
	outputs := [][]byte{[]byte(conflict0x80073CF3), []byte(installed), []byte(incoming), nil, nil}
	errs := []error{errors.New("exit status 1"), nil, nil, nil, nil}
	if !retryOK {
		outputs[4] = []byte("Add-AppxPackage : Deployment failed with HRESULT: 0x80073CF9, Install failed.")
		errs[4] = errors.New("exit status 1")
	}
	return &mockRunnerSeq{outputs: outputs, errors: errs}
}

// The one case that justifies removing a working installation: our identity is
// installed, and it was signed by somebody other than whoever signed the asset.
func TestWindowsInstaller_Install_DifferingPublisherRemovesAndRetries(t *testing.T) {
	runner := conflictRunner(sideloadPublisher, otherPublisher, true)

	if err := installWindows(runner, "/tmp/app.msix"); err != nil {
		t.Fatalf("expected the retry to succeed, got: %v", err)
	}
	if len(runner.calls) != 5 {
		t.Fatalf("expected install, two publisher queries, remove, install; got %d: %v", len(runner.calls), runner.calls)
	}
	if !hasArgContaining(allArgs(runner.calls[1]), "-ExpandProperty Publisher") {
		t.Errorf("call 1: expected the installed-publisher query, got: %v", allArgs(runner.calls[1]))
	}
	if !hasArgContaining(allArgs(runner.calls[1]), windowsPackageName) {
		t.Errorf("call 1: expected the query scoped to our identity name, got: %v", allArgs(runner.calls[1]))
	}
	if !hasArgContaining(allArgs(runner.calls[2]), "AppxManifest.xml") {
		t.Errorf("call 2: expected the asset manifest read, got: %v", allArgs(runner.calls[2]))
	}
	if !hasArgContaining(allArgs(runner.calls[2]), "app.msix") {
		t.Errorf("call 2: expected the asset path in the manifest read, got: %v", allArgs(runner.calls[2]))
	}
	if !hasArgContaining(allArgs(runner.calls[3]), "Remove-AppxPackage") {
		t.Errorf("call 3: expected Remove-AppxPackage, got: %v", allArgs(runner.calls[3]))
	}
	if !hasArgContaining(allArgs(runner.calls[4]), "Add-AppxPackage") {
		t.Errorf("call 4: expected the install retry, got: %v", allArgs(runner.calls[4]))
	}
}

// Everything else about a 0x80073CF3 leaves the installation alone. These are
// the cases that used to depend on how Windows worded the failure; none of them
// does now, and each fails towards keeping the application.
func TestWindowsInstaller_Install_0x80073CF3KeepsInstalledPackageUnlessPublishersDiffer(t *testing.T) {
	for _, tc := range []struct {
		name    string
		runner  *mockRunnerSeq
		queries int // how many publisher queries should have been needed
	}{
		{
			// A missing dependency or a wrong architecture: our package is
			// installed, signed by us, and removing it fixes nothing.
			"same publisher on both sides",
			conflictRunner(sideloadPublisher, sideloadPublisher, true),
			2,
		},
		{
			// Nothing of ours is installed, so there is nothing to conflict
			// with and nothing to remove. No point reading the asset.
			"our identity is not installed",
			conflictRunner("", "", true),
			1,
		},
		{
			// The asset could not be read — not a zip, no manifest, unparseable
			// XML. We cannot tell whether the publishers differ, so we must not
			// act as though they do.
			"asset publisher unreadable",
			conflictRunner(sideloadPublisher, "", true),
			2,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := installWindows(tc.runner, "/tmp/app.msix")
			if err == nil {
				t.Fatal("expected an error, got nil")
			}
			if n := countRemoveAppxCalls(tc.runner.calls); n != 0 {
				t.Errorf("uninstalled the working package (%d Remove-AppxPackage call(s)); calls: %v", n, tc.runner.calls)
			}
			if want := 1 + tc.queries; len(tc.runner.calls) != want {
				t.Errorf("expected %d calls (install + %d quer(y/ies)), got %d: %v", want, tc.queries, len(tc.runner.calls), tc.runner.calls)
			}
			if !strings.Contains(err.Error(), "0x80073CF3") {
				t.Errorf("expected the original HRESULT reported, got: %v", err)
			}
		})
	}
}

// A query that fails outright is not an answer. mockRunnerSeq returns an error
// for the publisher query, and the installation must survive it.
func TestWindowsInstaller_Install_PublisherQueryFailureKeepsInstalledPackage(t *testing.T) {
	for _, tc := range []struct {
		name   string
		errAt  int // index of the query that fails
		wanted int // total calls expected
	}{
		{"installed-publisher query fails", 1, 2},
		{"asset-publisher query fails", 2, 3},
	} {
		t.Run(tc.name, func(t *testing.T) {
			runner := conflictRunner(sideloadPublisher, otherPublisher, true)
			runner.errors[tc.errAt] = errors.New("exit status 1")
			// A failed query still writes to stderr; that output must not be
			// mistaken for the answer.
			runner.outputs[tc.errAt] = []byte("Get-AppxPackage : the term is not recognized")

			err := installWindows(runner, "/tmp/app.msix")
			if err == nil {
				t.Fatal("expected an error, got nil")
			}
			if n := countRemoveAppxCalls(runner.calls); n != 0 {
				t.Errorf("a failed query led to an uninstall (%d call(s)); calls: %v", n, runner.calls)
			}
			if len(runner.calls) != tc.wanted {
				t.Errorf("expected %d calls, got %d: %v", tc.wanted, len(runner.calls), runner.calls)
			}
		})
	}
}

// Publishers are compared byte for byte. The PublisherId hash is computed over
// the exact Publisher string with no normalisation, and even the order of the
// distinguished-name elements changes it (microsoft/WindowsAppSDK#650), so two
// spellings that differ only in case really are two different packages to
// Windows — and skipping that would skip a real conflict.
func TestWindowsInstaller_Install_PublisherComparisonIsExact(t *testing.T) {
	runner := conflictRunner(sideloadPublisher, strings.ToLower(sideloadPublisher), true)

	if err := installWindows(runner, "/tmp/app.msix"); err != nil {
		t.Fatalf("expected the retry to succeed, got: %v", err)
	}
	if n := countRemoveAppxCalls(runner.calls); n != 1 {
		t.Errorf("a case-only publisher difference was treated as the same publisher; calls: %v", runner.calls)
	}
}

// PowerShell pads and wraps; the queries' answers get trimmed before comparison,
// or every publisher would look different from every other one.
func TestWindowsInstaller_Install_PublisherAnswersAreTrimmed(t *testing.T) {
	runner := conflictRunner("  "+sideloadPublisher+"\r\n", sideloadPublisher+"\n", true)

	err := installWindows(runner, "/tmp/app.msix")
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if n := countRemoveAppxCalls(runner.calls); n != 0 {
		t.Errorf("whitespace around identical publishers was read as a conflict; calls: %v", runner.calls)
	}
}

// The regression that matters. ERROR_PACKAGE_ALREADY_EXISTS means a working
// CentroidX at this very version is on the machine and Windows will not
// overwrite it. Removing it to retry gambles the whole installation on a retry
// that fixes nothing, and if that retry fails — Defender holding a file, a full
// disk, a payload already deleted — the station is left with no application.
// PR #290 bound the uninstall to exactly this code; nothing may put it back.
func TestWindowsInstaller_Install_AlreadyInstalledKeepsInstalledPackage(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(alreadyInstalled), nil, nil, nil, nil},
		errors:  []error{errors.New("exit status 1"), nil, nil, nil, nil},
	}

	err := installWindows(runner, "/tmp/app.msix")
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if n := countRemoveAppxCalls(runner.calls); n != 0 {
		t.Errorf("an already-installed package was uninstalled (%d Remove-AppxPackage call(s)); calls: %v", n, runner.calls)
	}
	// Not even a publisher query: CFB is answered without asking anything.
	if len(runner.calls) != 1 {
		t.Errorf("expected the install to stop after one attempt, got %d calls: %v", len(runner.calls), runner.calls)
	}
	if strings.Contains(err.Error(), "after removing conflict") {
		t.Errorf("an already-installed package was reported as a publisher conflict: %v", err)
	}
	if !strings.Contains(err.Error(), "0x80073CFB") {
		t.Errorf("expected the HRESULT in the error, got: %v", err)
	}
	if !strings.Contains(err.Error(), "left alone") {
		t.Errorf("expected the error to say the installation was kept, got: %v", err)
	}
}

// The dependency message carries the conflict's HRESULT, so only the publisher
// query separates them. With our package installed under our own signature,
// nothing may be removed — and the missing framework must reach the operator.
func TestWindowsInstaller_Install_DependencyFailureKeepsInstalledPackage(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{
			[]byte(missingDependency),
			[]byte(sideloadPublisher),
			[]byte(sideloadPublisher),
			nil, nil,
		},
		errors: []error{errors.New("exit status 1"), nil, nil, nil, nil},
	}

	err := installWindows(runner, "/tmp/app.msix")
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if n := countRemoveAppxCalls(runner.calls); n != 0 {
		t.Errorf("a missing dependency uninstalled the working package (%d Remove-AppxPackage call(s)); calls: %v", n, runner.calls)
	}
	if !strings.Contains(err.Error(), "Microsoft.DirectXRuntime") {
		t.Errorf("expected the missing framework named in the error, got: %v", err)
	}
}

// When the retry after a conflict removal also fails, the error must say so —
// this is the state where the machine has no CentroidX installed and the
// message is all the operator has to go on.
func TestWindowsInstaller_Install_PublisherConflictRetryFailure(t *testing.T) {
	runner := conflictRunner(sideloadPublisher, otherPublisher, false)

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

// A publisher query is only allowed to answer with something that could be a
// publisher. The manager captures combined output, so a non-terminating
// PowerShell error arrives on the same channel as the answer while the process
// still exits 0 — and an error message is not equal to the other publisher, so
// letting it through would read as "they differ" and uninstall a working HMI on
// the strength of a diagnostic. Every one of these must refuse to act.
func TestWindowsInstaller_Install_UnrecognisedQueryOutputIsNotAPublisher(t *testing.T) {
	noise := []struct {
		name   string
		output string
	}{
		{"cmdlet error on stdout", "Get-AppxPackage : A parameter cannot be found that matches parameter name 'Name'."},
		{"deployment warning", "WARNING: The package repository is being rebuilt."},
		{"whitespace only", "   \r\n  "},
		{"empty", ""},
	}
	// Both queries are checked: whichever one is poisoned, nothing may be removed.
	for _, at := range []struct {
		name  string
		index int
		calls int
	}{
		{"installed-publisher query", 1, 2},
		{"asset-publisher query", 2, 3},
	} {
		for _, n := range noise {
			t.Run(at.name+"/"+n.name, func(t *testing.T) {
				runner := conflictRunner(sideloadPublisher, otherPublisher, true)
				runner.outputs[at.index] = []byte(n.output)

				err := installWindows(runner, "/tmp/app.msix")
				if err == nil {
					t.Fatal("expected an error, got nil")
				}
				if c := countRemoveAppxCalls(runner.calls); c != 0 {
					t.Errorf("unrecognised query output caused an uninstall (%d call(s)); calls: %v", c, runner.calls)
				}
				if len(runner.calls) != at.calls {
					t.Errorf("expected %d calls, got %d: %v", at.calls, len(runner.calls), runner.calls)
				}
			})
		}
	}
}

// The queries have to be built so that a failure cannot masquerade as an answer.
// -ErrorAction Stop / $ErrorActionPreference='Stop' are what make a cmdlet error
// terminating; without them PowerShell writes the error and exits 0, and the
// manager cannot tell the difference from the outside.
func TestWindowsInstaller_PublisherQueriesStopOnError(t *testing.T) {
	installed := installedPublisherCommand()
	for _, want := range []string{windowsPackageName, "-ErrorAction Stop", "-ExpandProperty Publisher"} {
		if !strings.Contains(installed, want) {
			t.Errorf("installed-publisher query is missing %q: %s", want, installed)
		}
	}
	asset := assetPublisherCommand(`C:\tmp\app.msix`)
	for _, want := range []string{"$ErrorActionPreference='Stop'", "AppxManifest.xml", "Identity.Publisher", `C:\tmp\app.msix`} {
		if !strings.Contains(asset, want) {
			t.Errorf("asset-publisher query is missing %q: %s", want, asset)
		}
	}
}

// The claim this redesign rests on is that the verdict does not depend on what
// Windows said, only on what it answered. So the same conflict, worded four
// different ways — including with no wording at all beyond the code — must reach
// the same decision.
//
// Only the English and Italian messages are recorded; the Icelandic is invented
// and the bare one is not a real message at all. That is safe here in a way it
// would not have been before, and it is precisely the point: nothing reads these
// strings except the hex digits. A test that had to quote real prose to pass
// would mean the prose was still load-bearing.
func TestWindowsInstaller_Install_VerdictIsIndependentOfMessageLanguage(t *testing.T) {
	messages := []struct {
		name    string
		message string
	}{
		{"english", conflict0x80073CF3},
		{
			"italian", // verbatim, microsoft/winget-cli#4752
			"Impossibile installare il pacchetto Mozilla.MozillaFirefox_129.0.2.0_x64__jag0gd4e3s9p2. È già " +
				"installato un pacchetto Mozilla.MozillaFirefox_126.0.1.0_x64__gmpnhwe7bv608 diverso con lo stesso " +
				"nome. Exception(1) tid(1274) 80073CF3",
		},
		{
			"icelandic", // invented; nothing reads it
			"Add-AppxPackage : Uppsetning mistókst með HRESULT: 0x80073CF3, pakkinn stóðst ekki staðfestingu.",
		},
		{"no prose at all", "0x80073CF3"},
	}

	for _, m := range messages {
		t.Run(m.name+"/differing publishers removes and retries", func(t *testing.T) {
			runner := conflictRunner(sideloadPublisher, otherPublisher, true)
			runner.outputs[0] = []byte(m.message)
			if err := installWindows(runner, "/tmp/app.msix"); err != nil {
				t.Fatalf("expected the retry to succeed, got: %v", err)
			}
			if c := countRemoveAppxCalls(runner.calls); c != 1 {
				t.Errorf("expected exactly one Remove-AppxPackage, got %d; calls: %v", c, runner.calls)
			}
		})
		t.Run(m.name+"/same publisher keeps the installation", func(t *testing.T) {
			runner := conflictRunner(sideloadPublisher, sideloadPublisher, true)
			runner.outputs[0] = []byte(m.message)
			if err := installWindows(runner, "/tmp/app.msix"); err == nil {
				t.Fatal("expected an error, got nil")
			}
			if c := countRemoveAppxCalls(runner.calls); c != 0 {
				t.Errorf("matching publishers still uninstalled (%d call(s)); calls: %v", c, runner.calls)
			}
		})
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
