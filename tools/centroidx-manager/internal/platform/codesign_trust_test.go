package platform

import (
	"strings"
	"testing"
)

// The publisher name Windows shows on an elevation prompt comes from a
// signature that chains to a trusted ROOT. TrustedPeople is enough for
// Windows to accept a sideloaded package and not enough for this, so a
// code-signing certificate landing in TrustedPeople would look like it worked
// and leave every prompt saying "Unknown".
func TestTrustCodesignCertificate_ImportsIntoTheMachineRootStore(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(trustAbsentToken), []byte(trustOKToken)},
		errors:  []error{nil, nil},
	}
	if err := trustCodesignCertificateWindows(runner, `C:\tmp\centroidx-codesign.cer`); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) < 2 {
		t.Fatal("expected the presence check and then the import")
	}
	all := allArgs(runner.calls[1])
	if !hasArgContaining(all, `Cert:\LocalMachine\Root`) {
		t.Errorf("expected the machine root store, got: %v", all)
	}
	if hasArgContaining(all, "TrustedPeople") {
		t.Errorf("the code-signing certificate must not go to TrustedPeople: %v", all)
	}
	if !hasArgContaining(all, "centroidx-codesign.cer") {
		t.Errorf("expected the certificate path, got: %v", all)
	}
}

// Both certificates use the same presence check, so a wrong store there would
// re-import on every update -- one UAC prompt per update, forever.
func TestTrustCodesignCertificate_ChecksTheRootStoreBeforeImporting(t *testing.T) {
	runner := &mockRunnerSeq{
		outputs: [][]byte{[]byte(trustPresentToken)},
		errors:  []error{nil},
	}
	if err := trustCodesignCertificateWindows(runner, `C:\tmp\centroidx-codesign.cer`); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(runner.calls) != 1 {
		t.Fatalf("an already-trusted certificate must not be imported again, calls: %d", len(runner.calls))
	}
	all := allArgs(runner.calls[0])
	if !hasArgContaining(all, `Cert:\LocalMachine\Root`) {
		t.Errorf("the presence check read the wrong store: %v", all)
	}
}

// The elevated copy of the manager is told which store to write to by the
// flag it is started with. Sending the code-signing certificate under
// -trust-cert would put it in TrustedPeople from inside the elevated run,
// where nothing here would notice.
func TestElevatedTrustScript_UsesTheStoreSpecificFlag(t *testing.T) {
	pkg := elevatedTrustScript(`C:\tmp\sideload.cer`, certStoreLocation)
	code := elevatedTrustScript(`C:\tmp\codesign.cer`, codesignStoreLocation)

	if !strings.Contains(pkg, "-trust-cert") || strings.Contains(pkg, "-trust-root") {
		t.Errorf("the package certificate must elevate with -trust-cert: %s", pkg)
	}
	if !strings.Contains(code, "-trust-root") {
		t.Errorf("the code-signing certificate must elevate with -trust-root: %s", code)
	}
}
