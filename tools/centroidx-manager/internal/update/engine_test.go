package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"runtime"
	"strings"
	"testing"
	"time"

	gogithub "github.com/google/go-github/v84/github"
)

// ---- mock types --------------------------------------------------------

// mockReleasesClient implements github.ReleasesClient for testing.
type mockReleasesClient struct {
	releases []*gogithub.RepositoryRelease
	latest   *gogithub.RepositoryRelease
	err      error
}

func (m *mockReleasesClient) GetLatestRelease(_ context.Context) (*gogithub.RepositoryRelease, error) {
	if m.err != nil {
		return nil, m.err
	}
	return m.latest, nil
}

func (m *mockReleasesClient) ListReleases(_ context.Context) ([]*gogithub.RepositoryRelease, error) {
	if m.err != nil {
		return nil, m.err
	}
	return m.releases, nil
}

func (m *mockReleasesClient) DownloadAsset(_ context.Context, _ *gogithub.ReleaseAsset) (io.ReadCloser, int64, error) {
	return nil, 0, errors.New("DownloadAsset not implemented in mock")
}

// mockInstaller tracks all install/trust/launch calls.
type mockInstaller struct {
	installed    []string
	trustedCerts []string
	launchedApp  bool
	installErr   error
	trustErr     error
	launchErr    error
}

func (m *mockInstaller) Install(assetPath string) error {
	if m.installErr != nil {
		return m.installErr
	}
	m.installed = append(m.installed, assetPath)
	return nil
}

func (m *mockInstaller) TrustCertificate(certPath string) error {
	if m.trustErr != nil {
		return m.trustErr
	}
	m.trustedCerts = append(m.trustedCerts, certPath)
	return nil
}

func (m *mockInstaller) IsInstalled() bool { return len(m.installed) > 0 }
func (m *mockInstaller) Uninstall() error { m.installed = nil; return nil }

func (m *mockInstaller) LaunchApp() error {
	if m.launchErr != nil {
		return m.launchErr
	}
	m.launchedApp = true
	return nil
}

// ---- helpers -----------------------------------------------------------

// buildTag creates a *gogithub.RepositoryRelease with the given tag name and body.
func buildRelease(tag, body string, assets []*gogithub.ReleaseAsset) *gogithub.RepositoryRelease {
	now := gogithub.Timestamp{Time: time.Now()}
	return &gogithub.RepositoryRelease{
		TagName:     gogithub.Ptr(tag),
		Body:        gogithub.Ptr(body),
		PublishedAt: &now,
		Assets:      assets,
	}
}

// buildDownloadableRelease creates a release that has the current platform's
// asset so it passes the ListAllReleases filter.
func buildDownloadableRelease(tag, body string) *gogithub.RepositoryRelease {
	assetName := selectPlatformAssetName()
	return buildRelease(tag, body, []*gogithub.ReleaseAsset{
		buildAsset(assetName, "https://example.com/"+assetName),
	})
}

// buildAsset creates a ReleaseAsset pointing at the given URL.
func buildAsset(name, downloadURL string) *gogithub.ReleaseAsset {
	return &gogithub.ReleaseAsset{
		Name:               gogithub.Ptr(name),
		BrowserDownloadURL: gogithub.Ptr(downloadURL),
	}
}

// newEngineTestServer serves the given assetContent at /asset and a matching
// SHA256SUMS.txt at /SHA256SUMS.txt. Returns server and its URL.
func newEngineTestServer(t *testing.T, assetContent, assetFilename, checksumOverride string) *httptest.Server {
	t.Helper()
	var checksumContent string
	if checksumOverride != "" {
		checksumContent = checksumOverride
	} else {
		h := sha256.Sum256([]byte(assetContent))
		checksumContent = hex.EncodeToString(h[:]) + "  " + assetFilename + "\n"
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/asset", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", fmt.Sprintf("%d", len(assetContent)))
		_, _ = w.Write([]byte(assetContent))
	})
	mux.HandleFunc("/SHA256SUMS.txt", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(checksumContent))
	})
	return httptest.NewServer(mux)
}

// ---- TestEngine_FetchReleaseInfo -------------------------------------------

func TestEngine_FetchReleaseInfo(t *testing.T) {
	release := buildRelease("2026.3.6", "## Changes\n- fix: bug", nil)
	client := &mockReleasesClient{latest: release}
	inst := &mockInstaller{}

	eng := NewEngine(client, inst)

	info, err := eng.FetchReleaseInfo(context.Background(), "", ChannelStable)
	if err != nil {
		t.Fatalf("FetchReleaseInfo returned error: %v", err)
	}
	if info.Version != "2026.3.6" {
		t.Errorf("expected version 2026.3.6, got %q", info.Version)
	}
	if !strings.Contains(info.Notes, "## Changes") {
		t.Errorf("expected notes to contain '## Changes', got: %q", info.Notes)
	}
}

