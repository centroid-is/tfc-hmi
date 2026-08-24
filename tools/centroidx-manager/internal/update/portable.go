package update

import (
	"archive/zip"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	gogithub "github.com/google/go-github/v84/github"
)

// Portable installs put CentroidX in a folder the operator chooses.
//
// The MSIX package is what an ordinary station should run -- it updates
// itself and Windows manages it -- but its location belongs to Windows, so
// "where do you want it?" has no answer there. The releases also carry a
// plain zip of the same build; unpacking that into a chosen folder is what
// makes the manager behave like a normal installer, and it needs no
// certificate and no elevation.

// portableAssetName is the zip published beside the platform installer.
func portableAssetName() string {
	return fmt.Sprintf("centroidx_%s_x64.zip", runtime.GOOS)
}

// SelectPortableAsset finds the portable zip in a release's assets.
func SelectPortableAsset(assets []*gogithub.ReleaseAsset) *gogithub.ReleaseAsset {
	want := strings.ToLower(portableAssetName())
	for _, a := range assets {
		if strings.ToLower(a.GetName()) == want {
			return a
		}
	}
	return nil
}

// DefaultPortableDir is where a portable install lands unless the operator
// picks somewhere else: beside their other per-user programs, so it needs no
// elevation and survives a Windows reinstall of the machine account.
func DefaultPortableDir() string {
	if dir, err := os.UserHomeDir(); err == nil && dir != "" {
		return filepath.Join(dir, "CentroidX")
	}
	return filepath.Join(os.TempDir(), "CentroidX")
}

// InstallPortable downloads the release's portable zip and unpacks it into
// destDir, replacing whatever is there.
//
// The version installed is recorded in destDir/CENTROIDX_VERSION so the
// picker can say what a folder holds without unpacking it again.
func (e *Engine) InstallPortable(ctx context.Context, version, channel, destDir string, onProgress func(downloaded, total int64)) error {
	if strings.TrimSpace(destDir) == "" {
		return errors.New("choose a folder to install into")
	}

	info, err := e.FetchReleaseInfo(ctx, version, channel)
	if err != nil {
		return err
	}
	asset := SelectPortableAsset(info.Assets)
	if asset == nil {
		return fmt.Errorf("release %s publishes no portable %s", info.Version, portableAssetName())
	}

	staging, err := os.MkdirTemp("", "centroidx-portable-")
	if err != nil {
		return fmt.Errorf("create a staging folder: %w", err)
	}
	defer func() { _ = os.RemoveAll(staging) }()

	// Same download path as the managed install: checksum-verified against
	// the release's SHA256SUMS.txt, not merely fetched.
	checksum := findChecksumAsset(info.Assets)
	if checksum == nil {
		return fmt.Errorf("release %s publishes no checksums", info.Version)
	}
	zipPath, err := DownloadAndVerify(
		ctx,
		asset.GetBrowserDownloadURL(),
		checksum.GetBrowserDownloadURL(),
		asset.GetName(),
		staging,
		onProgress,
	)
	if err != nil {
		return err
	}

	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return fmt.Errorf("create %s: %w", destDir, err)
	}
	if err := unzip(zipPath, destDir); err != nil {
		return err
	}
	_ = os.WriteFile(filepath.Join(destDir, "CENTROIDX_VERSION"), []byte(info.Version+"\n"), 0o644)
	e.log("portable install of %s in %s", info.Version, destDir)
	return nil
}

// PortableVersionIn reports the version recorded in a portable folder, or
// empty when there is none.
func PortableVersionIn(dir string) string {
	b, err := os.ReadFile(filepath.Join(dir, "CENTROIDX_VERSION"))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

// unzip extracts src into dst.
//
// Every entry's path is checked against dst before anything is written: a
// crafted archive with "../" in its names would otherwise write outside the
// folder the operator chose (zip slip). Ours are built by CI, but an
// installer that unpacks a downloaded archive is exactly the place that
// check belongs.
func unzip(src, dst string) error {
	r, err := zip.OpenReader(src)
	if err != nil {
		return fmt.Errorf("open %s: %w", filepath.Base(src), err)
	}
	defer func() { _ = r.Close() }()

	root, err := filepath.Abs(dst)
	if err != nil {
		return err
	}
	for _, f := range r.File {
		target := filepath.Join(root, filepath.FromSlash(f.Name)) //nolint:gosec // checked below
		rel, err := filepath.Rel(root, target)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
			return fmt.Errorf("refusing %q: it would write outside %s", f.Name, dst)
		}
		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(target, 0o755); err != nil {
				return err
			}
			continue
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		if err := writeZipEntry(f, target); err != nil {
			return err
		}
	}
	return nil
}

func writeZipEntry(f *zip.File, target string) error {
	rc, err := f.Open()
	if err != nil {
		return fmt.Errorf("read %s: %w", f.Name, err)
	}
	defer func() { _ = rc.Close() }()

	out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, f.Mode()|0o200)
	if err != nil {
		return fmt.Errorf("write %s: %w", target, err)
	}
	defer func() { _ = out.Close() }()

	// Bounded copy: a zip bomb should not fill the operator's disk before
	// anyone notices. 4 GiB is far above any build we publish.
	const maxEntry = 4 << 30
	if _, err := io.Copy(out, io.LimitReader(rc, maxEntry)); err != nil {
		return fmt.Errorf("write %s: %w", target, err)
	}
	return nil
}

// findChecksumAsset returns the release's SHA256SUMS.txt.
func findChecksumAsset(assets []*gogithub.ReleaseAsset) *gogithub.ReleaseAsset {
	for _, a := range assets {
		if a.GetName() == "SHA256SUMS.txt" {
			return a
		}
	}
	return nil
}
