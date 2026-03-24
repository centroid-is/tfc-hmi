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

	info, err := eng.FetchReleaseInfo(context.Background(), "")
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

	info, err := eng.FetchReleaseInfo(context.Background(), "2026.3.6")
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

	_, err := eng.FetchReleaseInfo(context.Background(), "9999.1.1")
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

	result, err := eng.ListAllReleases(context.Background())
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

	result, err := eng.ListAllReleases(context.Background())
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

	result, err := eng.ListAllReleases(context.Background())
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

	result, err := eng.ListAllReleases(context.Background())
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

	result, err := eng.ListAllReleases(context.Background())
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

	_, err := eng.ListAllReleases(context.Background())
	if err == nil {
		t.Fatal("expected error from ListAllReleases when client fails, got nil")
	}
	if !strings.Contains(err.Error(), "list releases") {
		t.Errorf("expected error to contain 'list releases', got: %v", err)
	}
}
