package platform

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The Go constant and the pubspec have to say the same thing. Windows accepts
// a sideloaded package only when the manifest publisher equals the signing
// certificate subject exactly, and the manager asks the machine store about
// that same subject to decide whether a station already trusts us. If the two
// drift, the store lookup answers "not trusted" forever and every install
// asks for approval it does not need -- or worse, the release cannot be
// signed at all.
func TestPublisherMatchesPubspec(t *testing.T) {
	// internal/platform -> centroidx-manager -> tools -> repo root
	pubspec := filepath.Join("..", "..", "..", "..", "centroid-hmi", "pubspec.yaml")
	data, err := os.ReadFile(pubspec)
	if err != nil {
		t.Skipf("pubspec not readable from here (%v); nothing to compare against", err)
	}

	var got string
	for _, line := range strings.Split(string(data), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "publisher:") {
			got = strings.TrimSpace(strings.TrimPrefix(trimmed, "publisher:"))
			break
		}
	}
	if got == "" {
		t.Fatal("no publisher found in msix_config")
	}
	if got != sideloadPublisherCN {
		t.Errorf("pubspec publisher %q but sideloadPublisherCN %q: a package signed "+
			"under one cannot be recognised through the other", got, sideloadPublisherCN)
	}
}