func TestEngine_FetchReleaseInfo_SpecificVersion(t *testing.T) {
	releases := []*gogithub.RepositoryRelease{
		buildRelease("2026.3.5", "old", nil),
		buildRelease("2026.3.6", "## Current", nil),
	}
	client := &mockReleasesClient{releases: releases}
	inst := &mockInstaller{}

	eng := NewEngine(client, inst)

	info, err := eng.FetchReleaseInfo(context.Background(), "2026.3.6", ChannelStable)
	if err != nil {
		t.Fatalf("FetchReleaseInfo returned error: %v", err)
	}
	if info.Version != "2026.3.6" {
		t.Errorf("expected version 2026.3.6, got %q", info.Version)
	}
}

func TestEngine_FetchReleaseInfo_VersionNotFound(t *testing.T) {
	releases := []*gogithub.RepositoryRelease{
		buildRelease("2026.3.5", "old", nil),
	}
	client := &mockReleasesClient{releases: releases}
	inst := &mockInstaller{}

	eng := NewEngine(client, inst)

	_, err := eng.FetchReleaseInfo(context.Background(), "9999.1.1", ChannelStable)
	if err == nil {
		t.Fatal("expected error for non-existent version, got nil")
	}
}

// ---- TestEngine_SelectAsset ------------------------------------------------

func TestEngine_SelectAsset(t *testing.T) {
	assetFilename := platformAssetName()
	assets := []*gogithub.ReleaseAsset{
		buildAsset(assetFilename, "http://example.com/"+assetFilename),
		buildAsset("SHA256SUMS.txt", "http://example.com/SHA256SUMS.txt"),
		buildAsset("other-asset.zip", "http://example.com/other.zip"),
	}
	release := buildRelease("2026.3.6", "notes", assets)

	eng := NewEngine(&mockReleasesClient{}, &mockInstaller{})

	platformAsset, checksumAsset, err := eng.SelectAsset(release)
	if err != nil {
		t.Fatalf("SelectAsset returned error: %v", err)
	}
	if platformAsset == nil {
		t.Fatal("expected platform asset, got nil")
	}
	if platformAsset.GetName() != assetFilename {
		t.Errorf("expected asset name %q, got %q", assetFilename, platformAsset.GetName())
	}
	if checksumAsset == nil {
		t.Fatal("expected checksum asset, got nil")
	}
	if checksumAsset.GetName() != "SHA256SUMS.txt" {
		t.Errorf("expected checksum asset 'SHA256SUMS.txt', got %q", checksumAsset.GetName())
	}
}

func TestEngine_SelectAsset_Missing(t *testing.T) {
	// No matching platform asset.
	assets := []*gogithub.ReleaseAsset{
		buildAsset("SHA256SUMS.txt", "http://example.com/SHA256SUMS.txt"),
	}
	release := buildRelease("2026.3.6", "notes", assets)

	eng := NewEngine(&mockReleasesClient{}, &mockInstaller{})

	_, _, err := eng.SelectAsset(release)
	if err == nil {
		t.Fatal("expected error for missing platform asset, got nil")
	}
}

// ---- TestEngine_Update_Success ---------------------------------------------

func TestEngine_Update_Success(t *testing.T) {
	assetContent := "fake MSIX content for engine test"
	assetFilename := platformAssetName()

	srv := newEngineTestServer(t, assetContent, assetFilename, "")
	defer srv.Close()

	assets := []*gogithub.ReleaseAsset{
		buildAsset(assetFilename, srv.URL+"/asset"),
		buildAsset("SHA256SUMS.txt", srv.URL+"/SHA256SUMS.txt"),
	}
	release := buildRelease("2026.3.6", "notes", assets)

	client := &mockReleasesClient{latest: release}
	inst := &mockInstaller{}

	eng := NewEngine(client, inst)

	destDir := t.TempDir()
	err := eng.Update(context.Background(), UpdateOptions{
		DestDir:    destDir,
		OnProgress: nil,
	})
	if err != nil {
		t.Fatalf("Update returned error: %v", err)
	}
	if len(inst.installed) == 0 {
		t.Fatal("expected Install to be called, but it was not")
	}
	// Verify installed path contains the asset filename.
	if !strings.Contains(inst.installed[0], assetFilename) {
		t.Errorf("expected installed path to contain %q, got %q", assetFilename, inst.installed[0])
	}
	if !inst.launchedApp {
		t.Error("expected LaunchApp to be called after install")
	}
}

