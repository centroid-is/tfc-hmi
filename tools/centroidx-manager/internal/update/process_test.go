package update

import (
	"os/exec"
	"testing"
	"time"
)

// TestWaitForPIDExit_AlreadyExited verifies that WaitForPIDExit returns nil for a
// PID that does not exist (already exited or never existed).
func TestWaitForPIDExit_AlreadyExited(t *testing.T) {
	// PID 99999999 is virtually guaranteed not to exist on any platform.
	err := WaitForPIDExit(99999999, 2*time.Second)
	if err != nil {
		t.Errorf("expected nil for non-existent PID, got: %v", err)
	}
}

// TestWaitForPIDExit_RunningProcess starts a real subprocess, waits for it
// via WaitForPIDExit, and verifies the call returns after the process exits.
func TestWaitForPIDExit_RunningProcess(t *testing.T) {
	// Start a short-lived subprocess. "go env GOPATH" is available on all CI
	// platforms without needing shell builtins like "sleep".
	cmd := newSleepCommand()
	if err := cmd.Start(); err != nil {
		t.Fatalf("start subprocess: %v", err)
	}
	pid := cmd.Process.Pid

	// Wait for the process asynchronously so we don't block the test.
	done := make(chan error, 1)
	go func() {
		done <- WaitForPIDExit(pid, 5*time.Second)
	}()

	// The process should exit quickly on its own.
	if err := cmd.Wait(); err != nil {
		// Non-zero exit is fine for our purposes.
		_ = err
	}

	// WaitForPIDExit should return within a reasonable time after the process exits.
	select {
	case err := <-done:
		if err != nil {
			t.Errorf("WaitForPIDExit returned error: %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Error("WaitForPIDExit did not return within 10s after process exited")
	}
}

// newSleepCommand returns a cross-platform command that runs briefly then exits.
// Uses "go env GOROOT" which is guaranteed to be available in test environments.
func newSleepCommand() *exec.Cmd {
	// "go env GOROOT" exits immediately — we just need any subprocess.
	return exec.Command("go", "env", "GOROOT")
}
