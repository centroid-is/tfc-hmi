//go:build integration && darwin

package platform

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestIntegration_HdiutilAvailable verifies that hdiutil is present on the
// macOS CI runner. If this test fails, the runner image is missing the
// expected macOS disk image tooling.
func TestIntegration_HdiutilAvailable(t *testing.T) {
	requireCommand(t, "hdiutil")

	stdout, stderr, err := runCommand(t, "hdiutil", "info")
	if err != nil {
		t.Fatalf("hdiutil info failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}
	// hdiutil info may produce empty output when no images are mounted — that's fine.
	// A zero exit code is sufficient to confirm hdiutil works.
	t.Logf("hdiutil info output: %s", stdout)
}

// TestIntegration_HdiutilCreateMountUnmount exercises the full DMG lifecycle
// that installDarwin uses: create a DMG from a temp directory, attach it,
// parse the mount point (using parseMountPoint from installer.go — same
// package access), verify the volume exists, then detach. This validates the
// complete workflow on a real macOS runner.
func TestIntegration_HdiutilCreateMountUnmount(t *testing.T) {
	requireCommand(t, "hdiutil")

	// Step 1: Create a source directory with a small test file.
	srcDir := t.TempDir()
	testFile := filepath.Join(srcDir, "centroidx-test.txt")
	if err := os.WriteFile(testFile, []byte("integration test payload"), 0600); err != nil {
		t.Fatalf("write test file: %v", err)
	}

	// Step 2: Create a compressed DMG from the source directory.
	outDir := t.TempDir()
	dmgPath := filepath.Join(outDir, "test-integration.dmg")

	stdout, stderr, err := runCommand(t,
		"hdiutil", "create",
		"-volname", "CentroidXTest",
		"-srcfolder", srcDir,
		"-format", "UDZO",
		dmgPath,
	)
	if err != nil {
		t.Fatalf("hdiutil create failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}

	// Step 3: Attach the DMG.
	plistOut, stderr, err := runCommand(t,
		"hdiutil", "attach",
		"-nobrowse", "-plist",
		dmgPath,
	)
	if err != nil {
		t.Fatalf("hdiutil attach failed: %v\nplist: %s\nstderr: %s", err, plistOut, stderr)
	}

	// Step 4: Parse the mount point using the package function (same package access).
	mountPoint := parseMountPoint([]byte(plistOut))
	if mountPoint == "" {
		t.Fatalf("parseMountPoint returned empty string from hdiutil output:\n%s", plistOut)
	}
	if !strings.HasPrefix(mountPoint, "/Volumes/") {
		t.Errorf("expected mount point to start with /Volumes/; got %q", mountPoint)
	}

	// Ensure we always detach, even if assertions fail.
	defer func() {
		stdout, stderr, err := runCommand(t, "hdiutil", "detach", mountPoint, "-quiet")
		if err != nil {
			t.Logf("hdiutil detach failed (may have already been detached): %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
		}
	}()

	// Step 5: Verify the mount point directory exists.
	info, err := os.Stat(mountPoint)
	if err != nil {
		t.Fatalf("mount point %q does not exist after attach: %v", mountPoint, err)
	}
	if !info.IsDir() {
		t.Errorf("mount point %q is not a directory", mountPoint)
	}

	t.Logf("DMG mounted at: %s", mountPoint)
}

// TestIntegration_XattrAvailable verifies that xattr is on PATH on the macOS
// CI runner. installDarwin uses xattr to strip the quarantine attribute after
// copying the .app bundle to /Applications.
func TestIntegration_XattrAvailable(t *testing.T) {
	stdout, stderr, err := runCommand(t, "which", "xattr")
	if err != nil {
		t.Fatalf("which xattr failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}
	path := strings.TrimSpace(stdout)
	if path == "" {
		t.Fatal("xattr not found on PATH — quarantine removal will not work on this runner")
	}
	t.Logf("xattr found at: %s", path)
}
