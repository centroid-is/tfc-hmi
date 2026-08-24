package update

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"

	"github.com/Masterminds/semver/v3"
	gogithub "github.com/google/go-github/v84/github"

	"github.com/centroid-is/centroidx-manager/internal/github"
	"github.com/centroid-is/centroidx-manager/internal/platform"
)

// Release channels. Stable follows tagged releases ("latest" in GitHub
// Releases terms); Latest additionally follows prereleases such as the
// rolling `main-latest` build published on every merge to main.
const (
	ChannelStable = "stable"
	ChannelLatest = "latest"
)

// ValidChannel reports whether s names a known release channel.
// The empty string is valid and means ChannelStable.
func ValidChannel(s string) bool {
	return s == "" || s == ChannelStable || s == ChannelLatest
}

// ReleaseInfo holds metadata about a GitHub release, returned by FetchReleaseInfo.
type ReleaseInfo struct {
	Version     string
	Notes       string
	Assets      []*gogithub.ReleaseAsset
	PublishedAt time.Time

	// Prerelease is GitHub's own flag. The Latest channel lists these and
	// nothing else: a tagged release belongs on Stable, and listing it in
	// both tabs made "Latest" read as "everything", which is not what an
	// operator picking a development build is looking for.
	Prerelease bool
}

// UpdateOptions controls the behaviour of Engine.Update.
type UpdateOptions struct {
	// Version to install. Empty means the newest on Channel.
	Version string

	// Channel selects which releases are considered when Version is empty:
	// ChannelStable (default) or ChannelLatest.
	Channel string

	// WaitPID, if > 0, is the process ID to wait for before installing.
	WaitPID int

	// OnProgress is called with (downloaded, total) bytes during the download.
	// May be nil.
	OnProgress func(downloaded, total int64)

	// DestDir is the directory where downloaded assets are stored.
	// If empty, os.TempDir() is used.
	DestDir string
}

// Engine orchestrates the update lifecycle: check, download, verify, install, relaunch.
// All external dependencies are injected via interfaces for testability.
type Engine struct {
	client    github.ReleasesClient
	installer platform.Installer

	// logf reports non-fatal progress and problems. Defaults to log.Printf;
	// tests replace it to assert on what the operator would have been told.
	logf func(format string, args ...any)
}

// NewEngine creates an Engine with the given GitHub client and platform installer.
// Both dependencies are injected so tests can provide mock implementations.
func NewEngine(client github.ReleasesClient, installer platform.Installer) *Engine {
	return &Engine{
		client:    client,
		installer: installer,
		logf:      log.Printf,
	}
}

