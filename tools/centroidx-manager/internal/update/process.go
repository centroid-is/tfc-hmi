package update

import "time"

// WaitForPIDExit blocks until the process with the given PID exits, or until
// the timeout elapses. If the process has already exited (or never existed),
// it returns nil immediately.
//
// It delegates to the platform-specific waitForPIDExitPlatform function
// defined in process_unix.go or process_windows.go.
func WaitForPIDExit(pid int, timeout time.Duration) error {
	return waitForPIDExitPlatform(pid, timeout)
}
