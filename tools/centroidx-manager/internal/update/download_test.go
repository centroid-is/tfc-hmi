package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const testAssetFilename = "centroidx-setup.msix"
const testAssetContent = "fake MSIX binary content for testing"

// buildChecksumContent generates a SHA256SUMS.txt line for the given content and filename.
func buildChecksumContent(content, filename string) string {
	h := sha256.Sum256([]byte(content))
	return hex.EncodeToString(h[:]) + "  " + filename + "\n"
}

// newTestServer creates an httptest server that serves the asset and checksums file.
// checksumContent allows the caller to inject arbitrary (including wrong) checksum data.
func newTestServer(t *testing.T, assetContent, checksumContent string) (*httptest.Server, string, string) {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/asset", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", fmt.Sprintf("%d", len(assetContent)))
		_, _ = w.Write([]byte(assetContent))
	})
	mux.HandleFunc("/SHA256SUMS.txt", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(checksumContent))
	})
	srv := httptest.NewServer(mux)
	assetURL := srv.URL + "/asset"
	checksumURL := srv.URL + "/SHA256SUMS.txt"
	return srv, assetURL, checksumURL
}

func TestDownloadAndVerify_Success(t *testing.T) {
	checksumContent := buildChecksumContent(testAssetContent, testAssetFilename)
	srv, assetURL, checksumURL := newTestServer(t, testAssetContent, checksumContent)
	defer srv.Close()

	destDir := t.TempDir()
	path, err := DownloadAndVerify(context.Background(), assetURL, checksumURL, testAssetFilename, destDir, nil)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	if path == "" {
		t.Fatal("expected non-empty file path, got empty string")
	}
	if _, statErr := os.Stat(path); os.IsNotExist(statErr) {
		t.Fatalf("returned path %q does not exist on disk", path)
	}
	// Verify the file is in destDir.
	dir := filepath.Dir(path)
	if dir != destDir {
		t.Errorf("expected file in destDir %q, got %q", destDir, dir)
	}
	// Verify contents are correct.
	data, readErr := os.ReadFile(path)
	if readErr != nil {
		t.Fatalf("read verified file: %v", readErr)
	}
	if string(data) != testAssetContent {
		t.Errorf("file content mismatch: got %q, want %q", string(data), testAssetContent)
	}
}

func TestDownloadAndVerify_ChecksumMismatch(t *testing.T) {
	// Serve a checksum file with all-zeros hash (intentionally wrong).
	wrongChecksum := "0000000000000000000000000000000000000000000000000000000000000000  " + testAssetFilename + "\n"
	srv, assetURL, checksumURL := newTestServer(t, testAssetContent, wrongChecksum)
	defer srv.Close()

	destDir := t.TempDir()
	_, err := DownloadAndVerify(context.Background(), assetURL, checksumURL, testAssetFilename, destDir, nil)
	if err == nil {
		t.Fatal("expected checksum mismatch error, got nil")
	}
	if !containsString(err.Error(), "checksum mismatch") {
		t.Errorf("error message should contain 'checksum mismatch', got: %q", err.Error())
	}

	// Verify no temp file was left behind.
	entries, dirErr := os.ReadDir(destDir)
	if dirErr != nil {
		t.Fatalf("read destDir: %v", dirErr)
	}
	if len(entries) != 0 {
		names := make([]string, len(entries))
		for i, e := range entries {
			names[i] = e.Name()
		}
		t.Errorf("expected temp file cleaned up after checksum mismatch, found: %v", names)
	}
}

func TestDownloadAndVerify_DownloadError(t *testing.T) {
	// Server returns 500 for the asset.
	mux := http.NewServeMux()
	mux.HandleFunc("/asset", func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "internal server error", http.StatusInternalServerError)
	})
	mux.HandleFunc("/SHA256SUMS.txt", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(buildChecksumContent(testAssetContent, testAssetFilename)))
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	destDir := t.TempDir()
	_, err := DownloadAndVerify(context.Background(), srv.URL+"/asset", srv.URL+"/SHA256SUMS.txt", testAssetFilename, destDir, nil)
	if err == nil {
		t.Fatal("expected error for HTTP 500, got nil")
	}
}

