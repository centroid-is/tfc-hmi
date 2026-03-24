package update

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"runtime"
	"sort"
	"strings"
	"time"

	"github.com/Masterminds/semver/v3"
	gogithub "github.com/google/go-github/v84/github"

	"github.com/centroid-is/centroidx-manager/internal/github"
	"github.com/centroid-is/centroidx-manager/internal/platform"
)

// ReleaseInfo holds metadata about a GitHub release, returned by FetchReleaseInfo.
type ReleaseInfo struct {
	Version     string
	Notes       string
	Assets      []*gogithub.ReleaseAsset
	PublishedAt time.Time
}

// UpdateOptions controls the behaviour of Engine.Update.
type UpdateOptions struct {
	// Version to install. Empty means latest.
	Version string

	// WaitPID, if > 0, is the process ID to wait for before installing.
	WaitPID int

	// OnProgress is called with (downloaded, total) bytes during the download.
	// May be nil.
	OnProgress func(downloaded, total int64)

	// FirstTime, if true, attempts to install the certificate before the app.
	FirstTime bool

	// DestDir is the directory where downloaded assets are stored.
	// If empty, os.TempDir() is used.
	DestDir string
}

// Engine orchestrates the update lifecycle: check, download, verify, install, relaunch.
// All external dependencies are injected via interfaces for testability.
type Engine struct {
	client    github.ReleasesClient
	installer platform.Installer
}

// NewEngine creates an Engine with the given GitHub client and platform installer.
// Both dependencies are injected so tests can provide mock implementations.
func NewEngine(client github.ReleasesClient, installer platform.Installer) *Engine {
	return &Engine{
		client:    client,
		installer: installer,
	}
}

// FetchReleaseInfo returns metadata for the requested release.
// If version is empty the latest release is returned.
// If version is specified, ListReleases is called and the matching tag is found.
func (e *Engine) FetchReleaseInfo(ctx context.Context, version string) (*ReleaseInfo, error) {
	if version == "" {
		release, err := e.client.GetLatestRelease(ctx)
		if err != nil {
			return nil, fmt.Errorf("fetch release: network error: %w", err)
		}
		return releaseToInfo(release), nil
	}

	releases, err := e.client.ListReleases(ctx)
	if err != nil {
		return nil, fmt.Errorf("fetch release: network error: %w", err)
	}

	// Normalise requested version (strip leading "v").
	want := strings.TrimPrefix(version, "v")

	for _, r := range releases {
		tag := strings.TrimPrefix(r.GetTagName(), "v")
		if tag == want {
			return releaseToInfo(r), nil
		}
	}

	return nil, fmt.Errorf("fetch release: version %q not found in GitHub Releases", version)
}

// ListAllReleases returns all releases from GitHub sorted newest-first using
// CalVer semver comparison. Releases with unparseable version tags are silently
// skipped. Returns an empty (non-nil) slice when there are no parseable releases.
// Returns a wrapped error if the GitHub client call fails.
func (e *Engine) ListAllReleases(ctx context.Context) ([]ReleaseInfo, error) {
	releases, err := e.client.ListReleases(ctx)
	if err != nil {
		return nil, fmt.Errorf("list releases: %w", err)
	}

	// tagged pairs a parsed semver version with its ReleaseInfo for sorting.
	type tagged struct {
		version *semver.Version
		info    ReleaseInfo
	}

	targetAsset := selectPlatformAssetName()
	result := make([]tagged, 0, len(releases))
	for _, r := range releases {
		info := releaseToInfo(r)
		v, err := ParseVersion(info.Version)
		if err != nil {
			// Silently skip releases with unparseable tags (drafts, bad tags, etc.)
			continue
		}
		// Only include releases that have a downloadable asset for this platform.
		if !releaseHasAsset(info.Assets, targetAsset) {
			continue
		}
		result = append(result, tagged{version: v, info: *info})
	}

	// Sort descending: newest version first.
	sort.Slice(result, func(i, j int) bool {
		return result[i].version.GreaterThan(result[j].version)
	})

	out := make([]ReleaseInfo, len(result))
	for i, t := range result {
		out[i] = t.info
	}
	return out, nil
}

// releaseHasAsset checks if a release contains an asset with the given name.
func releaseHasAsset(assets []*gogithub.ReleaseAsset, name string) bool {
	for _, a := range assets {
		if a.GetName() == name {
			return true
		}
	}
	return false
}

// releaseToInfo converts a GitHub API release to a ReleaseInfo.
func releaseToInfo(r *gogithub.RepositoryRelease) *ReleaseInfo {
	var publishedAt time.Time
	if r.PublishedAt != nil {
		publishedAt = r.PublishedAt.Time
	}
	return &ReleaseInfo{
		Version:     strings.TrimPrefix(r.GetTagName(), "v"),
		Notes:       r.GetBody(),
		Assets:      r.Assets,
		PublishedAt: publishedAt,
	}
}

// SelectAsset selects the platform-appropriate asset and the SHA256SUMS.txt
// from a release's asset list.
// Returns (platformAsset, checksumAsset, error).
func (e *Engine) SelectAsset(release *gogithub.RepositoryRelease) (*gogithub.ReleaseAsset, *gogithub.ReleaseAsset, error) {
	targetName := selectPlatformAssetName()

	var platformAsset, checksumAsset *gogithub.ReleaseAsset
	for _, a := range release.Assets {
		name := a.GetName()
		if name == targetName {
			platformAsset = a
		}
		if name == "SHA256SUMS.txt" {
			checksumAsset = a
		}
	}

	if platformAsset == nil {
		return nil, nil, fmt.Errorf(
			"select asset: no asset found for platform %s/%s (expected %q)",
			runtime.GOOS, runtime.GOARCH, targetName,
		)
	}
	if checksumAsset == nil {
		return nil, nil, fmt.Errorf("select asset: SHA256SUMS.txt not found in release assets")
	}

	return platformAsset, checksumAsset, nil
}

