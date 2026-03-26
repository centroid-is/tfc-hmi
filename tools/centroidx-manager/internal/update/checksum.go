package update

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"strings"
)

// ParseSHA256SUMS parses a SHA256SUMS.txt file content (lines of "hash  filename")
// into a filename -> hash map.
func ParseSHA256SUMS(content string) map[string]string {
	result := make(map[string]string)
	for _, line := range strings.Split(strings.TrimSpace(content), "\n") {
		parts := strings.Fields(line)
		if len(parts) == 2 {
			result[parts[1]] = parts[0] // filename -> hash
		}
	}
	return result
}

// VerifyFile verifies the SHA256 checksum of a file against an expected hex string.
// Uses constant-time comparison to prevent timing attacks.
func VerifyFile(filePath, expectedHex string) error {
	f, err := os.Open(filePath)
	if err != nil {
		return fmt.Errorf("open file for verification: %w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return fmt.Errorf("hash file: %w", err)
	}
	actualHex := hex.EncodeToString(h.Sum(nil))

	// Constant-time comparison prevents timing attacks
	if subtle.ConstantTimeCompare([]byte(actualHex), []byte(expectedHex)) != 1 {
		return fmt.Errorf("checksum mismatch: got %s, want %s", actualHex, expectedHex)
	}
	return nil
}
