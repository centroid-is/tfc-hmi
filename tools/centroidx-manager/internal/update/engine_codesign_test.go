package update

import (
	"strings"
	"testing"

	gogithub "github.com/google/go-github/v84/github"
)

func assetNamed(name, url string) *gogithub.ReleaseAsset {
	return &gogithub.ReleaseAsset{Name: &name, BrowserDownloadURL: &url}
}

// The two certificates are told apart by name alone. If the package trust step
// picked up the code-signing certificate, a station would import it into
// TrustedPeople and then reject the package for an untrusted publisher -- an
// install that fails for a reason nothing in the log would explain.
func TestCertAssets_AreToldApartByName(t *testing.T) {
	assets := []*gogithub.ReleaseAsset{
		assetNamed("centroidx-codesign.cer", "https://example.invalid/codesign.cer"),
		assetNamed("centroidx-sideload.cer", "https://example.invalid/sideload.cer"),
		assetNamed("centroidx.msix", "https://example.invalid/pkg.msix"),
	}

	sideload := pickCertAsset(assets, false)
	if sideload == nil || !strings.Contains(sideload.GetName(), "sideload") {
		t.Fatalf("the package certificate step picked %v", sideload)
	}
	codesign := pickCertAsset(assets, true)
	if codesign == nil || !strings.Contains(codesign.GetName(), "codesign") {
		t.Fatalf("the code-signing step picked %v", codesign)
	}
}

// A release published before any of this exists has no code-signing asset.
// That is the normal case today and must be silent: the install works, the
// prompts just stay anonymous.
func TestCodesignAsset_AbsentIsNotAnError(t *testing.T) {
	assets := []*gogithub.ReleaseAsset{
		assetNamed("centroidx-sideload.cer", "https://example.invalid/sideload.cer"),
	}
	if got := pickCertAsset(assets, true); got != nil {
		t.Fatalf("expected no code-signing asset, got %q", got.GetName())
	}
}