// FetchReleaseInfo returns metadata for the requested release.
//
// If version is non-empty, ListReleases is called and the matching tag is
// found regardless of channel. With an empty version the channel decides:
// ChannelStable (or "") returns the latest tagged release, ChannelLatest
// returns the most recently published release — prereleases included — that
// carries an installable asset for this platform. Prerelease tags like
// `main-latest` do not parse as versions, so the latest channel orders by
// publish date instead of semver.
func (e *Engine) FetchReleaseInfo(ctx context.Context, version, channel string) (*ReleaseInfo, error) {
	if !ValidChannel(channel) {
		return nil, fmt.Errorf("fetch release: unknown channel %q (expected %q or %q)", channel, ChannelStable, ChannelLatest)
	}

	if version == "" {
		if channel == ChannelLatest {
			return e.fetchLatestChannelRelease(ctx)
		}
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

// fetchLatestChannelRelease picks the newest-published non-draft release that
// has an installable asset for this platform, prereleases included.
func (e *Engine) fetchLatestChannelRelease(ctx context.Context) (*ReleaseInfo, error) {
	releases, err := e.client.ListReleases(ctx)
	if err != nil {
		return nil, fmt.Errorf("fetch release: network error: %w", err)
	}

	var best *gogithub.RepositoryRelease
	for _, r := range releases {
		if r.GetDraft() {
			continue
		}
		if selectAssetByNames(r.Assets, platformAssetCandidates()) == nil {
			continue
		}
		if best == nil || r.GetPublishedAt().After(best.GetPublishedAt().Time) {
			best = r
		}
	}
	if best == nil {
		return nil, fmt.Errorf(
			"fetch release: no release on the latest channel has an asset for platform %s/%s",
			runtime.GOOS, runtime.GOARCH,
		)
	}
	return releaseToInfo(best), nil
}

// ListAllReleases returns the installable releases on the given channel,
// newest-first, for the version picker.
//
// On ChannelStable (or "") only releases with a parseable CalVer tag are
// listed, ordered by version — drafts, prereleases and bad tags are skipped.
// On ChannelLatest the rolling prerelease is listed too; its tag
// (`main-latest`) never parses as a version, so the whole channel is ordered
// by publish date instead, which keeps the rolling build in its true position
// relative to the tagged releases.
//
// Releases without a downloadable asset for this platform are skipped on both
// channels — the picker must not offer something it cannot install. Returns an
// empty (non-nil) slice when nothing qualifies, or a wrapped error if the
// GitHub client call fails.
func (e *Engine) ListAllReleases(ctx context.Context, channel string) ([]ReleaseInfo, error) {
	if !ValidChannel(channel) {
		return nil, fmt.Errorf("list releases: unknown channel %q (expected %q or %q)", channel, ChannelStable, ChannelLatest)
	}

	releases, err := e.client.ListReleases(ctx)
	if err != nil {
		return nil, fmt.Errorf("list releases: %w", err)
	}

	// tagged pairs a parsed semver version with its ReleaseInfo for sorting.
	// version is nil for releases whose tag is not a version (latest channel).
	type tagged struct {
		version *semver.Version
		info    ReleaseInfo
	}

	latest := channel == ChannelLatest
	targetAssets := platformAssetCandidates()
	result := make([]tagged, 0, len(releases))
	for _, r := range releases {
		if r.GetDraft() {
			continue
		}
		info := releaseToInfo(r)
		// Latest is the development channel: prereleases only. Tagged
		// releases are what Stable lists, and showing them in both made the
		// two tabs look like "some" and "all" rather than two channels.
		if latest && !info.Prerelease {
			continue
		}
		if !latest && info.Prerelease {
			continue
		}
		v, err := ParseVersion(info.Version)
		if err != nil {
			// Unparseable tags are the rolling prerelease's own shape, so they
			// belong on the latest channel and nowhere else.
			if !latest {
				continue
			}
			v = nil
		}
		// Only include releases that have a downloadable asset for this platform.
		if selectAssetByNames(info.Assets, targetAssets) == nil {
			continue
		}
		result = append(result, tagged{version: v, info: *info})
	}

	sort.Slice(result, func(i, j int) bool {
		if latest {
			// Publish date: the only ordering that can place an unversioned
			// rolling tag among versioned releases.
			return result[i].info.PublishedAt.After(result[j].info.PublishedAt)
		}
		return result[i].version.GreaterThan(result[j].version)
	})

	out := make([]ReleaseInfo, len(result))
	for i, t := range result {
		out[i] = t.info
	}
	return out, nil
}

// selectAssetByNames returns the first asset whose name matches any of the
// candidate names, in candidate priority order. Returns nil when none match.
func selectAssetByNames(assets []*gogithub.ReleaseAsset, candidates []string) *gogithub.ReleaseAsset {
	for _, name := range candidates {
		for _, a := range assets {
			if a.GetName() == name {
				return a
			}
		}
	}
	return nil
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
		Prerelease:  r.GetPrerelease(),
	}
}

// SelectAsset selects the platform-appropriate asset and the SHA256SUMS.txt
// from a release's asset list.
// Returns (platformAsset, checksumAsset, error).
func (e *Engine) SelectAsset(release *gogithub.RepositoryRelease) (*gogithub.ReleaseAsset, *gogithub.ReleaseAsset, error) {
	candidates := platformAssetCandidates()

	platformAsset := selectAssetByNames(release.Assets, candidates)
	var checksumAsset *gogithub.ReleaseAsset
	for _, a := range release.Assets {
		if a.GetName() == "SHA256SUMS.txt" {
			checksumAsset = a
		}
	}

	if platformAsset == nil {
		return nil, nil, fmt.Errorf(
			"select asset: no asset found for platform %s/%s (expected one of %q)",
			runtime.GOOS, runtime.GOARCH, candidates,
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
// SelectPlatformAssetName returns the expected Flutter app asset filename for the current platform.
func SelectPlatformAssetName() string { return selectPlatformAssetName() }

// SelectManagerAssetName returns the expected manager binary artifact name
// for the current platform, matching CI artifact naming.
func SelectManagerAssetName() string {
	ext := ""
	if runtime.GOOS == "windows" {
		ext = ".exe"
	}
	return fmt.Sprintf("centroidx-manager_%s_%s%s", runtime.GOOS, runtime.GOARCH, ext)
}

func selectPlatformAssetName() string {
	ext := platformExt()
	return fmt.Sprintf("centroidx_%s_%s%s", runtime.GOOS, runtime.GOARCH, ext)
}

// platformAssetCandidates returns asset filenames accepted for this platform,
// in priority order. The canonical centroidx_{os}_{arch}.{ext} name comes
// first; legacy names shipped by earlier CI (the msix was published as plain
// "centroidx.msix" up to v2026.3.26) stay accepted so rollbacks to those
// releases keep working.
func platformAssetCandidates() []string {
	candidates := []string{selectPlatformAssetName()}
	if runtime.GOOS == "windows" {
		candidates = append(candidates, "centroidx.msix")
	}
	return candidates
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
	info, err := e.FetchReleaseInfo(ctx, opts.Version, opts.Channel)
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

	// Step 5: trust the release signing certificate.
	e.trustReleaseCertificate(ctx, info.Assets, destDir)

	// Step 6: Install the downloaded asset.
	if err := e.installer.Install(downloadedPath); err != nil {
		// The payload is deliberately kept when the install fails: it is what
		// someone will want to inspect, and replaceFile clears a stale
		// destination anyway, so it cannot wedge the next update.
		return fmt.Errorf("install: %w", err)
	}
	// Installed successfully — the downloaded package has served its purpose.
	// Leaving it in the temp directory under a fixed name is what turns a
	// locked destination into a permanent failure on Windows.
	if err := os.Remove(downloadedPath); err != nil {
		e.log("warn: could not remove the downloaded package %s: %v", downloadedPath, err)
	}

	// Step 7: Launch the application.
	if err := e.installer.LaunchApp(); err != nil {
		return fmt.Errorf("launch app: %w", err)
	}

	return nil
}

// trustReleaseCertificate imports the release's signing certificate into the
// OS trust store. It is attempted on every install and update, and no outcome
// is fatal.
//
// Unconditional, because a certificate is not a first-install concern: when the
// signing certificate is rotated, the machines that need the new one are
// precisely the ones that already have the app. Gating this on a first install
// meant a rotation could only ever be delivered to stations that did not need
// it yet.
//
// Non-fatal, because trusting a certificate needs administrator rights the
// manager does not have (see trustCertificateWindows). Without the certificate
// the install fails on its own with a signature error, so attempting it anyway
// costs nothing; refusing to install because trust failed would take a station
// that merely lacks trust and stop it from even trying — a worse outcome than
// today's, and the one shipping the certificate asset would otherwise create.
//
// Every path logs. The silent version of this function hid an unreachable
// trust step for months.
// log reports a non-fatal condition. It tolerates an Engine built as a struct
// literal rather than through NewEngine, so a logging call can never be the
// thing that takes down an update.
func (e *Engine) log(format string, args ...any) {
	if e.logf == nil {
		log.Printf(format, args...)
		return
	}
	e.logf(format, args...)
}

func (e *Engine) trustReleaseCertificate(ctx context.Context, assets []*gogithub.ReleaseAsset, destDir string) {
	certPath, err := downloadCertAsset(ctx, assets, destDir)
	if err != nil {
		e.log("warn: could not download the release signing certificate, installing without it: %v", err)
		return
	}
	if certPath == "" {
		e.log("warn: this release publishes no signing certificate; a station that does not already trust the publisher will reject the package")
		return
	}
	// Remove the certificate whether or not the import worked — it is a
	// temporary download, and the old code left it behind on every failure.
	defer func() { _ = os.Remove(certPath) }()

	if err := e.installer.TrustCertificate(certPath); err != nil {
		e.log("warn: could not trust the release signing certificate, installing anyway: %v", err)
		return
	}
	e.log("trusted the release signing certificate %s", filepath.Base(certPath))

	e.trustCodesignCertificate(ctx, assets, destDir)
}

// trustCodesignCertificate trusts the certificate our own executables are
// signed with, when a release publishes one. Best effort and silent when the
// release has no such asset: it changes nothing about whether an install
// works, only whether the approval prompts an update raises say "Centroid" or
// "Unknown". It runs right after the package certificate so a station is asked
// for approval once, not twice.
func (e *Engine) trustCodesignCertificate(ctx context.Context, assets []*gogithub.ReleaseAsset, destDir string) {
	certPath, err := downloadCodesignAsset(ctx, assets, destDir)
	if err != nil {
		e.log("warn: could not download the code-signing certificate: %v", err)
		return
	}
	if certPath == "" {
		return
	}
	defer func() { _ = os.Remove(certPath) }()

	if err := e.installer.TrustCodesignCertificate(certPath); err != nil {
		e.log("warn: could not trust the code-signing certificate, so approval prompts will not name the publisher: %v", err)
		return
	}
	e.log("trusted the code-signing certificate %s", filepath.Base(certPath))
}

// TrustCertificateFor downloads the signing certificate published with the
// given release (empty version: the newest on the channel) and imports it
// into the machine trust store. On Windows that asks for one UAC approval
// when the manager is not elevated. Behind the picker's "Trust certificate"
// button, so a station can be set up deliberately instead of the trust step
// only ever running as a side effect of an install.
func (e *Engine) TrustCertificateFor(ctx context.Context, version, channel string) error {
	info, err := e.FetchReleaseInfo(ctx, version, channel)
	if err != nil {
		return err
	}
	certPath, err := downloadCertAsset(ctx, info.Assets, os.TempDir())
	if err != nil {
		return fmt.Errorf("download the release signing certificate: %w", err)
	}
	if certPath == "" {
		return fmt.Errorf("release %s publishes no signing certificate", info.Version)
	}
	defer func() { _ = os.Remove(certPath) }()
	return e.installer.TrustCertificate(certPath)
}

// Install is a shortcut for a first-time install of the latest release.
// It calls Update with Version="" (latest).
func (e *Engine) Install(ctx context.Context, destDir string, onProgress func(downloaded, total int64)) error {
	return e.Update(ctx, UpdateOptions{
		DestDir:    destDir,
		OnProgress: onProgress,
	})
}

// InstallLocal installs from a local package file path (dev/testing mode).
// Skips GitHub Releases — directly calls the platform installer.
func (e *Engine) InstallLocal(pkgPath string) error {
	if err := e.installer.Install(pkgPath); err != nil {
		return fmt.Errorf("install local package: %w", err)
	}
	return e.installer.LaunchApp()
}

// InstallFromURL downloads a package from a direct URL and installs it.
// Used for dev/testing with CI artifact URLs.
func (e *Engine) InstallFromURL(ctx context.Context, url string, onProgress func(downloaded, total int64)) error {
	destDir := os.TempDir()
	// Extract filename from URL
	parts := strings.Split(url, "/")
	filename := parts[len(parts)-1]
	if filename == "" {
		filename = "centroidx-package" + platformExt()
	}

	destPath := fmt.Sprintf("%s/%s", destDir, filename)

	// Download with progress
	data, err := fetchBytes(ctx, url)
	if err != nil {
		return fmt.Errorf("download artifact: %w", err)
	}

	if onProgress != nil {
		onProgress(int64(len(data)), int64(len(data)))
	}

	if err := os.WriteFile(destPath, data, 0o644); err != nil {
		return fmt.Errorf("write artifact: %w", err)
	}

	if err := e.installer.Install(destPath); err != nil {
		return fmt.Errorf("install artifact: %w", err)
	}
	return e.installer.LaunchApp()
}

// downloadCertAsset looks for a .cer asset in the release asset list and
// downloads it to destDir. Returns the local path on success, ("", nil) if no
// cert asset is present, or ("", err) on download failure.
// pickCertAsset chooses between the two certificates a release can publish.
// They are told apart by name: anything with "codesign" in it is what our own
// executables are signed with, everything else ending .cer/.crt is what the
// package is signed with. Mixing them up fails in a way nothing reports --
// the wrong certificate lands in the wrong store and the package is rejected
// for an untrusted publisher -- so the rule lives in one place.
func pickCertAsset(assets []*gogithub.ReleaseAsset, codesign bool) *gogithub.ReleaseAsset {
	for _, a := range assets {
		name := a.GetName()
		if !strings.HasSuffix(name, ".cer") && !strings.HasSuffix(name, ".crt") {
			continue
		}
		if strings.Contains(strings.ToLower(name), "codesign") != codesign {
			continue
		}
		return a
	}
	return nil
}

// downloadCertAsset fetches the certificate the package is signed with, or
// returns "" when the release publishes none (not an error: the caller treats
// trust as best effort).
func downloadCertAsset(ctx context.Context, assets []*gogithub.ReleaseAsset, destDir string) (string, error) {
	return downloadAssetTo(ctx, pickCertAsset(assets, false), destDir)
}

// downloadCodesignAsset fetches the certificate our executables are signed
// with. Trusting it as a root is what makes Windows name the publisher on an
// elevation prompt instead of saying "Unknown"; without it every prompt looks
// like something unasked-for.
func downloadCodesignAsset(ctx context.Context, assets []*gogithub.ReleaseAsset, destDir string) (string, error) {
	return downloadAssetTo(ctx, pickCertAsset(assets, true), destDir)
}

// downloadAssetTo writes one asset into destDir. Certificates are public by
// definition, so no checksum is required here; what protects the station is
// that a wrong certificate cannot make a wrong package install -- Windows
// still checks the package signature against what was actually trusted.
func downloadAssetTo(ctx context.Context, a *gogithub.ReleaseAsset, destDir string) (string, error) {
	if a == nil {
		return "", nil
	}
	name := a.GetName()
	path := fmt.Sprintf("%s/%s", destDir, name)
	data, err := fetchBytes(ctx, a.GetBrowserDownloadURL())
	if err != nil {
		return "", fmt.Errorf("download cert asset %q: %w", name, err)
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return "", fmt.Errorf("write cert asset %q: %w", name, err)
	}
	return path, nil
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