// selectPlatformAssetName returns the expected asset filename for the current
// platform using the naming convention: centroidx_{os}_{arch}.{ext}
//
// Extension mapping:
//
//	windows -> .msix
//	linux   -> .deb
//	darwin  -> .dmg
func selectPlatformAssetName() string {
	ext := platformExt()
	return fmt.Sprintf("centroidx_%s_%s%s", runtime.GOOS, runtime.GOARCH, ext)
}

// platformExt returns the installer file extension for the current OS.
func platformExt() string {
	switch runtime.GOOS {
	case "windows":
		return ".msix"
	case "linux":
		return ".deb"
	case "darwin":
		return ".dmg"
	default:
		return ".bin"
	}
}

// Update runs the full update flow: fetch → select asset → (wait PID) →
// download → verify → (trust cert) → install → launch.
// All errors are returned with context wrapping for clear user messages.
func (e *Engine) Update(ctx context.Context, opts UpdateOptions) error {
	destDir := opts.DestDir
	if destDir == "" {
		destDir = os.TempDir()
	}

	// Step 1: Fetch release info.
	info, err := e.FetchReleaseInfo(ctx, opts.Version)
	if err != nil {
		// FetchReleaseInfo already wraps with "network error" context.
		return err
	}

	// Step 2: Select platform asset.
	platformAsset, checksumAsset, err := e.SelectAsset(&gogithub.RepositoryRelease{
		TagName: gogithub.Ptr(info.Version),
		Body:    gogithub.Ptr(info.Notes),
		Assets:  info.Assets,
	})
	if err != nil {
		return fmt.Errorf("select platform asset: %w", err)
	}

	// Step 3: Optionally wait for PID exit.
	if opts.WaitPID > 0 {
		if err := WaitForPIDExit(opts.WaitPID, 60*time.Second); err != nil {
			return fmt.Errorf("wait for process exit: %w", err)
		}
	}

	// Step 4: Download and verify asset.
	assetFilename := platformAsset.GetName()
	assetURL := platformAsset.GetBrowserDownloadURL()
	checksumURL := checksumAsset.GetBrowserDownloadURL()

	downloadedPath, err := DownloadAndVerify(ctx, assetURL, checksumURL, assetFilename, destDir, opts.OnProgress)
	if err != nil {
		return err // DownloadAndVerify uses "checksum mismatch" / "download asset" phrasing
	}

	// Step 5: First-time install — trust certificate if cert asset is present.
	if opts.FirstTime {
		if certPath, cerr := downloadCertAsset(ctx, info.Assets, destDir); cerr == nil && certPath != "" {
			if trustErr := e.installer.TrustCertificate(certPath); trustErr != nil {
				return fmt.Errorf("trust certificate: %w", trustErr)
			}
			// Best-effort cleanup of the cert file.
			_ = os.Remove(certPath)
		}
	}

	// Step 6: Install the downloaded asset.
	if err := e.installer.Install(downloadedPath); err != nil {
		return fmt.Errorf("install: %w", err)
	}

	// Step 7: Launch the application.
	if err := e.installer.LaunchApp(); err != nil {
		return fmt.Errorf("launch app: %w", err)
	}

	return nil
}

// Install is a shortcut for a first-time install of the latest release.
// It calls Update with FirstTime=true and Version="" (latest).
func (e *Engine) Install(ctx context.Context, destDir string, onProgress func(downloaded, total int64)) error {
	return e.Update(ctx, UpdateOptions{
		FirstTime:  true,
		DestDir:    destDir,
		OnProgress: onProgress,
	})
}

// downloadCertAsset looks for a .cer asset in the release asset list and
// downloads it to destDir. Returns the local path on success, ("", nil) if no
// cert asset is present, or ("", err) on download failure.
func downloadCertAsset(ctx context.Context, assets []*gogithub.ReleaseAsset, destDir string) (string, error) {
	for _, a := range assets {
		name := a.GetName()
		if strings.HasSuffix(name, ".cer") || strings.HasSuffix(name, ".crt") {
			// Minimal HTTP download — no checksum required for certs.
			certLocalPath := fmt.Sprintf("%s/%s", destDir, name)
			data, err := fetchBytes(ctx, a.GetBrowserDownloadURL())
			if err != nil {
				return "", fmt.Errorf("download cert asset %q: %w", name, err)
			}
			if err := os.WriteFile(certLocalPath, data, 0o600); err != nil {
				return "", fmt.Errorf("write cert asset %q: %w", name, err)
			}
			return certLocalPath, nil
		}
	}
	return "", nil // no cert asset found — not an error
}

// fetchBytes fetches the content of url and returns the body as bytes.
func fetchBytes(ctx context.Context, url string) ([]byte, error) {
	if url == "" {
		return nil, fmt.Errorf("fetchBytes: empty URL")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, fmt.Errorf("fetchBytes create request: %w", err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("GET %s: %w", url, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GET %s: HTTP %d", url, resp.StatusCode)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response body from %s: %w", url, err)
	}
	return data, nil
}