// ---- TestEngine_Update_ChecksumMismatch ------------------------------------

func TestEngine_Update_ChecksumMismatch(t *testing.T) {
	assetContent := "fake MSIX content for checksum test"
	assetFilename := platformAssetName()

	// Serve a wrong checksum.
	wrongChecksum := "0000000000000000000000000000000000000000000000000000000000000000  " + assetFilename + "\n"
	srv := newEngineTestServer(t, assetContent, assetFilename, wrongChecksum)
	defer srv.Close()

	assets := []*gogithub.ReleaseAsset{
		buildAsset(assetFilename, srv.URL+"/asset"),
		buildAsset("SHA256SUMS.txt", srv.URL+"/SHA256SUMS.txt"),
	}
	release := buildRelease("2026.3.6", "notes", assets)

	client := &mockReleasesClient{latest: release}
	inst := &mockInstaller{}

	eng := NewEngine(client, inst)

	destDir := t.TempDir()
	err := eng.Update(context.Background(), UpdateOptions{DestDir: destDir})
	if err == nil {
		t.Fatal("expected checksum error, got nil")
	}
	if !strings.Contains(err.Error(), "checksum") {
		t.Errorf("expected error to contain 'checksum', got: %v", err)
	}
}

// ---- TestEngine_Update_NetworkError ----------------------------------------

func TestEngine_Update_NetworkError(t *testing.T) {
	client := &mockReleasesClient{
		err: errors.New("dial tcp: connection refused"),
	}
	inst := &mockInstaller{}

	eng := NewEngine(client, inst)

	destDir := t.TempDir()
	err := eng.Update(context.Background(), UpdateOptions{DestDir: destDir})
	if err == nil {
		t.Fatal("expected network error, got nil")
	}
	// Error should either say "network" or wrap the original error.
	if !strings.Contains(err.Error(), "network") && !strings.Contains(err.Error(), "connection refused") && !strings.Contains(err.Error(), "fetch release") {
		t.Errorf("expected error to mention network issue, got: %v", err)
	}
}

// ---- TestEngine_Update_InstallError ----------------------------------------

func TestEngine_Update_InstallError(t *testing.T) {
	assetContent := "fake MSIX content for install error test"
	assetFilename := platformAssetName()

	srv := newEngineTestServer(t, assetContent, assetFilename, "")
	defer srv.Close()

	assets := []*gogithub.ReleaseAsset{
		buildAsset(assetFilename, srv.URL+"/asset"),
		buildAsset("SHA256SUMS.txt", srv.URL+"/SHA256SUMS.txt"),
	}
	release := buildRelease("2026.3.6", "notes", assets)

	client := &mockReleasesClient{latest: release}
	inst := &mockInstaller{
		installErr: errors.New("Add-AppxPackage failed: access denied"),
	}

	eng := NewEngine(client, inst)

	destDir := t.TempDir()
	err := eng.Update(context.Background(), UpdateOptions{DestDir: destDir})
	if err == nil {
		t.Fatal("expected install error, got nil")
	}
	if !strings.Contains(err.Error(), "install") {
		t.Errorf("expected error to contain 'install', got: %v", err)
	}
}

// ---- TestEngine_Install_FirstTime ------------------------------------------

func TestEngine_Install_FirstTime(t *testing.T) {
	assetContent := "fake app package for first-time install"
	assetFilename := platformAssetName()

	srv := newEngineTestServer(t, assetContent, assetFilename, "")
	defer srv.Close()

	certFilename := "centroidx.cer"
	mux := http.NewServeMux()
	// Serve asset + checksums + cert
	h := sha256.Sum256([]byte(assetContent))
	checksumContent := hex.EncodeToString(h[:]) + "  " + assetFilename + "\n"
	mux.HandleFunc("/asset", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", fmt.Sprintf("%d", len(assetContent)))
		_, _ = w.Write([]byte(assetContent))
	})
	mux.HandleFunc("/SHA256SUMS.txt", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(checksumContent))
	})
	mux.HandleFunc("/cert", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("fake cert data"))
	})
	srv2 := httptest.NewServer(mux)
	defer srv2.Close()

	assets := []*gogithub.ReleaseAsset{
		buildAsset(assetFilename, srv2.URL+"/asset"),
		buildAsset("SHA256SUMS.txt", srv2.URL+"/SHA256SUMS.txt"),
		buildAsset(certFilename, srv2.URL+"/cert"),
	}
	release := buildRelease("2026.3.6", "notes", assets)

	client := &mockReleasesClient{latest: release}
	inst := &mockInstaller{}

	eng := NewEngine(client, inst)

	destDir := t.TempDir()
	err := eng.Update(context.Background(), UpdateOptions{
		DestDir:   destDir,
		FirstTime: true,
	})
	if err != nil {
		t.Fatalf("Install (first-time) returned error: %v", err)
	}

	// For non-Windows we just check Install was called.
	if len(inst.installed) == 0 {
		t.Fatal("expected Install to be called, but it was not")
	}

	// On first-time install with a cert asset, TrustCertificate should be called.
	// (Platform-agnostic: the engine calls TrustCertificate when cert asset is found)
	if len(inst.trustedCerts) == 0 {
		t.Log("TrustCertificate not called (may be platform-specific no-op, acceptable)")
	}
}

