package update

import (
	"archive/zip"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func writeZip(t *testing.T, path string, entries map[string]string) {
	t.Helper()
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = f.Close() }()
	zw := zip.NewWriter(f)
	for name, body := range entries {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(body)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
}

// The default is Program Files: an operator looking for an installed program
// looks there, not in their profile. Elevation is the price, and the manager
// asks for it the same way it asks for the certificate.
func TestDefaultPortableDir_IsProgramFilesOnWindows(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Program Files is a Windows notion")
	}
	dir := DefaultPortableDir()
	if !strings.Contains(strings.ToLower(dir), "program files") {
		t.Errorf("expected a Program Files path, got %q", dir)
	}
	if filepath.Base(dir) != "CentroidX" {
		t.Errorf("expected the folder to be named CentroidX, got %q", dir)
	}
}

// Program Files is not writable unelevated; a temp folder is. The install
// path picks its route from this, so a wrong answer either skips a needed
// approval or asks for one that is not needed.
func TestWritable(t *testing.T) {
	if !writable(t.TempDir()) {
		t.Error("a fresh temp folder must be writable")
	}
	if runtime.GOOS == "windows" && os.Getenv("CENTROIDX_TEST_ELEVATED") == "" {
		if pf := os.Getenv("ProgramFiles"); pf != "" {
			if writable(filepath.Join(pf, "CentroidX-does-not-exist")) {
				t.Error("Program Files reported writable without elevation")
			}
		}
	}
}

// A zip that tries to write outside the chosen folder is refused: this is
// the one place the manager unpacks something it downloaded.
func TestUnzip_RefusesEntriesOutsideTheDestination(t *testing.T) {
	tmp := t.TempDir()
	src := filepath.Join(tmp, "evil.zip")
	writeZip(t, src, map[string]string{"../escaped.txt": "nope"})

	dst := filepath.Join(tmp, "dest")
	err := unzip(src, dst)
	if err == nil {
		t.Fatal("expected the traversing entry to be refused")
	}
	if !strings.Contains(err.Error(), "outside") {
		t.Errorf("expected the error to say why, got: %v", err)
	}
	if _, statErr := os.Stat(filepath.Join(tmp, "escaped.txt")); statErr == nil {
		t.Error("the entry was written outside the destination")
	}
}

func TestUnzip_WritesTheArchive(t *testing.T) {
	tmp := t.TempDir()
	src := filepath.Join(tmp, "ok.zip")
	writeZip(t, src, map[string]string{
		"centroidx-windows-x64/centroidx.exe": "MZ",
		"centroidx-windows-x64/data/app.txt":  "hello",
	})

	dst := filepath.Join(tmp, "dest")
	if err := unzip(src, dst); err != nil {
		t.Fatalf("unzip: %v", err)
	}
	if b, err := os.ReadFile(filepath.Join(dst, "centroidx-windows-x64", "data", "app.txt")); err != nil {
		t.Fatalf("nested entry missing: %v", err)
	} else if string(b) != "hello" {
		t.Errorf("nested entry content %q", b)
	}
}

// The Start-menu shortcut needs the executable, which sits one level down in
// the published zip.
func TestFindPortableExe(t *testing.T) {
	tmp := t.TempDir()
	nested := filepath.Join(tmp, "centroidx-windows-x64")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatal(err)
	}
	exe := filepath.Join(nested, "centroidx.exe")
	if err := os.WriteFile(exe, []byte("MZ"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := FindPortableExe(tmp); got != exe {
		t.Errorf("expected %q, got %q", exe, got)
	}

	flat := t.TempDir()
	flatExe := filepath.Join(flat, "centroidx.exe")
	if err := os.WriteFile(flatExe, []byte("MZ"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := FindPortableExe(flat); got != flatExe {
		t.Errorf("flat layout: expected %q, got %q", flatExe, got)
	}

	if got := FindPortableExe(t.TempDir()); got != "" {
		t.Errorf("expected no executable in an empty folder, got %q", got)
	}
}

func TestPortableVersionIn(t *testing.T) {
	dir := t.TempDir()
	if v := PortableVersionIn(dir); v != "" {
		t.Errorf("expected no version in an empty folder, got %q", v)
	}
	if err := os.WriteFile(filepath.Join(dir, versionFile), []byte("2026.8.23\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if v := PortableVersionIn(dir); v != "2026.8.23" {
		t.Errorf("expected 2026.8.23, got %q", v)
	}
}
