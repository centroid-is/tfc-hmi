package github_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	githubclient "github.com/centroid-is/centroidx-manager/internal/github"
)

// testdataPath returns the absolute path to the testdata directory.
func testdataPath(filename string) string {
	_, file, _, _ := runtime.Caller(0)
	dir := filepath.Dir(filepath.Dir(filepath.Dir(file)))
	return filepath.Join(dir, "testdata", filename)
}

func TestListReleases(t *testing.T) {
	fixture, err := os.ReadFile(testdataPath("mock_releases.json"))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/repos/centroid-is/tfc-hmi2/releases", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") == "" {
			t.Error("expected Authorization header to be present")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write(fixture) //nolint:errcheck
	})

	srv := httptest.NewServer(mux)
	defer srv.Close()

	client := githubclient.NewClient("centroid-is", "tfc-hmi2", "test-token", srv.URL+"/")
	releases, err := client.ListReleases(context.Background())
	if err != nil {
		t.Fatalf("ListReleases: %v", err)
	}

	if len(releases) != 2 {
		t.Errorf("expected 2 releases, got %d", len(releases))
	}

	if len(releases) > 0 && releases[0].GetTagName() != "2026.3.6" {
		t.Errorf("expected first tag to be 2026.3.6, got %q", releases[0].GetTagName())
	}
}

func TestGetLatestRelease(t *testing.T) {
	fixture, err := os.ReadFile(testdataPath("mock_release_latest.json"))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/repos/centroid-is/tfc-hmi2/releases/latest", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") == "" {
			t.Error("expected Authorization header to be present")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write(fixture) //nolint:errcheck
	})

	srv := httptest.NewServer(mux)
	defer srv.Close()

	client := githubclient.NewClient("centroid-is", "tfc-hmi2", "test-token", srv.URL+"/")
	release, err := client.GetLatestRelease(context.Background())
	if err != nil {
		t.Fatalf("GetLatestRelease: %v", err)
	}

	if release.GetTagName() != "2026.3.6" {
		t.Errorf("expected tag 2026.3.6, got %q", release.GetTagName())
	}

	if body := release.GetBody(); body == "" {
		t.Error("expected non-empty body")
	} else if len(body) == 0 {
		t.Error("expected body to contain release notes")
	}

	if len(release.Assets) != 4 {
		t.Errorf("expected 4 assets, got %d", len(release.Assets))
	}
}

func TestListReleases_Unauthorized(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/repos/centroid-is/tfc-hmi2/releases", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusUnauthorized)
		w.Write([]byte(`{"message":"Bad credentials"}`)) //nolint:errcheck
	})

	srv := httptest.NewServer(mux)
	defer srv.Close()

	client := githubclient.NewClient("centroid-is", "tfc-hmi2", "bad-token", srv.URL+"/")
	_, err := client.ListReleases(context.Background())
	if err == nil {
		t.Fatal("expected error for 401 response, got nil")
	}
}

func TestGetLatestRelease_NotFound(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/repos/centroid-is/tfc-hmi2/releases/latest", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte(`{"message":"Not Found"}`)) //nolint:errcheck
	})

	srv := httptest.NewServer(mux)
	defer srv.Close()

	client := githubclient.NewClient("centroid-is", "tfc-hmi2", "test-token", srv.URL+"/")
	_, err := client.GetLatestRelease(context.Background())
	if err == nil {
		t.Fatal("expected error for 404 response, got nil")
	}
}
