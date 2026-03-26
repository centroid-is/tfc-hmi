//go:build windows

package platform

import (
	"os"
	"path/filepath"
	"testing"
)

// TestExtractManager_FirstRun verifies that ExtractManager copies the binary
// to the expected APPDATA destination when it has not been extracted yet.
func TestExtractManager_FirstRun(t *testing.T) {
	// Create a temp directory to serve as both source exe dir and APPDATA root.
	tmpDir := t.TempDir()

	// Write a dummy "manager binary" as the source.
	srcPath := filepath.Join(tmpDir, "centroidx-manager.exe")
	if err := os.WriteFile(srcPath, []byte("fake binary content"), 0o755); err != nil {
		t.Fatalf("write dummy binary: %v", err)
	}

	// Point APPDATA to a subdirectory so we can verify the dest layout.
	appdata := filepath.Join(tmpDir, "appdata")
	t.Setenv("APPDATA", appdata)

	// Override os.Executable via the testable helper.
	err := extractManagerFrom(srcPath, appdata)
	if err != nil {
		t.Fatalf("extractManagerFrom: %v", err)
	}

	dest := filepath.Join(appdata, "centroidx", "manager", "centroidx-manager.exe")
	info, err := os.Stat(dest)
	if err != nil {
		t.Fatalf("dest file not found: %v", err)
	}
	if info.Size() == 0 {
		t.Error("dest file is empty")
	}
}

// TestExtractManager_AlreadyExtracted verifies that a second call with the same
// source size is a no-op (no extra writes).
func TestExtractManager_AlreadyExtracted(t *testing.T) {
	tmpDir := t.TempDir()
	srcContent := []byte("fake binary content")

	srcPath := filepath.Join(tmpDir, "centroidx-manager.exe")
	if err := os.WriteFile(srcPath, srcContent, 0o755); err != nil {
		t.Fatalf("write dummy binary: %v", err)
	}

	appdata := filepath.Join(tmpDir, "appdata")
	destDir := filepath.Join(appdata, "centroidx", "manager")
	if err := os.MkdirAll(destDir, 0o755); err != nil {
		t.Fatalf("create dest dir: %v", err)
	}
	dest := filepath.Join(destDir, "centroidx-manager.exe")
	// Pre-write dest with same content (same size).
	if err := os.WriteFile(dest, srcContent, 0o755); err != nil {
		t.Fatalf("write dest: %v", err)
	}
	originalModTime := mustModTime(t, dest)

	// Second extraction — must be no-op.
	if err := extractManagerFrom(srcPath, appdata); err != nil {
		t.Fatalf("extractManagerFrom (second call): %v", err)
	}

	newModTime := mustModTime(t, dest)
	if newModTime != originalModTime {
		t.Error("dest file was modified even though sizes matched (expected no-op)")
	}
}

// TestIsRunningFromMSIX verifies the path detection heuristic.
func TestIsRunningFromMSIX(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		{`C:\Program Files\WindowsApps\CentroidX_1.0\centroidx-manager.exe`, true},
		{`C:\Users\Alice\AppData\Roaming\centroidx\manager\centroidx-manager.exe`, false},
		{`C:\Program Files\centroidx\centroidx-manager.exe`, false},
	}
	for _, tc := range cases {
		got := pathIsFromMSIX(tc.path)
		if got != tc.want {
			t.Errorf("pathIsFromMSIX(%q) = %v, want %v", tc.path, got, tc.want)
		}
	}
}

func mustModTime(t *testing.T, path string) int64 {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat %q: %v", path, err)
	}
	return info.ModTime().UnixNano()
}
