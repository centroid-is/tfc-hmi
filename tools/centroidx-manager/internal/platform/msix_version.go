package platform

import (
	"archive/zip"
	"encoding/xml"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// PackageVersionOf reads the Identity Version out of an MSIX.
//
// An MSIX is a zip with an AppxManifest.xml at its root, and the version in
// that manifest -- not the release tag, not the file name -- is what Windows
// compares against what is installed. Reading it before calling
// Add-AppxPackage is what lets the manager say "uninstall first" instead of
// handing the operator a deployment HRESULT.
func PackageVersionOf(msixPath string) (string, error) {
	r, err := zip.OpenReader(msixPath)
	if err != nil {
		return "", fmt.Errorf("open %s: %w", msixPath, err)
	}
	defer func() { _ = r.Close() }()

	for _, f := range r.File {
		if f.Name != "AppxManifest.xml" {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return "", fmt.Errorf("read AppxManifest.xml: %w", err)
		}
		defer func() { _ = rc.Close() }()

		data, err := io.ReadAll(io.LimitReader(rc, 4<<20))
		if err != nil {
			return "", fmt.Errorf("read AppxManifest.xml: %w", err)
		}

		var manifest struct {
			Identity struct {
				Version string `xml:"Version,attr"`
			} `xml:"Identity"`
		}
		if err := xml.Unmarshal(data, &manifest); err != nil {
			return "", fmt.Errorf("parse AppxManifest.xml: %w", err)
		}
		if manifest.Identity.Version == "" {
			return "", fmt.Errorf("AppxManifest.xml carries no Identity version")
		}
		return manifest.Identity.Version, nil
	}
	return "", fmt.Errorf("%s has no AppxManifest.xml", msixPath)
}

// ComparePackageVersions orders two MSIX versions the way Windows does:
// four numeric fields, left to right, missing fields read as zero. It is
// deliberately not semver -- "0.2026.8.512" is four fields and semver rejects
// it, and "2026.8.23.1" would lose its last field.
//
// Returns -1 when a sorts below b, 0 when they are equal, 1 when a is above.
func ComparePackageVersions(a, b string) int {
	fa := versionFields(a)
	fb := versionFields(b)
	for i := 0; i < 4; i++ {
		switch {
		case fa[i] < fb[i]:
			return -1
		case fa[i] > fb[i]:
			return 1
		}
	}
	return 0
}

// versionFields splits a version into its four numeric fields. Anything that
// is not a number reads as zero rather than failing: the caller is deciding
// how to phrase a message, and a malformed version must not stop an install
// that Windows might well accept.
func versionFields(v string) [4]int {
	var out [4]int
	parts := strings.Split(strings.TrimSpace(v), ".")
	for i := 0; i < len(parts) && i < 4; i++ {
		n, err := strconv.Atoi(strings.TrimSpace(parts[i]))
		if err != nil || n < 0 {
			continue
		}
		out[i] = n
	}
	return out
}
