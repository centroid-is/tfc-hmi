package update

import (
	"github.com/centroid-is/centroidx-manager/internal/github"
	"github.com/centroid-is/centroidx-manager/internal/platform"
)

// Engine orchestrates the update lifecycle: check, download, verify, install, relaunch.
// All external dependencies are injected via interfaces for testability.
type Engine struct {
	client    github.ReleasesClient
	installer platform.Installer
}

// NewEngine creates an Engine with the given GitHub client and platform installer.
// Both dependencies are injected so tests can provide mock implementations.
func NewEngine(client github.ReleasesClient, installer platform.Installer) *Engine {
	return &Engine{
		client:    client,
		installer: installer,
	}
}