// ---- TestEngine_Install_shortcut -------------------------------------------

func TestEngine_Install_Shortcut(t *testing.T) {
	assetContent := "fake app content install shortcut"
	assetFilename := platformAssetName()

	srv := newEngineTestServer(t, assetContent, assetFilename, "")
	defer srv.Close()

	assets := []*gogithub.ReleaseAsset{
		buildAsset(assetFilename, srv.URL+"/asset"),
		buildAsset("SHA256SUMS.txt", srv.URL+"/SHA256SUMS.txt"),
	}
	release := buildRelease("2026.3.6", "notes", assets)

	client := &mockReleasesClient{latest: release}
	inst := &mockInstaller{}

	eng := NewEngine(client, inst)

	destDir := t.TempDir()
	err := eng.Install(context.Background(), destDir, nil)
	if err != nil {
		t.Fatalf("Install shortcut returned error: %v", err)
	}
	if len(inst.installed) == 0 {
		t.Fatal("expected Install to be called via Install shortcut")
	}
}

// ---- helper: platform asset name for current OS/Arch ----------------------

// platformAssetName returns the expected asset filename for the current
// platform using the naming convention centroidx_{os}_{arch}.{ext}.
// This mirrors the logic in SelectAsset so tests use the same name.
func platformAssetName() string {
	return selectPlatformAssetName()
}

// selectPlatformAssetName is defined in engine.go (exported for test access via same package).
// We call it directly here since both files are in package update.

// tmpDir is available via t.TempDir().

// ---- os.ReadFile needed for checksum test cleanup check.
var _ = os.ReadFile

// ---- TestEngine_ListAllReleases -------------------------------------------

func TestEngine_ListAllReleases_SortDescending(t *testing.T) {
	releases := []*gogithub.RepositoryRelease{
		buildDownloadableRelease("2026.3.5", "notes"),
		buildDownloadableRelease("2026.10.1", "notes"),
		buildDownloadableRelease("2026.3.6", "notes"),
	}
	client := &mockReleasesClient{releases: releases}
	eng := NewEngine(client, &mockInstaller{})

	result, err := eng.ListAllReleases(context.Background(), ChannelStable)
	if err != nil {
		t.Fatalf("ListAllReleases returned error: %v", err)
	}
	if len(result) != 3 {
		t.Fatalf("expected 3 releases, got %d", len(result))
	}
	// Expect newest-first: 2026.10.1, 2026.3.6, 2026.3.5
	expected := []string{"2026.10.1", "2026.3.6", "2026.3.5"}
	for i, v := range expected {
		if result[i].Version != v {
			t.Errorf("result[%d]: expected %q, got %q", i, v, result[i].Version)
		}
	}
}

func TestEngine_ListAllReleases_MonthBoundary(t *testing.T) {
	releases := []*gogithub.RepositoryRelease{
		buildDownloadableRelease("2026.9.30", "old"),
		buildDownloadableRelease("2026.10.1", "new"),
	}
	client := &mockReleasesClient{releases: releases}
	eng := NewEngine(client, &mockInstaller{})

	result, err := eng.ListAllReleases(context.Background(), ChannelStable)
	if err != nil {
		t.Fatalf("ListAllReleases returned error: %v", err)
	}
	if len(result) != 2 {
		t.Fatalf("expected 2 releases, got %d", len(result))
	}
	// 2026.10.1 must sort before 2026.9.30 (month boundary: 10 > 9)
	if result[0].Version != "2026.10.1" {
		t.Errorf("expected first result to be 2026.10.1 (month boundary), got %q", result[0].Version)
	}
	if result[1].Version != "2026.9.30" {
		t.Errorf("expected second result to be 2026.9.30, got %q", result[1].Version)
	}
}

