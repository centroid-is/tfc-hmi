package ui

import (
	"strings"
	"testing"
	"time"

	"github.com/centroid-is/centroidx-manager/internal/update"
)

// The times in these tests are rendered through formatBuildTime, which is in
// local time — so assertions stick to the stable parts of the text, not the
// clock digits.

func mainLatestAt(published time.Time) []update.ReleaseInfo {
	return []update.ReleaseInfo{{
		Version:     "main-latest",
		PublishedAt: published,
		Prerelease:  true,
	}}
}

func recordFor(pkgVersion string, published time.Time) *update.InstallRecord {
	return &update.InstallRecord{
		ReleaseVersion: "main-latest",
		PackageVersion: pkgVersion,
		Channel:        update.ChannelLatest,
		PublishedAt:    published,
		InstalledAt:    published.Add(2 * time.Hour),
	}
}

// The whole feature: a station on an older main build, looking at the latest
// tab, must be told loudly that a newer build exists — with both timepoints.
func TestUpgradeBanner_NewerMainBuildIsAnnounced(t *testing.T) {
	installedBuild := time.Date(2026, 8, 27, 10, 14, 0, 0, time.UTC)
	newestBuild := time.Date(2026, 8, 30, 9, 2, 0, 0, time.UTC)

	text, upgrade := upgradeBanner(
		mainLatestAt(newestBuild),
		recordFor("0.2026.8.512", installedBuild),
		"0.2026.8.512", true, update.ChannelLatest)

	if !upgrade {
		t.Error("expected the banner to announce an upgrade")
	}
	if !strings.Contains(text, "newer build") {
		t.Errorf("expected the text to say a newer build exists, got %q", text)
	}
	if !strings.Contains(text, formatBuildTime(newestBuild)) {
		t.Errorf("expected the newest build's timepoint in %q", text)
	}
	if !strings.Contains(text, formatBuildTime(installedBuild)) {
		t.Errorf("expected the installed build's timepoint in %q", text)
	}
}

func TestUpgradeBanner_CurrentBuildReadsUpToDate(t *testing.T) {
	published := time.Date(2026, 8, 30, 9, 2, 0, 0, time.UTC)

	text, upgrade := upgradeBanner(
		mainLatestAt(published),
		recordFor("0.2026.8.600", published),
		"0.2026.8.600", true, update.ChannelLatest)

	if upgrade {
		t.Error("the same build must not be announced as an upgrade")
	}
	if !strings.Contains(text, "Up to date") {
		t.Errorf("expected an up-to-date confirmation, got %q", text)
	}
}

// A record for a build that is no longer the installed one (someone
// side-loaded a different package) must not date the wrong build — on the
// latest channel that means saying nothing.
func TestUpgradeBanner_StaleRecordSaysNothingOnLatest(t *testing.T) {
	published := time.Date(2026, 8, 30, 9, 2, 0, 0, time.UTC)

	text, _ := upgradeBanner(
		mainLatestAt(published),
		recordFor("0.2026.8.512", published.Add(-72*time.Hour)),
		"0.2026.8.600", true, update.ChannelLatest)

	if text != "" {
		t.Errorf("a stale record must not produce a banner, got %q", text)
	}
}

func TestUpgradeBanner_NoRecordSaysNothingOnLatest(t *testing.T) {
	text, _ := upgradeBanner(
		mainLatestAt(time.Date(2026, 8, 30, 9, 2, 0, 0, time.UTC)),
		nil, "0.2026.8.600", true, update.ChannelLatest)
	if text != "" {
		t.Errorf("without a record the latest channel cannot compare, got %q", text)
	}
}

// Stable versions order on their own, so even without a record the picker can
// say a release is newer than the installed package.
func TestUpgradeBanner_StableFallsBackToVersionOrder(t *testing.T) {
	releases := []update.ReleaseInfo{{
		Version:     "2026.8.29",
		PublishedAt: time.Date(2026, 8, 29, 12, 0, 0, 0, time.UTC),
	}}

	text, upgrade := upgradeBanner(releases, nil, "2026.8.23.0", true, update.ChannelStable)
	if !upgrade || !strings.Contains(text, "v2026.8.29") {
		t.Errorf("expected a version-based upgrade banner naming v2026.8.29, got %q (upgrade=%v)", text, upgrade)
	}

	// A main build (0.YYYY.M.run) sorts below every release, so a stable
	// release is an upgrade from it — the same rule CI stamps versions by.
	text, upgrade = upgradeBanner(releases, nil, "0.2026.8.512", true, update.ChannelStable)
	if !upgrade || text == "" {
		t.Errorf("expected a stable release to read as an upgrade from a main build, got %q (upgrade=%v)", text, upgrade)
	}

	// Same version installed: nothing to announce.
	text, _ = upgradeBanner(releases, nil, "2026.8.29.0", true, update.ChannelStable)
	if text != "" {
		t.Errorf("an equal version must not produce a banner, got %q", text)
	}
}

func TestUpgradeBanner_SilentWhenNothingInstalledOrListed(t *testing.T) {
	published := time.Date(2026, 8, 30, 9, 2, 0, 0, time.UTC)
	if text, _ := upgradeBanner(mainLatestAt(published), recordFor("0.2026.8.512", published), "0.2026.8.512", false, update.ChannelLatest); text != "" {
		t.Errorf("nothing installed: expected no banner, got %q", text)
	}
	if text, _ := upgradeBanner(nil, recordFor("0.2026.8.512", published), "0.2026.8.512", true, update.ChannelLatest); text != "" {
		t.Errorf("nothing listed: expected no banner, got %q", text)
	}
}

func TestInstalledSummary_DatesTheBuildWhenTheRecordMatches(t *testing.T) {
	published := time.Date(2026, 8, 27, 10, 14, 0, 0, time.UTC)
	rec := recordFor("0.2026.8.512", published)

	text := installedSummary(rec, "0.2026.8.512")
	if !strings.Contains(text, "0.2026.8.512") {
		t.Errorf("expected the package version in %q", text)
	}
	if !strings.Contains(text, "main-latest") {
		t.Errorf("expected the release name in %q", text)
	}
	if !strings.Contains(text, formatBuildTime(published)) {
		t.Errorf("expected the publish timepoint in %q", text)
	}
	if !strings.Contains(text, formatBuildTime(rec.InstalledAt)) {
		t.Errorf("expected the install timepoint in %q", text)
	}
}

func TestInstalledSummary_PlainWithoutARecord(t *testing.T) {
	text := installedSummary(nil, "2026.8.23.0")
	if text != "CentroidX 2026.8.23.0 is installed" {
		t.Errorf("expected the plain installed line, got %q", text)
	}
	if got := installedSummary(nil, ""); got != "CentroidX is installed" {
		t.Errorf("expected the versionless line, got %q", got)
	}
}
