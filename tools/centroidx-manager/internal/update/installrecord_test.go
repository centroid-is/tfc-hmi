package update

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	gogithub "github.com/google/go-github/v84/github"
)

// TestMain points the whole package's state directory at a throwaway folder.
// Engine.Update records every successful install, so without this every
// engine test would write into the developer's real config directory.
func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "centroidx-manager-test-state-")
	if err != nil {
		panic(err)
	}
	_ = os.Setenv("CENTROIDX_MANAGER_STATE_DIR", dir)
	code := m.Run()
	_ = os.RemoveAll(dir)
	os.Exit(code)
}

// resetStateDir gives one test a state directory of its own, so records left
// by other tests (every successful Engine.Update writes one) cannot leak in.
func resetStateDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("CENTROIDX_MANAGER_STATE_DIR", dir)
	return dir
}

func TestInstallRecord_RoundTrip(t *testing.T) {
	resetStateDir(t)

	saved := InstallRecord{
		ReleaseVersion: "main-latest",
		PackageVersion: "0.2026.8.512",
		Channel:        ChannelLatest,
		PublishedAt:    time.Date(2026, 8, 27, 10, 14, 0, 0, time.UTC),
		InstalledAt:    time.Date(2026, 8, 28, 9, 0, 0, 0, time.UTC),
	}
	if err := SaveInstallRecord(saved); err != nil {
		t.Fatalf("SaveInstallRecord returned error: %v", err)
	}

	loaded, err := LoadInstallRecord()
	if err != nil {
		t.Fatalf("LoadInstallRecord returned error: %v", err)
	}
	if loaded == nil {
		t.Fatal("expected a record, got nil")
	}
	if loaded.ReleaseVersion != saved.ReleaseVersion ||
		loaded.PackageVersion != saved.PackageVersion ||
		loaded.Channel != saved.Channel ||
		!loaded.PublishedAt.Equal(saved.PublishedAt) ||
		!loaded.InstalledAt.Equal(saved.InstalledAt) {
		t.Errorf("round trip changed the record: saved %+v, loaded %+v", saved, *loaded)
	}
}

func TestLoadInstallRecord_NoneIsNotAnError(t *testing.T) {
	resetStateDir(t)

	rec, err := LoadInstallRecord()
	if err != nil {
		t.Fatalf("a station with no record must not error, got: %v", err)
	}
	if rec != nil {
		t.Errorf("expected nil record on a fresh station, got %+v", *rec)
	}
}

func TestLoadInstallRecord_CorruptFileErrors(t *testing.T) {
	dir := resetStateDir(t)
	if err := os.WriteFile(filepath.Join(dir, installRecordFile), []byte("not json"), 0o644); err != nil {
		t.Fatal(err)
	}

	if _, err := LoadInstallRecord(); err == nil {
		t.Fatal("expected an error for a corrupt record, got nil")
	}
}

func TestInstallRecord_DescribesCurrentInstall(t *testing.T) {
	published := time.Date(2026, 8, 27, 10, 14, 0, 0, time.UTC)
	rec := &InstallRecord{PackageVersion: "0.2026.8.512", PublishedAt: published}

	if !rec.DescribesCurrentInstall("0.2026.8.512") {
		t.Error("a matching package version must be recognised")
	}
	if rec.DescribesCurrentInstall("0.2026.8.600") {
		t.Error("a build installed by other means must not be dated by this record")
	}
	if (&InstallRecord{PackageVersion: "", PublishedAt: published}).DescribesCurrentInstall("") {
		t.Error("an empty package version says nothing and must not match anything")
	}
	if (&InstallRecord{PackageVersion: "0.2026.8.512"}).DescribesCurrentInstall("0.2026.8.512") {
		t.Error("a record without a publish time cannot date the install")
	}
	var nilRec *InstallRecord
	if nilRec.DescribesCurrentInstall("0.2026.8.512") {
		t.Error("nil must be safe and false")
	}
}

// The whole point of the record: after installing from the latest channel,
// the publish time of the rolling build must survive on disk, because the
// package version (0.YYYY.M.run) does not carry it.
func TestEngine_Update_RecordsTheInstalledBuild(t *testing.T) {
	resetStateDir(t)

	assetContent := "fake main build"
	assetFilename := platformAssetName()
	srv := newEngineTestServer(t, assetContent, assetFilename, "")
	defer srv.Close()

	published := time.Date(2026, 8, 27, 10, 14, 0, 0, time.UTC)
	prerelease := buildChannelRelease("main-latest", true, false, published, []*gogithub.ReleaseAsset{
		buildAsset(assetFilename, srv.URL+"/asset"),
		buildAsset("SHA256SUMS.txt", srv.URL+"/SHA256SUMS.txt"),
	})

	client := &mockReleasesClient{releases: []*gogithub.RepositoryRelease{prerelease}}
	eng := NewEngine(client, &mockInstaller{})

	if err := eng.Update(context.Background(), UpdateOptions{
		Channel: ChannelLatest,
		DestDir: t.TempDir(),
	}); err != nil {
		t.Fatalf("Update returned error: %v", err)
	}

	rec, err := LoadInstallRecord()
	if err != nil {
		t.Fatalf("LoadInstallRecord returned error: %v", err)
	}
	if rec == nil {
		t.Fatal("expected the update to leave an install record")
	}
	if rec.ReleaseVersion != "main-latest" {
		t.Errorf("expected release version main-latest, got %q", rec.ReleaseVersion)
	}
	if !rec.PublishedAt.Equal(published) {
		t.Errorf("expected the release's publish time %v, got %v", published, rec.PublishedAt)
	}
	if rec.Channel != ChannelLatest {
		t.Errorf("expected channel %q, got %q", ChannelLatest, rec.Channel)
	}
	if rec.InstalledAt.IsZero() {
		t.Error("expected the install time to be stamped")
	}
}

// A record that cannot be written must not fail the update — the station got
// its build; only the picker's dating of it is lost.
func TestEngine_Update_RecordWriteFailureDoesNotFailTheUpdate(t *testing.T) {
	// A state "directory" that is a file: MkdirAll fails.
	blocker := filepath.Join(t.TempDir(), "state")
	if err := os.WriteFile(blocker, []byte("in the way"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("CENTROIDX_MANAGER_STATE_DIR", blocker)

	inst := &mockInstaller{}
	eng, logs := newLoggingEngine(certFixture(t, "present"), inst)

	if err := eng.Update(context.Background(), UpdateOptions{DestDir: t.TempDir()}); err != nil {
		t.Fatalf("a record write failure aborted the update: %v", err)
	}
	if len(inst.installed) == 0 {
		t.Error("expected the install to proceed")
	}
	if !logsContain(*logs, "record") {
		t.Errorf("expected the record failure to be logged; got %v", *logs)
	}
}
