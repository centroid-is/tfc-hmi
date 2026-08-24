package platform

import (
	"strings"
	"testing"
)

// One certificate signs the package and our executables, and the two jobs
// need different stores: TrustedPeople is what Add-AppxPackage checks, Root
// is the only thing that makes Windows name the publisher on an elevation
// prompt. Filling only TrustedPeople looks like it worked and leaves every
// prompt saying "Unknown".
func TestTrustCertificate_FillsBothStores(t *testing.T) {
	// absent, absent, then the two imports succeed.
	runner := &mockRunnerSeq{
		outputs: [][]byte{
			[]byte(trustAbsentToken), []byte(trustAbsentToken),
			[]byte(trustOKToken), []byte(trustOKToken),
		},
		errors: []error{nil, nil, nil, nil},
	}
	if err := trustCertificateWindows(runner, `C:\tmp\centroidx-sideload.cer`); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var sawPeople, sawRoot bool
	for _, call := range runner.calls {
		all := allArgs(call)
		if hasArgContaining(all, "Import-Certificate") {
			if hasArgContaining(all, `Cert:\LocalMachine\TrustedPeople`) {
				sawPeople = true
			}
			if hasArgContaining(all, `Cert:\LocalMachine\Root`) {
				sawRoot = true
			}
		}
	}
	if !sawPeople {
		t.Error("the package certificate never reached TrustedPeople: the install will be rejected")
	}
	if !sawRoot {
		t.Error("the certificate never reached the machine roots: prompts stay anonymous")
	}
}

// A station that was set up once must never be prompted again, so both stores
// are read before anything is imported -- reading needs no rights.
func TestTrustCertificate_AlreadyInBothStoresImportsNothing(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(trustPresentToken), []byte(trustPresentToken)},
		errors:  []error{nil, nil},
	}
	if err := trustCertificateWindows(runner, `C:\tmp\centroidx-sideload.cer`); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, call := range runner.calls {
		if hasArgContaining(allArgs(call), "Import-Certificate") {
			t.Fatalf("an already-trusted certificate was imported again: %v", allArgs(call))
		}
	}
}

// Two stores needing rights must cost one UAC dialog, not two: consecutive
// approval prompts read as something going wrong, and the second one is the
// one an operator declines.
func TestTrustCertificate_AsksForApprovalOnce(t *testing.T) {
	notElevated := []byte(trustFailedToken + " " + trustNotElevated)
	runner := &mockRunnerSeq{
		outputs: [][]byte{
			[]byte(trustAbsentToken), []byte(trustAbsentToken),
			notElevated, notElevated,
			[]byte("CENTROIDX_ELEVATED_EXIT=0"),
			[]byte(trustPresentToken), []byte(trustPresentToken),
		},
		errors: []error{nil, nil, nil, nil, nil, nil, nil},
	}
	if err := trustCertificateWindows(runner, `C:\tmp\centroidx-sideload.cer`); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	elevations := 0
	for _, call := range runner.calls {
		if hasArgContaining(allArgs(call), "Start-Process") {
			elevations++
		}
	}
	if elevations != 1 {
		t.Errorf("expected exactly one approval prompt, got %d", elevations)
	}
}

// The elevated copy of the manager is told which stores to write to by the
// flags it is started with; both travel in the single elevated run.
func TestElevatedTrustScript_CarriesAFlagPerStore(t *testing.T) {
	script := elevatedTrustScript(`C:\tmp\centroidx-sideload.cer`, []string{certStoreLocation, codesignStoreLocation})
	if !strings.Contains(script, "-trust-cert") {
		t.Errorf("no -trust-cert in: %s", script)
	}
	if !strings.Contains(script, "-trust-root") {
		t.Errorf("no -trust-root in: %s", script)
	}
	if strings.Count(script, "Start-Process") != 1 {
		t.Errorf("expected a single elevated run: %s", script)
	}
}
