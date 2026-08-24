//go:build !windows

package platform

import "os/exec"

// hideConsole is Windows-only; elsewhere children never open console windows.
func hideConsole(_ *exec.Cmd) {}
