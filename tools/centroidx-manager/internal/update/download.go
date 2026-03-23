package update

import "context"

// DownloadAndVerify fetches an asset from assetURL, saves it to a temp file in destDir,
// downloads SHA256SUMS.txt from checksumURL, verifies the asset matches the expected hash,
// and returns the path to the verified file.
//
// assetFilename is the filename used to look up the hash in SHA256SUMS.txt.
// onProgress is called with (downloaded, total) bytes after each chunk (may be nil).
func DownloadAndVerify(ctx context.Context, assetURL string, checksumURL string, assetFilename string, destDir string, onProgress func(int64, int64)) (string, error) {
	// stub — returns empty path and nil error
	_ = ctx
	_ = assetURL
	_ = checksumURL
	_ = assetFilename
	_ = destDir
	_ = onProgress
	return "", nil
}
