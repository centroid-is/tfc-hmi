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
	return runCommandWithTimeout(t, 30*time.Second, name, args...)
}

// runCommandWithTimeout is runCommand with an explicit deadline, for calls
// that pay a cold-start cost the default 30s does not cover — notably the
// first PowerShell cmdlet lookup on a fresh Windows runner, which triggers a
// full module auto-discovery scan.
func runCommandWithTimeout(t *testing.T, timeout time.Duration, name string, args ...string) (string, string, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
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