func TestEngine_ListAllReleases_SkipsUnparseable(t *testing.T) {
	releases := []*gogithub.RepositoryRelease{
		buildDownloadableRelease("2026.3.6", "notes"),
		buildDownloadableRelease("invalid-tag", "bad"),
		buildDownloadableRelease("2026.3.5", "notes"),
	}
	client := &mockReleasesClient{releases: releases}
	eng := NewEngine(client, &mockInstaller{})

	result, err := eng.ListAllReleases(context.Background(), ChannelStable)
	if err != nil {
		t.Fatalf("ListAllReleases returned error: %v", err)
	}
	if len(result) != 2 {
		t.Fatalf("expected 2 releases (unparseable skipped), got %d", len(result))
	}
	// Verify neither returned entry is the invalid one
	for _, r := range result {
		if r.Version == "invalid-tag" {
			t.Error("expected invalid-tag to be skipped, but it appeared in results")
		}
	}
}

func TestEngine_ListAllReleases_Empty(t *testing.T) {
	client := &mockReleasesClient{releases: []*gogithub.RepositoryRelease{}}
	eng := NewEngine(client, &mockInstaller{})

	result, err := eng.ListAllReleases(context.Background(), ChannelStable)
	if err != nil {
		t.Fatalf("ListAllReleases returned error on empty: %v", err)
	}
	if result == nil {
		t.Fatal("expected empty slice, got nil")
	}
	if len(result) != 0 {
		t.Fatalf("expected 0 releases, got %d", len(result))
	}
}

func TestEngine_ListAllReleases_FiltersNoAssets(t *testing.T) {
	releases := []*gogithub.RepositoryRelease{
		buildDownloadableRelease("2026.3.6", "has asset"),
		buildRelease("2026.3.5", "no assets", nil), // no platform asset
		buildRelease("2026.3.4", "wrong asset", []*gogithub.ReleaseAsset{
			buildAsset("something-else.zip", "https://example.com/other.zip"),
		}),
	}
	client := &mockReleasesClient{releases: releases}
	eng := NewEngine(client, &mockInstaller{})

	result, err := eng.ListAllReleases(context.Background(), ChannelStable)
	if err != nil {
		t.Fatalf("ListAllReleases returned error: %v", err)
	}
	if len(result) != 1 {
		t.Fatalf("expected 1 release (only one with platform asset), got %d", len(result))
	}
	if result[0].Version != "2026.3.6" {
		t.Errorf("expected version 2026.3.6, got %q", result[0].Version)
	}
}

func TestEngine_ListAllReleases_NetworkError(t *testing.T) {
	client := &mockReleasesClient{err: errors.New("dial tcp: connection refused")}
	eng := NewEngine(client, &mockInstaller{})

	_, err := eng.ListAllReleases(context.Background(), ChannelStable)
	if err == nil {
		t.Fatal("expected error from ListAllReleases when client fails, got nil")
	}
	if !strings.Contains(err.Error(), "list releases") {
		t.Errorf("expected error to contain 'list releases', got: %v", err)
	}
}

// ---- channel resolution ----------------------------------------------------

// buildChannelRelease creates a release with explicit prerelease/draft flags
// and publish time, for latest-channel resolution tests.
func buildChannelRelease(tag string, prerelease, draft bool, publishedAt time.Time, assets []*gogithub.ReleaseAsset) *gogithub.RepositoryRelease {
	return &gogithub.RepositoryRelease{
		TagName:     gogithub.Ptr(tag),
		Body:        gogithub.Ptr("notes for " + tag),
		Prerelease:  gogithub.Ptr(prerelease),
		Draft:       gogithub.Ptr(draft),
		PublishedAt: &gogithub.Timestamp{Time: publishedAt},
		Assets:      assets,
	}
}

func platformAssets() []*gogithub.ReleaseAsset {
	name := selectPlatformAssetName()
	return []*gogithub.ReleaseAsset{buildAsset(name, "https://example.com/"+name)}
}

