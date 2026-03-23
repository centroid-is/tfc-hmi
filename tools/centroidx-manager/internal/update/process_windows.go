//go:build windows

package update

import (
	"time"

	"golang.org/x/sys/windows"
)

// waitForPIDExitPlatform opens a handle to the process and calls
// WaitForSingleObject to block until the process exits or the timeout elapses.
// If OpenProcess fails (process already gone), it returns nil immediately.
func waitForPIDExitPlatform(pid int, timeout time.Duration) error {
	handle, err := windows.OpenProcess(
		windows.PROCESS_QUERY_LIMITED_INFORMATION|windows.SYNCHRONIZE,
		false,
		uint32(pid),
	)
	if err != nil {
		// Process already gone.
		return nil
	}
	defer windows.CloseHandle(handle)

	millis := uint32(timeout.Milliseconds())
	result, _ := windows.WaitForSingleObject(handle, millis)
	if result == windows.WAIT_OBJECT_0 {
		return nil // Process exited cleanly.
	}
	// Timeout — process may still be running; don't force-kill.
	return nil
}
