package github

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"

	gogithub "github.com/google/go-github/v84/github"
)

// ReleasesClient is the interface all downstream packages use to interact
// with GitHub Releases. Implementations can be swapped for test doubles.
type ReleasesClient interface {
	GetLatestRelease(ctx context.Context) (*gogithub.RepositoryRelease, error)
	ListReleases(ctx context.Context) ([]*gogithub.RepositoryRelease, error)
	DownloadAsset(ctx context.Context, asset *gogithub.ReleaseAsset) (io.ReadCloser, int64, error)
}

// githubClient is the real implementation of ReleasesClient.
type githubClient struct {
	client *gogithub.Client
	owner  string
	repo   string
	token  string
}

// NewClient creates a ReleasesClient for the given owner/repo.
// Pass a non-empty baseURL to override the GitHub API URL (used in tests with httptest).
func NewClient(owner, repo, token, baseURL string) ReleasesClient {
	var httpClient *http.Client
	if token != "" {
		// Use a transport that injects the Authorization header
		httpClient = &http.Client{
			Transport: &authTransport{token: token, base: http.DefaultTransport},
		}
	}
	client := gogithub.NewClient(httpClient)
	if baseURL != "" {
		parsed, err := url.Parse(baseURL)
		if err == nil {
			client.BaseURL = parsed
		}
	}
	return &githubClient{client: client, owner: owner, repo: repo, token: token}
}

// authTransport injects an Authorization header for GitHub API requests.
type authTransport struct {
	token string
	base  http.RoundTripper
}

func (t *authTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	clone := req.Clone(req.Context())
	clone.Header.Set("Authorization", "Bearer "+t.token)
	return t.base.RoundTrip(clone)
}

func (c *githubClient) GetLatestRelease(ctx context.Context) (*gogithub.RepositoryRelease, error) {
	release, _, err := c.client.Repositories.GetLatestRelease(ctx, c.owner, c.repo)
	if err != nil {
		return nil, fmt.Errorf("get latest release: %w", err)
	}
	return release, nil
}

func (c *githubClient) ListReleases(ctx context.Context) ([]*gogithub.RepositoryRelease, error) {
	opts := &gogithub.ListOptions{PerPage: 30}
	releases, _, err := c.client.Repositories.ListReleases(ctx, c.owner, c.repo, opts)
	if err != nil {
		return nil, fmt.Errorf("list releases: %w", err)
	}
	return releases, nil
}

// DownloadAsset downloads a release asset using the BrowserDownloadURL directly.
// This avoids the CDN auth conflict that occurs when forwarding Authorization headers
// to AWS S3 / release-assets.githubusercontent.com (see Pattern 3 in research).
func (c *githubClient) DownloadAsset(ctx context.Context, asset *gogithub.ReleaseAsset) (io.ReadCloser, int64, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", asset.GetBrowserDownloadURL(), nil)
	if err != nil {
		return nil, 0, fmt.Errorf("create download request: %w", err)
	}
	// Include auth token for GitHub CDN requests (private repos)
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("download asset: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, 0, fmt.Errorf("download failed: HTTP %d for %s", resp.StatusCode, asset.GetName())
	}
	return resp.Body, resp.ContentLength, nil
}
