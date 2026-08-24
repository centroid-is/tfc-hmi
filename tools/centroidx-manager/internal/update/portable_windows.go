//go:build windows

package update

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

const hiddenConsole = 0x08000000 // CREATE_NO_WINDOW

// unpackElevated unpacks src into dst with administrator rights.
//
// Program Files is the default destination -- it is where an operator looks
// for an installed program -- and writing there needs elevation. Windows'
// own approval prompt is raised once for the whole unpack, rather than the
// manager silently choosing a folder nobody would find.
//
// The elevated child runs in a console we cannot read, so its exit code is
// the only signal, and success is confirmed afterwards by the caller looking
// for what it should have written.
func unpackElevated(src, dst, version string) error {
	script := fmt.Sprintf(
		`$ErrorActionPreference='Stop'; `+
			`New-Item -ItemType Directory -Force -Path %s | Out-Null; `+
			`Expand-Archive -LiteralPath %s -DestinationPath %s -Force; `+
			`Set-Content -LiteralPath %s -Value %s`,
		psQuote(dst), psQuote(src), psQuote(dst),
		psQuote(filepath.Join(dst, versionFile)), psQuote(version),
	)

	cmd := exec.Command(
		"powershell", "-NoProfile", "-NonInteractive", "-Command",
		`$p = Start-Process -FilePath 'powershell' -Verb RunAs -Wait -PassThru -WindowStyle Hidden `+
			`-ArgumentList '-NoProfile','-NonInteractive','-Command',`+psQuote(script)+`; `+
			`exit $p.ExitCode`,
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: hiddenConsole}

	out, err := cmd.CombinedOutput()
	if err != nil {
		detail := strings.TrimSpace(string(out))
		if detail == "" {
			detail = err.Error()
		}
		return fmt.Errorf("unpack into %s needs administrator approval: %s", dst, detail)
	}
	return nil
}

// psQuote renders s as a PowerShell single-quoted literal.
func psQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "''") + "'"
}

// createShortcut puts a Start-menu entry for the portable install, so it is
// launched the way every other program is rather than by remembering a path.
// Best effort: a missing shortcut is not a failed install.
func createShortcut(exePath, name string) error {
	menu := os.Getenv("APPDATA")
	if menu == "" {
		return nil
	}
	link := filepath.Join(menu, "Microsoft", "Windows", "Start Menu", "Programs", name+".lnk")
	script := fmt.Sprintf(
		`$s = (New-Object -ComObject WScript.Shell).CreateShortcut(%s); `+
			`$s.TargetPath = %s; $s.WorkingDirectory = %s; $s.Save()`,
		psQuote(link), psQuote(exePath), psQuote(filepath.Dir(exePath)),
	)
	cmd := exec.Command("powershell", "-NoProfile", "-NonInteractive", "-Command", script)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: hiddenConsole}
	return cmd.Run()
}