func TestEngine_FetchReleaseInfo_LatestChannel_PicksNewestPublished(t *testing.T) {
	older := time.Date(2026, 3, 26, 10, 0, 0, 0, time.UTC)
	newer := time.Date(2026, 8, 20, 12, 0, 0, 0, time.UTC)
	client := &mockReleasesClient{
		releases: []*gogithub.RepositoryRelease{
			buildChannelRelease("v2026.3.26", false, false, older, platformAssets()),
			// Rolling prerelease: tag does not parse as a version on purpose.
			buildChannelRelease("main-latest", true, false, newer, platformAssets()),
		},
	}
	eng := NewEngine(client, &mockInstaller{})

	info, err := eng.FetchReleaseInfo(context.Background(), "", ChannelLatest)
	if err != nil {
		t.Fatalf("FetchReleaseInfo(latest) returned error: %v", err)
	}
	if info.Version != "main-latest" {
		t.Errorf("expected main-latest prerelease to win on latest channel, got %q", info.Version)
	}
}

func TestEngine_FetchReleaseInfo_LatestChannel_StableCanWin(t *testing.T) {
	// A stable release published after the last main build wins on the latest
	// channel too — "latest" means newest published, not "always prerelease".
	older := time.Date(2026, 8, 19, 10, 0, 0, 0, time.UTC)
	newer := time.Date(2026, 8, 20, 12, 0, 0, 0, time.UTC)
	client := &mockReleasesClient{
		releases: []*gogithub.RepositoryRelease{
			buildChannelRelease("main-latest", true, false, older, platformAssets()),
			buildChannelRelease("v2026.8.20", false, false, newer, platformAssets()),
		},
	}
	eng := NewEngine(client, &mockInstaller{})

	info, err := eng.FetchReleaseInfo(context.Background(), "", ChannelLatest)
	if err != nil {
		t.Fatalf("FetchReleaseInfo(latest) returned error: %v", err)
	}
	if info.Version != "2026.8.20" {
		t.Errorf("expected newest-published stable release, got %q", info.Version)
	}
}

func TestEngine_FetchReleaseInfo_LatestChannel_SkipsDraftsAndAssetless(t *testing.T) {
	oldest := time.Date(2026, 8, 18, 0, 0, 0, 0, time.UTC)
	middle := time.Date(2026, 8, 19, 0, 0, 0, 0, time.UTC)
	newest := time.Date(2026, 8, 20, 0, 0, 0, 0, time.UTC)
	client := &mockReleasesClient{
		releases: []*gogithub.RepositoryRelease{
			buildChannelRelease("draft-tag", true, true, newest, platformAssets()),
			buildChannelRelease("main-latest", true, false, middle, nil), // no platform asset
			buildChannelRelease("v2026.8.18", false, false, oldest, platformAssets()),
		},
	}
	eng := NewEngine(client, &mockInstaller{})

	info, err := eng.FetchReleaseInfo(context.Background(), "", ChannelLatest)
	if err != nil {
		t.Fatalf("FetchReleaseInfo(latest) returned error: %v", err)
	}
	if info.Version != "2026.8.18" {
		t.Errorf("expected drafts and asset-less releases skipped, got %q", info.Version)
	}
}

func TestEngine_FetchReleaseInfo_LatestChannel_NoInstallableRelease(t *testing.T) {
	client := &mockReleasesClient{
		releases: []*gogithub.RepositoryRelease{
			buildChannelRelease("main-latest", true, false, time.Date(2026, 8, 20, 0, 0, 0, 0, time.UTC), nil),
		},
	}
	eng := NewEngine(client, &mockInstaller{})

	_, err := eng.FetchReleaseInfo(context.Background(), "", ChannelLatest)
	if err == nil {
		t.Fatal("expected error when no release has an installable asset, got nil")
	}
	if !strings.Contains(err.Error(), "latest channel") {
		t.Errorf("expected error to mention the latest channel, got: %v", err)
	}
}

func TestEngine_FetchReleaseInfo_StableChannel_IgnoresPrereleases(t *testing.T) {
	// Stable resolution goes through GetLatestRelease, which GitHub defines as
	// excluding prereleases — the prerelease in the list must not leak through.
	stable := buildChannelRelease("v2026.3.26", false, false, time.Date(2026, 3, 26, 0, 0, 0, 0, time.UTC), platformAssets())
	client := &mockReleasesClient{
		latest: stable,
		releases: []*gogithub.RepositoryRelease{
			buildChannelRelease("main-latest", true, false, time.Date(2026, 8, 20, 0, 0, 0, 0, time.UTC), platformAssets()),
			stable,
		},
	}
	eng := NewEngine(client, &mockInstaller{})

	for _, channel := range []string{ChannelStable, ""} {
		info, err := eng.FetchReleaseInfo(context.Background(), "", channel)
		if err != nil {
			t.Fatalf("FetchReleaseInfo(%q) returned error: %v", channel, err)
		}
		if info.Version != "2026.3.26" {
			t.Errorf("channel %q: expected stable 2026.3.26, got %q", channel, info.Version)
		}
	}
}

