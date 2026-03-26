package update

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"testing"
)

func TestParseSHA256SUMS(t *testing.T) {
	content := "abc123  file1.msix\ndef456  file2.deb\n"
	got := ParseSHA256SUMS(content)

	if got["file1.msix"] != "abc123" {
		t.Errorf("expected file1.msix -> abc123, got %q", got["file1.msix"])
	}
	if got["file2.deb"] != "def456" {
		t.Errorf("expected file2.deb -> def456, got %q", got["file2.deb"])
	}
	if len(got) != 2 {
		t.Errorf("expected 2 entries, got %d", len(got))
	}
}

func TestParseSHA256SUMS_TrailingNewline(t *testing.T) {
	content := "abc123  file1.msix\n\n"
	got := ParseSHA256SUMS(content)
	if len(got) != 1 {
		t.Errorf("expected 1 entry, got %d", len(got))
	}
}

func TestParseSHA256SUMS_Empty(t *testing.T) {
	got := ParseSHA256SUMS("")
	if len(got) != 0 {
		t.Errorf("expected empty map, got %d entries", len(got))
	}
}

func TestVerifyFile(t *testing.T) {
	// Create temp file with known content
	f, err := os.CreateTemp("", "checksum-test-*.bin")
	if err != nil {
		t.Fatal(err)
	}
	defer os.Remove(f.Name())

	content := []byte("hello world")
	if _, err := f.Write(content); err != nil {
		t.Fatal(err)
	}
	f.Close()

	// Compute expected SHA256
	h := sha256.New()
	h.Write(content)
	expectedHex := hex.EncodeToString(h.Sum(nil))

	// Correct hash must succeed
	if err := VerifyFile(f.Name(), expectedHex); err != nil {
		t.Errorf("VerifyFile with correct hash failed: %v", err)
	}

	// Wrong hash must fail
	if err := VerifyFile(f.Name(), "0000000000000000000000000000000000000000000000000000000000000000"); err == nil {
		t.Error("VerifyFile with wrong hash should have returned error")
	}
}

func TestVerifyFile_FileNotFound(t *testing.T) {
	err := VerifyFile("/nonexistent/path/file.bin", "abc123")
	if err == nil {
		t.Error("VerifyFile with nonexistent file should return error")
	}
}
