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
	runner := &mockRunner{}
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
	if !hasArgContaining(all, "/tmp/cert.cer") {
		t.Errorf("expected cert path in command args, got: %v", all)
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

// The genuine publisher conflict — same package identity, different signing
// publisher — is the one case where removing the installed package is the fix.
func TestWindowsInstaller_Install_PublisherConflictRemovesAndRetries(t *testing.T) {
	const conflict = "Add-AppxPackage : Deployment failed with HRESULT: 0x80073CFB, The provided package " +
		"is already installed, and reinstallation of the package was blocked. Check the " +
		"AppXDeployment-Server event log for details."
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(conflict), nil, nil},
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
}

// HRESULTs are matched case-insensitively: the hex casing PowerShell emits is
// not something an update on a plant rig should depend on.
func TestWindowsInstaller_Install_PublisherConflictLowercaseHRESULT(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte("Deployment failed with HRESULT: 0x80073cfb, package already installed"), nil, nil},
		errors:  []error{errors.New("exit status 1"), nil, nil},
	}

	if err := installWindows(runner, "/tmp/app.msix"); err != nil {
		t.Fatalf("expected the retry to succeed, got: %v", err)
	}
	if n := countRemoveAppxCalls(runner.calls); n != 1 {
		t.Errorf("expected exactly one Remove-AppxPackage, got %d; calls: %v", n, runner.calls)
	}
}

// When the retry after a conflict removal also fails, the error must say so —
// this is the state where the machine has no CentroidX installed and the
// message is all the operator has to go on.
func TestWindowsInstaller_Install_PublisherConflictRetryFailure(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{
			[]byte("Deployment failed with HRESULT: 0x80073CFB, package already installed"),
			nil,
			[]byte("Deployment failed with HRESULT: 0x80073CF9, Install failed."),
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
	calls   []mockCall
	outputs [][]byte
	errors  []error
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
	if len(runner.calls) == 0 {
		t.Fatal("no commands were recorded")
	}
	call := runner.calls[0]
	if call.name != "/Applications/CentroidX.app/Contents/MacOS/centroidx" {
		t.Errorf("expected app path as command, got: %v", call.name)
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
