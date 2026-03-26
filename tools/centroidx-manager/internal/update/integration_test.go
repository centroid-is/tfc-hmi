//go:build integration

package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"runtime"
	"testing"
	"time"

	githubclient "github.com/centroid-is/centroidx-manager/internal/github"
	gogithub "github.com/google/go-github/v84/github"
)

const (
	integrationOwner = "centroid-is"
	integrationRepo  = "tfc-hmi"
	// integrationTimeout is the maximum duration for all network calls in each test.
	integrationTimeout = 120 * time.Second
)

// requireToken reads GITHUB_TOKEN from the environment and skips the test
// if it is not set. Returns the token on success.
func requireToken(t *testing.T) string {
	t.Helper()
	token := os.Getenv("GITHUB_TOKEN")
	if token == "" {
		t.Skip("GITHUB_TOKEN not set — skipping integration test")
	}
	return token
}

// suitableRelease holds the release and extracted asset URLs found by requireRelease.
type suitableRelease struct {
	release       *gogithub.RepositoryRelease
	assetURL      string
	assetFilename string
	checksumURL   string
}

// requireRelease calls ListReleases on the client, finds the first release that
// has both a platform asset for the current OS/arch and a SHA256SUMS.txt asset,
// and returns it. Skips the test if no releases exist or none has the right assets.
func requireRelease(t *testing.T, client githubclient.ReleasesClient) suitableRelease {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), integrationTimeout)
	defer cancel()

	releases, err := client.ListReleases(ctx)
	if err != nil {
		t.Fatalf("ListReleases failed: %v", err)
	}
	if len(releases) == 0 {
		t.Skip("no releases found in centroid-is/tfc-hmi — skipping integration test")
	}

	platformAssetName := selectPlatformAssetName()

	for _, r := range releases {
		var platformAsset, checksumAsset *gogithub.ReleaseAsset
		for _, a := range r.Assets {
			name := a.GetName()
			if name == platformAssetName {
				platformAsset = a
			}
			if name == "SHA256SUMS.txt" {
				checksumAsset = a
			}
		}
		if platformAsset != nil && checksumAsset != nil {
			return suitableRelease{
				release:       r,
				assetURL:      platformAsset.GetBrowserDownloadURL(),
				assetFilename: platformAsset.GetName(),
				checksumURL:   checksumAsset.GetBrowserDownloadURL(),
			}
		}
	}

	t.Skipf(
		"no release in centroid-is/tfc-hmi has both %q and SHA256SUMS.txt — skipping (running on %s/%s)",
		platformAssetName, runtime.GOOS, runtime.GOARCH,
	)
	return suitableRelease{} // unreachable — t.Skipf does not return
}

// TestIntegration_ListReleases verifies that the real GitHub Releases API
// returns at least one release for centroid-is/tfc-hmi.
func TestIntegration_ListReleases(t *testing.T) {
	token := requireToken(t)
	client := githubclient.NewClient(integrationOwner, integrationRepo, token, "")

	ctx, cancel := context.WithTimeout(context.Background(), integrationTimeout)
	defer cancel()

	releases, err := client.ListReleases(ctx)
	if err != nil {
		t.Fatalf("ListReleases returned error: %v", err)
	}

	if len(releases) == 0 {
		t.Skip("no releases found in centroid-is/tfc-hmi — skipping (expected at least 1 release)")
	}

	t.Logf("ListReleases returned %d releases; first tag: %s", len(releases), releases[0].GetTagName())
}

// TestIntegration_DownloadAndVerifyChecksum downloads a real asset from the
// latest suitable GitHub Release and verifies the DownloadAndVerify function
// returns no error and produces a non-empty file on disk.
func TestIntegration_DownloadAndVerifyChecksum(t *testing.T) {
	token := requireToken(t)
	client := githubclient.NewClient(integrationOwner, integrationRepo, token, "")
	sr := requireRelease(t, client)

	t.Logf("Using release %s, asset %q", sr.release.GetTagName(), sr.assetFilename)
	t.Logf("Asset URL: %s", sr.assetURL)
	t.Logf("Checksum URL: %s", sr.checksumURL)

	ctx, cancel := context.WithTimeout(context.Background(), integrationTimeout)
	defer cancel()

	destDir := t.TempDir()
	path, err := DownloadAndVerify(ctx, sr.assetURL, sr.checksumURL, sr.assetFilename, destDir, nil)
	if err != nil {
		t.Fatalf("DownloadAndVerify returned error: %v", err)
	}

	if path == "" {
		t.Fatal("DownloadAndVerify returned empty path")
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("downloaded file does not exist at %q: %v", path, err)
	}
	if info.Size() == 0 {
		t.Errorf("downloaded file at %q has size 0 (expected > 0)", path)
	}

	t.Logf("Downloaded and verified %q (%d bytes) to %s", sr.assetFilename, info.Size(), path)
}

// TestIntegration_ChecksumActuallyMatches downloads a real asset, independently
// re-computes its SHA256, and confirms it matches the SHA256SUMS.txt entry —
// verifying the end-to-end checksum pipeline is consistent.
func TestIntegration_ChecksumActuallyMatches(t *testing.T) {
	token := requireToken(t)
	client := githubclient.NewClient(integrationOwner, integrationRepo, token, "")
	sr := requireRelease(t, client)

	t.Logf("Using release %s, asset %q", sr.release.GetTagName(), sr.assetFilename)

	ctx, cancel := context.WithTimeout(context.Background(), integrationTimeout)
	defer cancel()

	destDir := t.TempDir()
	path, err := DownloadAndVerify(ctx, sr.assetURL, sr.checksumURL, sr.assetFilename, destDir, nil)
	if err != nil {
		t.Fatalf("DownloadAndVerify returned error: %v", err)
	}

	// Independently compute the SHA256 of the downloaded file.
	computedHash, err := computeFileSHA256(path)
	if err != nil {
		t.Fatalf("compute SHA256 of downloaded file: %v", err)
	}

	// Download SHA256SUMS.txt independently to parse the expected hash.
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, sr.checksumURL, nil)
	if err != nil {
		t.Fatalf("create checksum request: %v", err)
	}
	// Include auth for private repos.
	if token != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", token))
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("download SHA256SUMS.txt: %v", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("download SHA256SUMS.txt: HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read SHA256SUMS.txt body: %v", err)
	}

	hashes := ParseSHA256SUMS(string(body))
	expectedHash, ok := hashes[sr.assetFilename]
	if !ok {
		t.Fatalf("SHA256SUMS.txt does not contain entry for %q; available entries: %v", sr.assetFilename, keys(hashes))
	}

	if computedHash != expectedHash {
		t.Errorf("checksum mismatch:\n  computed: %s\n  expected: %s", computedHash, expectedHash)
	} else {
		t.Logf("SHA256 verified: %s matches SHA256SUMS.txt entry for %q", computedHash, sr.assetFilename)
	}
}

// computeFileSHA256 returns the hex-encoded SHA256 hash of the file at path.
func computeFileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", fmt.Errorf("hash file: %w", err)
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// keys returns the keys of a map[string]string as a slice (for diagnostic output).
func keys(m map[string]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