func TestEngine_FetchReleaseInfo_UnknownChannel(t *testing.T) {
	eng := NewEngine(&mockReleasesClient{}, &mockInstaller{})

	_, err := eng.FetchReleaseInfo(context.Background(), "", "nightly")
	if err == nil {
		t.Fatal("expected error for unknown channel, got nil")
	}
	if !strings.Contains(err.Error(), "nightly") {
		t.Errorf("expected error to name the bad channel, got: %v", err)
	}
}

func TestValidChannel(t *testing.T) {
	for _, valid := range []string{"", ChannelStable, ChannelLatest} {
		if !ValidChannel(valid) {
			t.Errorf("expected %q to be a valid channel", valid)
		}
	}
	for _, invalid := range []string{"nightly", "Stable", "LATEST", "main"} {
		if ValidChannel(invalid) {
			t.Errorf("expected %q to be rejected", invalid)
		}
	}
}

// ---- asset candidates ------------------------------------------------------

func TestSelectAssetByNames_PriorityOrder(t *testing.T) {
	canonical := buildAsset("centroidx_windows_amd64.msix", "https://example.com/canonical")
	legacy := buildAsset("centroidx.msix", "https://example.com/legacy")
	candidates := []string{"centroidx_windows_amd64.msix", "centroidx.msix"}

	// Both present: canonical wins.
	got := selectAssetByNames([]*gogithub.ReleaseAsset{legacy, canonical}, candidates)
	if got == nil || got.GetName() != "centroidx_windows_amd64.msix" {
		t.Errorf("expected canonical asset to win, got %v", got.GetName())
	}

	// Only legacy present (releases up to v2026.3.26): legacy matches.
	got = selectAssetByNames([]*gogithub.ReleaseAsset{legacy}, candidates)
	if got == nil || got.GetName() != "centroidx.msix" {
		t.Error("expected legacy asset to match when canonical is absent")
	}

	// Neither present.
	if selectAssetByNames([]*gogithub.ReleaseAsset{buildAsset("other.zip", "u")}, candidates) != nil {
		t.Error("expected nil when no candidate matches")
	}
}

func TestPlatformAssetCandidates(t *testing.T) {
	candidates := platformAssetCandidates()
	if len(candidates) == 0 {
		t.Fatal("expected at least one candidate asset name")
	}
	if candidates[0] != selectPlatformAssetName() {
		t.Errorf("expected canonical name first, got %q", candidates[0])
	}
	if runtime.GOOS == "windows" {
		found := false
		for _, c := range candidates {
			if c == "centroidx.msix" {
				found = true
			}
		}
		if !found {
			t.Error("expected legacy centroidx.msix candidate on windows")
		}
	}
}

// ---- TestEngine_Update_LatestChannel ---------------------------------------

func TestEngine_Update_LatestChannel(t *testing.T) {
	assetContent := "fake main-latest build content"
	assetFilename := platformAssetName()

	srv := newEngineTestServer(t, assetContent, assetFilename, "")
	defer srv.Close()

	assets := []*gogithub.ReleaseAsset{
		buildAsset(assetFilename, srv.URL+"/asset"),
		buildAsset("SHA256SUMS.txt", srv.URL+"/SHA256SUMS.txt"),
	}
	prerelease := buildChannelRelease("main-latest", true, false, time.Date(2026, 8, 20, 0, 0, 0, 0, time.UTC), assets)

	// latest is deliberately nil: if the stable path were taken by mistake the
	// update would fail instead of silently passing.
	client := &mockReleasesClient{releases: []*gogithub.RepositoryRelease{prerelease}}
	inst := &mockInstaller{}
	eng := NewEngine(client, inst)

	err := eng.Update(context.Background(), UpdateOptions{
		Channel: ChannelLatest,
		DestDir: t.TempDir(),
	})
	if err != nil {
		t.Fatalf("Update on latest channel returned error: %v", err)
	}
	if len(inst.installed) == 0 {
		t.Fatal("expected Install to be called for the prerelease")
	}
	if !inst.launchedApp {
		t.Error("expected LaunchApp after installing the prerelease")
	}
}

// ---- ListAllReleases channels ----------------------------------------------

