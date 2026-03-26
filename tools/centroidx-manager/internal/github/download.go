package github

import (
	"context"
	"fmt"
	"io"
	"net/http"
)

// progressWriter tracks bytes written and invokes an onProgress callback.
type progressWriter struct {
	downloaded int64
	total      int64
	onProgress func(downloaded, total int64)
}

func (pw *progressWriter) Write(p []byte) (int, error) {
	n := len(p)
	pw.downloaded += int64(n)
	if pw.onProgress != nil {
		pw.onProgress(pw.downloaded, pw.total)
	}
	return n, nil
}

// DownloadWithProgress downloads the resource at url into dest, calling
// onProgress with (downloaded, total) after each chunk. total is the
// expected size in bytes (use 0 or -1 if unknown).
func DownloadWithProgress(ctx context.Context, url string, dest io.Writer, total int64, onProgress func(int64, int64)) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("GET %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("download failed: HTTP %d for %s", resp.StatusCode, url)
	}

	// If the caller did not supply a total, fall back to Content-Length.
	if total <= 0 {
		total = resp.ContentLength
	}

	pw := &progressWriter{total: total, onProgress: onProgress}
	tee := io.TeeReader(resp.Body, pw)
	if _, err := io.Copy(dest, tee); err != nil {
		return fmt.Errorf("copy download body: %w", err)
	}
	return nil
}
