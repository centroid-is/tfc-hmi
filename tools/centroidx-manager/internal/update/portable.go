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

// versionFile records which release a portable folder holds.
const versionFile = "CENTROIDX_VERSION"

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
// picks somewhere else: Program Files, where Windows programs live and where
// anyone looking for the HMI will look for it. Writing there needs
// administrator rights, which the manager asks for once, the same way it
// asks for the certificate -- a per-user folder would avoid the prompt but
// hide the install somewhere nobody thinks to look.
func DefaultPortableDir() string {
	if runtime.GOOS == "windows" {
		if pf := os.Getenv("ProgramFiles"); pf != "" {
			return filepath.Join(pf, "CentroidX")
		}
		return filepath.Join(`C:\Program Files`, "CentroidX")
	}
	if dir, err := os.UserHomeDir(); err == nil && dir != "" {
		return filepath.Join(dir, "CentroidX")
	}
	return filepath.Join(os.TempDir(), "CentroidX")
}

// writable reports whether dir (or the nearest existing parent) can be
// written to without elevation. Asked before unpacking so the manager can
// raise one approval prompt up front rather than failing halfway through.
func writable(dir string) bool {
	probe := dir
	for {
		if _, err := os.Stat(probe); err == nil {
			break
		}
		parent := filepath.Dir(probe)
		if parent == probe {
			return false
		}
		probe = parent
	}
	f, err := os.CreateTemp(probe, ".centroidx-write-probe-")
	if err != nil {
		return false
	}
	name := f.Name()
	_ = f.Close()
	_ = os.Remove(name)
	return true
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

	// Program Files is the default, and writing there needs administrator
	// rights: ask Windows for them once, for the whole unpack, rather than
	// failing halfway through with half a program on disk.
	if !writable(destDir) {
		e.log("portable install into %s needs elevation; asking", destDir)
		if err := unpackElevated(zipPath, destDir, info.Version); err != nil {
			return err
		}
		if PortableVersionIn(destDir) != info.Version {
			return fmt.Errorf("the elevated unpack into %s did not complete (was the approval declined?)", destDir)
		}
	} else {
		if err := os.MkdirAll(destDir, 0o755); err != nil {
			return fmt.Errorf("create %s: %w", destDir, err)
		}
		if err := unzip(zipPath, destDir); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(destDir, versionFile),
			[]byte(info.Version+"\n"), 0o644); err != nil {
			return fmt.Errorf("record the installed version: %w", err)
		}
	}

	if exe := FindPortableExe(destDir); exe != "" {
		if err := createShortcut(exe, "CentroidX"); err != nil {
			e.log("warn: could not create the Start-menu shortcut: %v", err)
		}
	}
	e.log("portable install of %s in %s", info.Version, destDir)
	return nil
}

// FindPortableExe locates centroidx.exe inside an unpacked folder. The zip
// carries a top-level centroidx-windows-x64/ directory, so the executable is
// one level down, but a flat layout is accepted too.
func FindPortableExe(dir string) string {
	candidates := []string{
		filepath.Join(dir, "centroidx.exe"),
		filepath.Join(dir, "centroidx-windows-x64", "centroidx.exe"),
	}
	for _, c := range candidates {
		if st, err := os.Stat(c); err == nil && !st.IsDir() {
			return c
		}
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return ""
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		c := filepath.Join(dir, entry.Name(), "centroidx.exe")
		if st, err := os.Stat(c); err == nil && !st.IsDir() {
			return c
		}
	}
	return ""
}

// PortableVersionIn reports the version recorded in a portable folder, or
// empty when there is none.
func PortableVersionIn(dir string) string {
	b, err := os.ReadFile(filepath.Join(dir, versionFile))
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
