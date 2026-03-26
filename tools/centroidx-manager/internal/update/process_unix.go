//go:build !windows

package update

import (
	"os"
	"syscall"
	"time"
)

// waitForPIDExitPlatform polls the process using Signal(0) until it exits or
// the timeout elapses. On Unix, os.FindProcess always succeeds; Signal(0)
// returns an error when the process is gone (or when we lack permission to
// signal it, which also means it isn't ours to wait for).
//
// On timeout the function returns nil — the caller should not force-kill the
// Flutter app; it is expected to exit voluntarily.
func waitForPIDExitPlatform(pid int, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		p, err := os.FindProcess(pid)
		if err != nil {
			// Doesn't happen on Unix, but treat as "gone".
			return nil
		}
		if err := p.Signal(syscall.Signal(0)); err != nil {
			// Process is gone or we cannot signal it.
			return nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	// Timeout elapsed — process may still be running, but we don't force-kill.
	return nil
}
