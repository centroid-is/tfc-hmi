//go:build windows

package platform

import "testing"

// windowsInstaller's methods are one-line delegations to the untagged helpers
// in installer.go, where all the logic and all the other tests live. Nothing
// verified the delegations themselves: this file is `//go:build windows`, and
// until the manager unit-test job gained a windows-latest leg, a tagged test
// here would never have compiled, let alone run.
//
// They are worth pinning because a wrong delegation is invisible in review and
// total in effect — LaunchApp pointing at the generic launcher is exactly the
// bug this PR fixes, and it would look like a plausible one-liner.

func TestWindowsInstaller_LaunchApp_DelegatesToTheAppsFolderLauncher(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte("Centroid.CentroidX_delegationhash\r\n")},
		errors:  []error{nil},
	}
	inst := &windowsInstaller{runner: runner}

	if err := inst.LaunchApp(); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// The generic launcher would have started the path directly with no query
	// first; launchWindowsApp queries the family name, then starts the URI.
	if len(runner.calls) != 1 || !hasArgContaining(allArgs(runner.calls[0]), "PackageFamilyName") {
		t.Errorf("expected the family-name query, got: %v", runner.calls)
	}
	if len(runner.started) != 1 {
		t.Fatalf("expected exactly one started process, got %d: %v", len(runner.started), runner.started)
	}
	if !hasArgContaining(allArgs(runner.started[0]), `shell:AppsFolder\Centroid.CentroidX_delegationhash!centroidx`) {
		t.Errorf("expected the AppsFolder URI, got: %v", allArgs(runner.started[0]))
	}
}

func TestWindowsInstaller_Install_DelegatesToInstallWindows(t *testing.T) {
	runner := &mockRunner{}
	inst := &windowsInstaller{runner: runner}

	if err := inst.Install(`C:\tmp\app.msix`); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) == 0 {
		t.Fatal("no command was recorded")
	}
	all := allArgs(runner.calls[0])
	if !hasArgContaining(all, "Add-AppxPackage") {
		t.Errorf("expected Add-AppxPackage, got: %v", all)
	}
	if !hasArgContaining(all, `app.msix`) {
		t.Errorf("expected the asset path, got: %v", all)
	}
}

func TestWindowsInstaller_TrustCertificate_DelegatesToTrustCertificateWindows(t *testing.T) {
	runner := &mockRunner{}
	inst := &windowsInstaller{runner: runner}

	if err := inst.TrustCertificate(`C:\tmp\centroidx.cer`); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) == 0 {
		t.Fatal("no command was recorded")
	}
	all := allArgs(runner.calls[0])
	if !hasArgContaining(all, "Import-Certificate") {
		t.Errorf("expected Import-Certificate, got: %v", all)
	}
	// Machine store, not the per-user one — see certStoreLocation.
	if !hasArgContaining(all, `Cert:\LocalMachine\TrustedPeople`) {
		t.Errorf("expected the machine-level store, got: %v", all)
	}
}