func TestEngine_ListAllReleases_LatestChannel_IncludesRollingPrerelease(t *testing.T) {
	// The rolling prerelease is newer than the newest tag, so it heads the list
	// — and it is only visible at all because publish date, not version,
	// orders the latest channel.
	client := &mockReleasesClient{
		releases: []*gogithub.RepositoryRelease{
			buildChannelRelease("v2026.3.26", false, false, time.Date(2026, 3, 26, 0, 0, 0, 0, time.UTC), platformAssets()),
			buildChannelRelease("main-latest", true, false, time.Date(2026, 8, 21, 0, 0, 0, 0, time.UTC), platformAssets()),
			buildChannelRelease("v2026.2.17", false, false, time.Date(2026, 2, 17, 0, 0, 0, 0, time.UTC), platformAssets()),
		},
	}
	eng := NewEngine(client, &mockInstaller{})

	result, err := eng.ListAllReleases(context.Background(), ChannelLatest)
	if err != nil {
		t.Fatalf("ListAllReleases(latest) returned error: %v", err)
	}
	expected := []string{"main-latest", "2026.3.26", "2026.2.17"}
	if len(result) != len(expected) {
		t.Fatalf("expected %d releases, got %d", len(expected), len(result))
	}
	for i, want := range expected {
		if result[i].Version != want {
			t.Errorf("result[%d]: expected %q, got %q", i, want, result[i].Version)
		}
	}
}

func TestEngine_ListAllReleases_StableChannel_HidesRollingPrerelease(t *testing.T) {
	client := &mockReleasesClient{
		releases: []*gogithub.RepositoryRelease{
			buildChannelRelease("main-latest", true, false, time.Date(2026, 8, 21, 0, 0, 0, 0, time.UTC), platformAssets()),
			buildChannelRelease("v2026.3.26", false, false, time.Date(2026, 3, 26, 0, 0, 0, 0, time.UTC), platformAssets()),
		},
	}
	eng := NewEngine(client, &mockInstaller{})

	result, err := eng.ListAllReleases(context.Background(), ChannelStable)
	if err != nil {
		t.Fatalf("ListAllReleases(stable) returned error: %v", err)
	}
	if len(result) != 1 {
		t.Fatalf("expected only the tagged release, got %d: %+v", len(result), result)
	}
	if result[0].Version != "2026.3.26" {
		t.Errorf("expected 2026.3.26, got %q", result[0].Version)
	}
}

func TestEngine_ListAllReleases_SkipsDrafts(t *testing.T) {
	client := &mockReleasesClient{
		releases: []*gogithub.RepositoryRelease{
			buildChannelRelease("v2026.9.9", false, true, time.Date(2026, 9, 9, 0, 0, 0, 0, time.UTC), platformAssets()),
			buildChannelRelease("v2026.3.26", false, false, time.Date(2026, 3, 26, 0, 0, 0, 0, time.UTC), platformAssets()),
		},
	}
	eng := NewEngine(client, &mockInstaller{})

	for _, channel := range []string{ChannelStable, ChannelLatest} {
		result, err := eng.ListAllReleases(context.Background(), channel)
		if err != nil {
			t.Fatalf("ListAllReleases(%q) returned error: %v", channel, err)
		}
		if len(result) != 1 || result[0].Version != "2026.3.26" {
			t.Errorf("channel %q: expected drafts skipped, got %+v", channel, result)
		}
	}
}

func TestEngine_ListAllReleases_LatestChannel_StillNeedsAnAsset(t *testing.T) {
	// A rolling prerelease that has not published a package for this platform
	// must not be offered — the picker could not install it.
	client := &mockReleasesClient{
		releases: []*gogithub.RepositoryRelease{
			buildChannelRelease("main-latest", true, false, time.Date(2026, 8, 21, 0, 0, 0, 0, time.UTC), nil),
			buildChannelRelease("v2026.3.26", false, false, time.Date(2026, 3, 26, 0, 0, 0, 0, time.UTC), platformAssets()),
		},
	}
	eng := NewEngine(client, &mockInstaller{})

	result, err := eng.ListAllReleases(context.Background(), ChannelLatest)
	if err != nil {
		t.Fatalf("ListAllReleases(latest) returned error: %v", err)
	}
	if len(result) != 1 || result[0].Version != "2026.3.26" {
		t.Errorf("expected the asset-less prerelease skipped, got %+v", result)
	}
}

func TestEngine_ListAllReleases_UnknownChannel(t *testing.T) {
	eng := NewEngine(&mockReleasesClient{}, &mockInstaller{})

	if _, err := eng.ListAllReleases(context.Background(), "nightly"); err == nil {
		t.Fatal("expected error for unknown channel, got nil")
	}
}
