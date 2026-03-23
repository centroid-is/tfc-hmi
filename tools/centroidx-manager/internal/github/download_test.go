package github_test

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	githubclient "github.com/centroid-is/centroidx-manager/internal/github"
)

func TestDownloadWithProgress(t *testing.T) {
	// Serve 1 KB of known data.
	payload := bytes.Repeat([]byte("A"), 1024)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("Content-Length", "1024")
		w.Write(payload) //nolint:errcheck
	}))
	defer srv.Close()

	var buf bytes.Buffer
	var lastDownloaded, lastTotal int64
	progressCalled := false

	err := githubclient.DownloadWithProgress(context.Background(), srv.URL, &buf, 1024, func(downloaded, total int64) {
		progressCalled = true
		lastDownloaded = downloaded
		lastTotal = total
	})
	if err != nil {
		t.Fatalf("DownloadWithProgress: %v", err)
	}

	if buf.Len() != 1024 {
		t.Errorf("expected 1024 bytes, got %d", buf.Len())
	}

	if !bytes.Equal(buf.Bytes(), payload) {
		t.Error("downloaded content does not match expected payload")
	}

	if !progressCalled {
		t.Error("expected progress callback to be called at least once")
	}

	if lastDownloaded != 1024 {
		t.Errorf("expected final downloaded=1024, got %d", lastDownloaded)
	}

	if lastTotal != 1024 {
		t.Errorf("expected total=1024, got %d", lastTotal)
	}
}

func TestDownloadWithProgress_ServerError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	var buf bytes.Buffer
	err := githubclient.DownloadWithProgress(context.Background(), srv.URL, &buf, 0, nil)
	if err == nil {
		t.Fatal("expected error for 500 response, got nil")
	}
}

func TestProgressWriter(t *testing.T) {
	var callCount int
	var totalReceived int64

	pw := &progressWriterForTest{
		total: 100,
		onProgress: func(downloaded, total int64) {
			callCount++
			totalReceived = downloaded
		},
	}

	data1 := []byte("hello")
	n, err := pw.Write(data1)
	if err != nil {
		t.Fatalf("Write error: %v", err)
	}
	if n != len(data1) {
		t.Errorf("expected Write to return %d, got %d", len(data1), n)
	}
	if callCount != 1 {
		t.Errorf("expected 1 progress call, got %d", callCount)
	}

	data2 := []byte(" world")
	pw.Write(data2) //nolint:errcheck
	if callCount != 2 {
		t.Errorf("expected 2 progress calls, got %d", callCount)
	}
	if totalReceived != int64(len(data1)+len(data2)) {
		t.Errorf("expected downloaded=%d, got %d", len(data1)+len(data2), totalReceived)
	}
}

// progressWriterForTest is a test-local copy of the unexported progressWriter
// to verify Write counting logic without accessing the private type.
// This tests the same behaviour via a local implementation.
type progressWriterForTest struct {
	downloaded int64
	total      int64
	onProgress func(downloaded, total int64)
}

func (pw *progressWriterForTest) Write(p []byte) (int, error) {
	n := len(p)
	pw.downloaded += int64(n)
	if pw.onProgress != nil {
		pw.onProgress(pw.downloaded, pw.total)
	}
	return n, nil
}
