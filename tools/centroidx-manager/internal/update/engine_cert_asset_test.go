package update

import (
	"testing"

	gogithub "github.com/google/go-github/v84/github"
)

func assetNamed(name, url string) *gogithub.ReleaseAsset {
	return &gogithub.ReleaseAsset{Name: &name, BrowserDownloadURL: &url}
}

func TestPickCertAsset_FindsTheCertificateAmongTheReleaseAssets(t *testing.T) {
	assets := []*gogithub.ReleaseAsset{
		assetNamed("centroidx.msix", "https://example.invalid/pkg.msix"),
		assetNamed("centroidx-sideload.cer", "https://example.invalid/sideload.cer"),
	}
	got := pickCertAsset(assets)
	if got == nil || got.GetName() != "centroidx-sideload.cer" {
		t.Fatalf("picked %v", got)
	}
}

// A release that publishes no certificate is not an error: the install is
// attempted anyway and fails loudly if the station does not already trust us.
func TestPickCertAsset_AbsentIsNotAnError(t *testing.T) {
	assets := []*gogithub.ReleaseAsset{assetNamed("centroidx.msix", "https://example.invalid/pkg.msix")}
	if got := pickCertAsset(assets); got != nil {
		t.Fatalf("expected no certificate, got %q", got.GetName())
	}
}
