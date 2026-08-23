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

// A trust failure used to report only "exit status 1". installWindows and
// Uninstall both fold the command output into their errors; this one must too,
// or the operator has nothing to act on.
func TestWindowsInstaller_TrustCertificate_ReportsDetail(t *testing.T) {
	const detail = "Import-Certificate : The system cannot find the file specified."
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(detail)},
		errors:  []error{errors.New("exit status 1")},
	}

	err := trustCertificateWindows(runner, `C:\tmp\centroidx.cer`)
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if !strings.Contains(err.Error(), "cannot find the file specified") {
		t.Errorf("expected the command output in the error, got: %v", err)
	}
}

// Cert:\LocalMachine\TrustedPeople is a machine-wide store and writing to it
// needs administrator rights the manager does not request. That is the failure
// a plant technician will actually hit, and "exit status 1" tells them nothing
// — the error has to name the cause and give them the one-time command.
func TestWindowsInstaller_TrustCertificate_AccessDeniedExplainsElevation(t *testing.T) {
	cases := []struct {
		name   string
		output string
	}{
		{
			"access is denied",
			"Import-Certificate : Access is denied. 0x80070005 (WIN32: 5 ERROR_ACCESS_DENIED)",
		},
		{
			"unauthorized access exception",
			"Import-Certificate : Cannot access the store. " +
				"System.UnauthorizedAccessException: Access to the path is denied.",
		},
		{
			"registry access not allowed",
			"Import-Certificate : Requested registry access is not allowed.",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			runner := &mockRunnerSeq{
				outputs: [][]byte{[]byte(tc.output)},
				errors:  []error{errors.New("exit status 1")},
			}

			err := trustCertificateWindows(runner, `C:\tmp\centroidx.cer`)
			if err == nil {
				t.Fatal("expected an error, got nil")
			}
			msg := err.Error()
			if !strings.Contains(msg, "administrator") {
				t.Errorf("expected the error to name elevation as the cause, got: %v", err)
			}
			if !strings.Contains(msg, "Import-Certificate -FilePath") {
				t.Errorf("expected the error to carry the one-time remediation command, got: %v", err)
			}
			if !strings.Contains(msg, `C:\tmp\centroidx.cer`) {
				t.Errorf("expected the remediation command to name the cert path, got: %v", err)
			}
		})
	}
}

// A trust failure that is not an elevation problem must not be mislabelled as
// one — the same over-matching mistake the install path used to make.
func TestWindowsInstaller_TrustCertificate_NonElevationFailureIsNotBlamedOnAdmin(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte("Import-Certificate : Cannot find path 'C:\\tmp\\centroidx.cer' because it does not exist.")},
		errors:  []error{errors.New("exit status 1")},
	}

	err := trustCertificateWindows(runner, `C:\tmp\centroidx.cer`)
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if strings.Contains(err.Error(), "administrator") {
		t.Errorf("a missing-file failure was reported as an elevation problem: %v", err)
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