func TestDownloadAndVerify_Progress(t *testing.T) {
	checksumContent := buildChecksumContent(testAssetContent, testAssetFilename)
	srv, assetURL, checksumURL := newTestServer(t, testAssetContent, checksumContent)
	defer srv.Close()

	destDir := t.TempDir()

	var progressCalls []int64
	onProgress := func(downloaded, total int64) {
		progressCalls = append(progressCalls, downloaded)
	}

	_, err := DownloadAndVerify(context.Background(), assetURL, checksumURL, testAssetFilename, destDir, onProgress)
	if err != nil {
		t.Fatalf("expected no error, got: %v", err)
	}
	if len(progressCalls) == 0 {
		t.Error("expected progress callback to be called at least once, got zero calls")
	}
	// Progress values must be monotonically non-decreasing.
	for i := 1; i < len(progressCalls); i++ {
		if progressCalls[i] < progressCalls[i-1] {
			t.Errorf("progress went backward: calls[%d]=%d < calls[%d]=%d",
				i, progressCalls[i], i-1, progressCalls[i-1])
		}
	}
}

// containsString is a simple substring check used in test assertions.
func containsString(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(substr) == 0 ||
		func() bool {
			for i := 0; i <= len(s)-len(substr); i++ {
				if s[i:i+len(substr)] == substr {
					return true
				}
			}
			return false
		}())
}

// ---- replaceFile ------------------------------------------------------------

// os.Rename on Windows is MoveFileEx(MOVEFILE_REPLACE_EXISTING), which fails
// with ACCESS_DENIED or SHARING_VIOLATION when the destination is open without
// FILE_SHARE_DELETE — a Defender scan of the just-written package, or AppX
// staging still holding a reference. Because the payload lands in %TEMP% under
// a fixed name and is never cleaned up, that failure then repeats on every
// later update in the same session. Removing the destination first turns the
// replace into a create.
//
// An existing empty directory at the destination stands in for the Windows
// case here: os.Rename onto it fails on every platform, and only succeeds if
// the destination was removed first.
func TestReplaceFile_RemovesTheDestinationFirst(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")

	if err := os.WriteFile(src, []byte("new payload"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(dst, 0o755); err != nil {
		t.Fatal(err)
	}

	if err := replaceFile(src, dst); err != nil {
		t.Fatalf("replaceFile did not clear the destination: %v", err)
	}
	got, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("destination is not a readable file: %v", err)
	}
	if string(got) != "new payload" {
		t.Errorf("destination has the wrong content: %q", got)
	}
}

func TestReplaceFile_OverwritesAnExistingPayload(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	dst := filepath.Join(dir, "dst")

	if err := os.WriteFile(src, []byte("new payload"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dst, []byte("stale payload from a previous update"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := replaceFile(src, dst); err != nil {
		t.Fatalf("replaceFile returned error: %v", err)
	}
	got, _ := os.ReadFile(dst)
	if string(got) != "new payload" {
		t.Errorf("destination has the wrong content: %q", got)
	}
	if _, err := os.Stat(src); !os.IsNotExist(err) {
		t.Errorf("expected the source to be consumed, stat error was %v", err)
	}
}

// A scanner holding the file usually lets go within a moment, so a transient
// failure must be retried rather than failing the whole update.
func TestReplaceFile_RetriesATransientFailure(t *testing.T) {
	origRename, origDelay := renameFile, renameRetryDelay
	t.Cleanup(func() { renameFile, renameRetryDelay = origRename, origDelay })
	renameRetryDelay = time.Millisecond

	attempts := 0
	renameFile = func(oldpath, newpath string) error {
		attempts++
		if attempts < 3 {
			return errors.New("Access is denied.")
		}
		return origRename(oldpath, newpath)
	}

	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	if err := os.WriteFile(src, []byte("payload"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := replaceFile(src, filepath.Join(dir, "dst")); err != nil {
		t.Fatalf("expected the retry to succeed, got: %v", err)
	}
	if attempts != 3 {
		t.Errorf("expected 3 attempts, got %d", attempts)
	}
}

// The retry is bounded — a destination that is permanently locked must fail
// with the underlying error rather than spin.
func TestReplaceFile_GivesUpAndReportsTheRealError(t *testing.T) {
	origRename, origDelay := renameFile, renameRetryDelay
	t.Cleanup(func() { renameFile, renameRetryDelay = origRename, origDelay })
	renameRetryDelay = time.Millisecond

	attempts := 0
	renameFile = func(_, _ string) error {
		attempts++
		return errors.New("Access is denied.")
	}

	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	if err := os.WriteFile(src, []byte("payload"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := replaceFile(src, filepath.Join(dir, "dst"))
	if err == nil {
		t.Fatal("expected an error, got nil")
	}
	if !strings.Contains(err.Error(), "Access is denied") {
		t.Errorf("expected the underlying error to be reported, got: %v", err)
	}
	if attempts < 2 {
		t.Errorf("expected more than one attempt, got %d", attempts)
	}
	if attempts > 10 {
		t.Errorf("retry is not bounded: %d attempts", attempts)
	}
}
