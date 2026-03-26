package github

import (
	"context"
	"fmt"
	"io"
	"net/http"

	gogithub "github.com/google/go-github/v84/github"
)

// PRCapableClient extends ReleasesClient with PR and artifact operations.
type PRCapableClient interface {
	ListPRsWithArtifacts(ctx context.Context, platformAssetName string) ([]PRInfo, error)
	DownloadArtifact(ctx context.Context, archiveURL string) (io.ReadCloser, int64, error)
}

// AsPRClient returns the client as a PRCapableClient if it supports PR operations.
func AsPRClient(c ReleasesClient) (PRCapableClient, bool) {
	pc, ok := c.(*githubClient)
	return pc, ok
}

// PRArtifact represents a downloadable CI artifact from a PR's workflow run.
type PRArtifact struct {
	Name        string // e.g. "centroidx-manager_windows_amd64.exe"
	DownloadURL string // GitHub API artifact download URL
	SizeBytes   int64
}

// PRInfo holds a pull request and its available CI artifacts.
type PRInfo struct {
	Number    int
	Title     string
	Branch    string
	Author    string
	Artifacts []PRArtifact
}

// ListPRsWithArtifacts fetches open PRs and checks each for build-manager
// workflow artifacts matching the given platform asset name.
func (c *githubClient) ListPRsWithArtifacts(ctx context.Context, platformAssetName string) ([]PRInfo, error) {
	// List open PRs
	pulls, _, err := c.client.PullRequests.List(ctx, c.owner, c.repo, &gogithub.PullRequestListOptions{
		State:       "open",
		ListOptions: gogithub.ListOptions{PerPage: 20},
	})
	if err != nil {
		return nil, fmt.Errorf("list pull requests: %w", err)
	}

	var results []PRInfo
	for _, pr := range pulls {
		info := PRInfo{
			Number: pr.GetNumber(),
			Title:  pr.GetTitle(),
			Branch: pr.GetHead().GetRef(),
			Author: pr.GetUser().GetLogin(),
		}

		// Get workflow runs for this PR's head branch
		artifacts, err := c.fetchBranchArtifacts(ctx, info.Branch, "")
		if err != nil {
			// Skip PRs where we can't fetch artifacts (permissions, etc.)
			continue
		}
		if len(artifacts) == 0 {
			continue // Skip PRs with no matching artifacts
		}
		info.Artifacts = artifacts
		results = append(results, info)
	}

	return results, nil
}

// fetchBranchArtifacts collects artifacts from all platform workflows for a branch.
func (c *githubClient) fetchBranchArtifacts(ctx context.Context, branch, platformAssetName string) ([]PRArtifact, error) {
	workflows := []string{"windows.yml", "macos.yml", "build-manager.yml"}
	var all []PRArtifact
	for _, wf := range workflows {
		arts, err := c.fetchWorkflowArtifacts(ctx, branch, wf)
		if err != nil {
			continue
		}
		all = append(all, arts...)
	}
	return all, nil
}

// fetchWorkflowArtifacts gets artifacts from the latest successful run of a workflow.
func (c *githubClient) fetchWorkflowArtifacts(ctx context.Context, branch, workflowFile string) ([]PRArtifact, error) {
	runs, _, err := c.client.Actions.ListWorkflowRunsByFileName(ctx, c.owner, c.repo, workflowFile, &gogithub.ListWorkflowRunsOptions{
		Branch: branch,
		Status: "success",
		ListOptions: gogithub.ListOptions{PerPage: 1},
	})
	if err != nil {
		return nil, fmt.Errorf("list workflow runs: %w", err)
	}
	if len(runs.WorkflowRuns) == 0 {
		return nil, nil
	}

	latestRun := runs.WorkflowRuns[0]

	// List artifacts for this run
	artList, _, err := c.client.Actions.ListWorkflowRunArtifacts(ctx, c.owner, c.repo, latestRun.GetID(), &gogithub.ListOptions{PerPage: 20})
	if err != nil {
		return nil, fmt.Errorf("list artifacts: %w", err)
	}

	var result []PRArtifact
	for _, a := range artList.Artifacts {
		result = append(result, PRArtifact{
			Name:        a.GetName(),
			DownloadURL: a.GetArchiveDownloadURL(),
			SizeBytes:   a.GetSizeInBytes(),
		})
	}
	return result, nil
}

// DownloadArtifact downloads a workflow artifact zip from its archive URL.
// GitHub Actions artifacts are always returned as zip files.
func (c *githubClient) DownloadArtifact(ctx context.Context, archiveURL string) (io.ReadCloser, int64, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", archiveURL, nil)
	if err != nil {
		return nil, 0, fmt.Errorf("create artifact request: %w", err)
	}
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	req.Header.Set("Accept", "application/vnd.github+json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("download artifact: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, 0, fmt.Errorf("artifact download failed: HTTP %d", resp.StatusCode)
	}
	return resp.Body, resp.ContentLength, nil
}
