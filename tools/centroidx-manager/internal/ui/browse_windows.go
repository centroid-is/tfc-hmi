//go:build windows

package ui

import (
	"os/exec"
	"strings"
	"syscall"
)

// browseForFolder opens Windows' own folder picker, starting at start, and
// returns the chosen folder ("" when the operator cancels).
//
// Shelled out to PowerShell rather than bound to the COM dialog directly:
// the manager already runs PowerShell for everything else it asks of Windows,
// and a dialog is not worth a COM apartment and an OLE initialisation in a
// Gio event loop. The console the child would otherwise flash is suppressed
// the same way as the installer's commands.
func browseForFolder(start string) (string, error) {
	const script = `Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.FolderBrowserDialog
$d.Description = 'Choose the folder to install CentroidX into'
$d.ShowNewFolderButton = $true
$d.SelectedPath = $env:CENTROIDX_START_DIR
if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $d.SelectedPath }`

	cmd := exec.Command("powershell", "-NoProfile", "-STA", "-Command", script)
	cmd.Env = append(cmd.Environ(), "CENTROIDX_START_DIR="+start)
	// The dialog is the window the operator sees; the host console is not.
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: 0x08000000}

	out, err := cmd.Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}
