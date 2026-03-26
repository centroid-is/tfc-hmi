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
	// Sequence: hdiutil attach → cp → xattr → hdiutil detach (deferred)
	runner := &mockRunnerSeq{
		outputs: [][]byte{
			[]byte(`<string>/Volumes/CentroidX</string>`), // hdiutil output
			nil, // cp
			nil, // xattr
			nil, // hdiutil detach (deferred)
		},
		errors: []error{nil, nil, nil, nil},
	}

	if err := installDarwin(runner, "/tmp/app.dmg"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(runner.calls) < 3 {
		t.Fatalf("expected at least 3 calls, got %d: %v", len(runner.calls), runner.calls)
	}

	// Call 0: hdiutil attach
	call0 := allArgs(runner.calls[0])
	if !hasArg(call0, "hdiutil") {
		t.Errorf("call 0: expected 'hdiutil', got: %v", call0)
	}
	if !hasArg(call0, "attach") {
		t.Errorf("call 0: expected 'attach', got: %v", call0)
	}

	// Call 1: cp to /Applications/
	call1 := allArgs(runner.calls[1])
	if !hasArg(call1, "cp") {
		t.Errorf("call 1: expected 'cp', got: %v", call1)
	}
	if !hasArgContaining(call1, "/Applications/") {
		t.Errorf("call 1: expected '/Applications/' in args, got: %v", call1)
	}

	// Call 2: xattr
	call2 := allArgs(runner.calls[2])
	if !hasArg(call2, "xattr") {
		t.Errorf("call 2: expected 'xattr', got: %v", call2)
	}
	if !hasArgContaining(call2, "com.apple.quarantine") {
		t.Errorf("call 2: expected 'com.apple.quarantine' in args, got: %v", call2)
	}
}

func TestDarwinInstaller_Install_CleanupOnError(t *testing.T) {
	// hdiutil attach succeeds, cp fails — detach must still be called
	runner := &mockRunnerSeq{
		outputs: [][]byte{
			[]byte(`<string>/Volumes/CentroidX</string>`), // hdiutil attach
			nil, // cp (will error)
			nil, // hdiutil detach (deferred)
		},
		errors: []error{
			nil,                           // hdiutil attach succeeds
			errors.New("cp: permission denied"), // cp fails
			nil,                           // hdiutil detach succeeds
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
