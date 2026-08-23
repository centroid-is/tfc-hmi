package update

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	ghdownload "github.com/centroid-is/centroidx-manager/internal/github"
)

// DownloadAndVerify fetches an asset from assetURL, saves it to a temp file in destDir,
// downloads SHA256SUMS.txt from checksumURL, verifies the asset's SHA256 hash, and
// returns the path to the verified file.
//
// assetFilename is the key used to look up the expected hash in SHA256SUMS.txt.
// onProgress is called with (downloaded, total) bytes after each chunk; may be nil.
//
// On checksum failure the temporary file is removed before returning the error.
// On download failure the temporary file is removed before returning the error.
func DownloadAndVerify(ctx context.Context, assetURL string, checksumURL string, assetFilename string, destDir string, onProgress func(int64, int64)) (string, error) {
	// Step 1: Download and parse SHA256SUMS.txt.
	expectedHash, err := fetchExpectedHash(ctx, checksumURL, assetFilename)
	if err != nil {
		return "", err
	}

	// Step 2: Create temp file in destDir.
	tmpFile, err := os.CreateTemp(destDir, "centroidx-download-*")
	if err != nil {
		return "", fmt.Errorf("create temp file: %w", err)
	}
	tmpPath := tmpFile.Name()

	// Ensure temp file is cleaned up on any error path.
	cleanup := func() {
		tmpFile.Close()
		os.Remove(tmpPath)
	}

	// Step 3: Download the asset into the temp file.
	if err := ghdownload.DownloadWithProgress(ctx, assetURL, tmpFile, 0, onProgress); err != nil {
		cleanup()
		return "", fmt.Errorf("download asset: %w", err)
	}
	tmpFile.Close()

	// Step 4: Verify the checksum.
	if err := VerifyFile(tmpPath, expectedHash); err != nil {
		os.Remove(tmpPath)
		return "", err // VerifyFile already says "checksum mismatch: ..."
	}

	// Step 5: Rename temp file to the final name.
	finalPath := filepath.Join(destDir, assetFilename)
	if err := replaceFile(tmpPath, finalPath); err != nil {
		os.Remove(tmpPath)
		return "", fmt.Errorf("rename verified download: %w", err)
	}

	return finalPath, nil
}

// renameFile is os.Rename, indirected so tests can drive the retry path
// without needing a real locked file.
var renameFile = os.Rename

// renameAttempts and renameRetryDelay bound the retry in replaceFile. A
// scanner normally releases a file within a moment; anything longer is a real
// problem and should be reported rather than waited out, because the update UI
// is sitting in front of an operator.
const renameAttempts = 4

var renameRetryDelay = 250 * time.Millisecond

// replaceFile moves tmpPath onto finalPath, replacing whatever is already
// there.
//
// os.Rename on Windows is MoveFileEx(MOVEFILE_REPLACE_EXISTING), which fails
// with ACCESS_DENIED or SHARING_VIOLATION when the destination is open without
// FILE_SHARE_DELETE — Defender scanning the package we just wrote, or AppX
// staging still holding a reference from the previous install. The payload
// lands in os.TempDir() under a fixed per-platform name, so once that happens
// every later update in the same session hits the same locked file and fails
// the same way, until something clears %TEMP%. rename(2) on Unix replaces
// regardless of open handles, so this only bites Windows.
//
// Removing the destination first turns the usual case into a create rather
// than a replace, and the bounded retry covers a scanner that has not let go
// yet.
func replaceFile(tmpPath, finalPath string) error {
	var err error
	for attempt := range renameAttempts {
		if attempt > 0 {
			time.Sleep(renameRetryDelay)
		}
		// Best-effort: on a first install there is nothing to remove, and a
		// destination we cannot remove may still be renamable.
		_ = os.Remove(finalPath)

		if err = renameFile(tmpPath, finalPath); err == nil {
			return nil
		}
	}
	return err
}

// fetchExpectedHash downloads checksumURL, parses it as SHA256SUMS.txt format,
// and returns the expected hex hash for assetFilename.
func fetchExpectedHash(ctx context.Context, checksumURL, assetFilename string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, checksumURL, nil)
	if err != nil {
		return "", fmt.Errorf("create checksum request: %w", err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("GET checksum file: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download checksum file: HTTP %d for %s", resp.StatusCode, checksumURL)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read checksum file: %w", err)
	}

	hashes := ParseSHA256SUMS(string(body))
	hash, ok := hashes[assetFilename]
	if !ok {
		return "", fmt.Errorf("checksum file does not contain entry for %q", assetFilename)
	}
	return hash, nil
}
