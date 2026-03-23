//go:build integration && linux

package platform

import (
	"archive/tar"
	"compress/gzip"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestIntegration_DpkgAvailable verifies that dpkg is present on the CI runner
// and reports its version. If this test fails, the runner image is missing dpkg
// (unexpected on Ubuntu runners).
func TestIntegration_DpkgAvailable(t *testing.T) {
	requireCommand(t, "dpkg")

	stdout, stderr, err := runCommand(t, "dpkg", "--version")
	if err != nil {
		t.Fatalf("dpkg --version failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}
	if !strings.Contains(stdout, "Debian") {
		t.Errorf("expected 'Debian' in dpkg --version output; got %q", stdout)
	}
}

// TestIntegration_DpkgDryRun creates a minimal but valid .deb package using
// standard ar/tar tooling and verifies that dpkg --info can parse it. This
// does NOT install anything (no root required) — it only confirms dpkg can
// read the package format that our installer will produce.
func TestIntegration_DpkgDryRun(t *testing.T) {
	requireCommand(t, "dpkg")

	if _, err := exec.LookPath("ar"); err != nil {
		t.Skipf("ar not found on PATH — required to build minimal .deb: %v", err)
	}

	tmpDir := t.TempDir()

	// Step 1: Write debian-binary file (required first member of .deb ar archive).
	debianBinaryPath := filepath.Join(tmpDir, "debian-binary")
	if err := os.WriteFile(debianBinaryPath, []byte("2.0\n"), 0600); err != nil {
		t.Fatalf("write debian-binary: %v", err)
	}

	// Step 2: Create control.tar.gz with a minimal control file.
	controlTarPath := filepath.Join(tmpDir, "control.tar.gz")
	if err := writeControlTarGz(controlTarPath); err != nil {
		t.Fatalf("write control.tar.gz: %v", err)
	}

	// Step 3: Create an empty data.tar.gz (no files to install).
	dataTarPath := filepath.Join(tmpDir, "data.tar.gz")
	if err := writeEmptyTarGz(dataTarPath); err != nil {
		t.Fatalf("write data.tar.gz: %v", err)
	}

	// Step 4: Combine into a .deb using ar.
	debPath := filepath.Join(tmpDir, "test-integration.deb")
	stdout, stderr, err := runCommand(t,
		"ar", "r", debPath,
		debianBinaryPath, controlTarPath, dataTarPath,
	)
	if err != nil {
		t.Fatalf("ar create .deb failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}

	// Step 5: Verify dpkg can parse the package metadata without installing.
	stdout, stderr, err = runCommand(t, "dpkg", "--info", debPath)
	if err != nil {
		t.Fatalf("dpkg --info failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}
	if !strings.Contains(stdout, "test-integration") {
		t.Errorf("expected package name 'test-integration' in dpkg --info output; got %q", stdout)
	}
}

// TestIntegration_ElevationToolExists verifies that at least one elevation
// tool (pkexec or sudo) is available on the CI runner. installLinux uses
// pkexec first and falls back to sudo; this test ensures the fallback chain
// will succeed.
func TestIntegration_ElevationToolExists(t *testing.T) {
	_, pkexecErr := exec.LookPath("pkexec")
	_, sudoErr := exec.LookPath("sudo")

	if pkexecErr != nil && sudoErr != nil {
		t.Fatal("neither pkexec nor sudo found on PATH — dpkg installation cannot be elevated")
	}

	if pkexecErr == nil {
		t.Log("pkexec found (preferred elevation tool)")
	} else {
		t.Log("sudo found (fallback elevation tool; pkexec not available)")
	}
}

// writeControlTarGz writes a minimal control.tar.gz to path.
// The control file contains the minimum fields required by dpkg.
func writeControlTarGz(path string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	gw := gzip.NewWriter(f)
	defer gw.Close()

	tw := tar.NewWriter(gw)
	defer tw.Close()

	const controlContent = "Package: test-integration\n" +
		"Version: 1.0.0\n" +
		"Architecture: amd64\n" +
		"Maintainer: CentroidX Test <test@example.com>\n" +
		"Description: Integration test package\n" +
		" A minimal .deb for integration testing only.\n"

	hdr := &tar.Header{
		Name: "./control",
		Mode: 0600,
		Size: int64(len(controlContent)),
	}
	if err := tw.WriteHeader(hdr); err != nil {
		return err
	}
	_, err = tw.Write([]byte(controlContent))
	return err
}

// writeEmptyTarGz writes a valid but empty tar.gz archive to path.
func writeEmptyTarGz(path string) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	gw := gzip.NewWriter(f)
	defer gw.Close()

	tw := tar.NewWriter(gw)
	return tw.Close()
}
