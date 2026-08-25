package platform

import (
	"archive/zip"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeMsix builds the smallest thing that is still an MSIX to this code: a
// zip with an AppxManifest.xml carrying an Identity version.
func writeMsix(t *testing.T, dir, version string) string {
	t.Helper()
	path := filepath.Join(dir, "test.msix")
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	zw := zip.NewWriter(f)
	w, err := zw.Create("AppxManifest.xml")
	if err != nil {
		t.Fatal(err)
	}
	manifest := `<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="Centroid.CentroidX" Publisher="CN=Centroid, O=Centroid ehf., C=IS" Version="` + version + `" ProcessorArchitecture="x64" />
</Package>`
	if _, err := w.Write([]byte(manifest)); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestPackageVersionOf(t *testing.T) {
	dir := t.TempDir()
	got, err := PackageVersionOf(writeMsix(t, dir, "0.2026.8.512"))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "0.2026.8.512" {
		t.Errorf("expected 0.2026.8.512, got %q", got)
	}
}

// A package we cannot read must not stop an install: the version check only
// exists to phrase a message, and refusing on a read failure would block an
// install Windows might well accept.
func TestPackageVersionOf_UnreadableIsAnError(t *testing.T) {
	dir := t.TempDir()
	bad := filepath.Join(dir, "not-a-zip.msix")
	if err := os.WriteFile(bad, []byte("not a zip"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := PackageVersionOf(bad); err == nil {
		t.Error("expected an error for a file that is not an MSIX")
	}
}

// Windows compares four numeric fields left to right. semver cannot express
// that: it rejects "0.2026.8.512" outright and would drop the fourth field of
// "2026.8.23.1" -- which is the field the whole scheme turns on.
func TestComparePackageVersions(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"2026.8.23.1", "2026.8.23.1", 0},
		{"2026.8.25.0", "2026.8.23.1", 1},
		{"2026.8.23.1", "2026.8.25.0", -1},
		// the scheme: an unstable build always sorts below every stable one
		{"0.2026.8.512", "2026.8.23.1", -1},
		{"2026.8.23.1", "0.2026.8.512", 1},
		// and unstable builds order among themselves by the run counter
		{"0.2026.8.513", "0.2026.8.512", 1},
		{"0.2026.9.1", "0.2026.8.999", 1},
		{"0.2027.1.1", "0.2026.12.999", 1},
		// missing fields read as zero
		{"2026.8.23", "2026.8.23.0", 0},
		{"2026.8.23", "2026.8.23.1", -1},
	}
	for _, c := range cases {
		if got := ComparePackageVersions(c.a, c.b); got != c.want {
			t.Errorf("compare(%q, %q) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

// The message an operator reads. It has to name both versions and say what to
// do; "0x80073CFB" says neither.
func TestDowngradeRefusal_SaysWhatToDo(t *testing.T) {
	dir := t.TempDir()
	msix := writeMsix(t, dir, "0.2026.8.512")
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte("2026.8.23.1")}, errors: []error{nil}}

	msg := downgradeRefusal(runner, msix)
	if msg == "" {
		t.Fatal("a build below the installed version must be refused with an explanation")
	}
	for _, want := range []string{"2026.8.23.1", "0.2026.8.512", "Uninstall"} {
		if !strings.Contains(msg, want) {
			t.Errorf("expected %q in the message, got: %s", want, msg)
		}
	}
}

func TestDowngradeRefusal_SameVersionIsNamedAsSuch(t *testing.T) {
	dir := t.TempDir()
	msix := writeMsix(t, dir, "2026.8.23.1")
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte("2026.8.23.1")}, errors: []error{nil}}

	msg := downgradeRefusal(runner, msix)
	if !strings.Contains(msg, "same version") || !strings.Contains(msg, "Uninstall") {
		t.Errorf("expected the same-version case named and the remedy given, got: %s", msg)
	}
}

// Rolling back to an older release is the same refusal for the same reason,
// and it is a real operation: a station on a bad release has to go back. The
// check knows nothing about channels -- it compares versions -- so stable to
// older stable reads exactly like stable to a main build.
func TestDowngradeRefusal_RollbackToAnOlderStableIsExplained(t *testing.T) {
	dir := t.TempDir()
	msix := writeMsix(t, dir, "2026.8.23.1")
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte("2026.9.4.1")}, errors: []error{nil}}

	msg := downgradeRefusal(runner, msix)
	if msg == "" {
		t.Fatal("a rollback must be explained, not left to an HRESULT")
	}
	for _, want := range []string{"2026.9.4.1", "2026.8.23.1", "older", "Uninstall"} {
		if !strings.Contains(msg, want) {
			t.Errorf("expected %q in the rollback message, got: %s", want, msg)
		}
	}
}

func TestDowngradeRefusal_NewerInstallsSilently(t *testing.T) {
	dir := t.TempDir()
	msix := writeMsix(t, dir, "2026.9.1.0")
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte("2026.8.23.1")}, errors: []error{nil}}

	if msg := downgradeRefusal(runner, msix); msg != "" {
		t.Errorf("a newer build must install without comment, got: %s", msg)
	}
}

// Nothing installed: every version is installable, and the check must not
// invent a reason to stop.
func TestDowngradeRefusal_NothingInstalled(t *testing.T) {
	dir := t.TempDir()
	msix := writeMsix(t, dir, "0.2026.8.512")
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte("")}, errors: []error{nil}}

	if msg := downgradeRefusal(runner, msix); msg != "" {
		t.Errorf("expected no refusal on a clean machine, got: %s", msg)
	}
}
