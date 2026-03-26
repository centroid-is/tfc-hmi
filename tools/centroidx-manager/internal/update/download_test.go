package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
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
