//go:build windows

package platform

import (
	"os/exec"
	"syscall"
)

// createNoWindow is CREATE_NO_WINDOW: the child gets no console at all.
// Without it every PowerShell the installer runs flashes a console window at
// the operator — a dozen black boxes per update, each looking like something
// untrusted just ran.
const createNoWindow = 0x08000000

func hideConsole(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		HideWindow:    true,
		CreationFlags: createNoWindow,
	}
}
