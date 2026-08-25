package platform

import (
	"strings"
	"testing"
)

// An uninstall from the manager is nearly always a step in something else --
// a rollback, or a build Windows will not install over the current one -- and
// both end in an install. Removing the package takes its data container with
// it, so the configuration has to be put aside BEFORE the removal; afterwards
// there is nothing left to save.
func TestUninstall_SavesTheStationsDataFirst(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(dataSavedToken), nil},
		errors:  []error{nil, nil},
	}
	inst := &windowsInstaller{runner: runner}
	if err := inst.Uninstall(); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) != 2 {
		t.Fatalf("expected the save and then the removal, got %d calls", len(runner.calls))
	}
	if !hasArgContaining(allArgs(runner.calls[0]), dataSavedToken) {
		t.Errorf("call 0 was not the data save: %v", allArgs(runner.calls[0]))
	}
	if !hasArgContaining(allArgs(runner.calls[1]), "Remove-AppxPackage") {
		t.Errorf("call 1 was not the removal: %v", allArgs(runner.calls[1]))
	}
}

// The other half: an install onto a machine with nothing installed is where a
// saved container comes back.
func TestInstall_FreshInstallRestoresASavedContainer(t *testing.T) {
	dir := t.TempDir()
	msix := writeMsix(t, dir, "2026.8.23.1")
	// version query (nothing installed) -> install -> restore
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(""), nil, []byte(dataRestoredToken)},
		errors:  []error{nil, nil, nil},
	}
	if err := installWindows(runner, msix); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	restored := false
	for _, c := range runner.calls {
		if hasArgContaining(allArgs(c), dataRestoredToken) {
			restored = true
		}
	}
	if !restored {
		t.Errorf("a fresh install did not restore the saved container: %v", runner.calls)
	}
}

// And the case that must NOT restore: an ordinary upgrade over a working
// install. Writing a copy from some earlier uninstall over a live container
// would replace a configured station's settings with older ones.
func TestInstall_UpgradeInPlaceDoesNotRestore(t *testing.T) {
	dir := t.TempDir()
	msix := writeMsix(t, dir, "2026.9.1.0")
	// version query (2026.8.23.1 installed, incoming is newer) -> install
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte("2026.8.23.1"), nil},
		errors:  []error{nil, nil},
	}
	if err := installWindows(runner, msix); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, c := range runner.calls {
		if hasArgContaining(allArgs(c), dataRestoredToken) {
			t.Errorf("an in-place upgrade restored a stale container: %v", allArgs(c))
		}
	}
}

// The backup is consumed by the install that uses it. Left in place it would
// sit waiting for an unrelated future install to write a stale configuration
// over a working one.
func TestRestoreScript_ConsumesTheBackup(t *testing.T) {
	script := restorePackageDataScript()
	if !strings.Contains(script, "Remove-Item -Recurse -Force -LiteralPath $src") {
		t.Errorf("the restore must delete the copy it consumed: %s", script)
	}
}
