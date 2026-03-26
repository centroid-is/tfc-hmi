//go:build integration

package platform

import (
	"context"
	"os/exec"
	"strings"
	"testing"
	"time"
)

// runCommand executes a command with a 30-second timeout and returns stdout,
// stderr, and any error. It is a shared helper for all platform integration
// tests; callers should use t.Helper() in their own wrappers where needed.
func runCommand(t *testing.T, name string, args ...string) (string, string, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	var stdout, stderr strings.Builder
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	return stdout.String(), stderr.String(), err
}

// requireCommand skips the test if the named command cannot be found on PATH.
func requireCommand(t *testing.T, name string) {
	t.Helper()
	if _, err := exec.LookPath(name); err != nil {
		t.Skipf("command %q not found on PATH: %v", name, err)
	}
}
