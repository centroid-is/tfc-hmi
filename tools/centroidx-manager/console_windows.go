//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

// hideOwnConsole takes away the console window Windows gives a console binary,
// but only when this process is the one it was created for.
//
// The manager is a GUI app in every way that matters, yet double-clicking it
// opened a black console first -- which reads as "something untrusted just
// started", and was the first thing an operator saw of a release. Building with
// `-ldflags -H=windowsgui` fixes it too, but that lives in the release
// workflow; this fixes it in the binary itself, so a locally built manager
// behaves the same as a released one.
//
// GetConsoleProcessList tells us who is attached: exactly one PID means the
// console exists only for us and nobody is reading it, so it goes. More than
// one means we were started from an existing shell -- a developer with
// `centroidx-manager -picker` in a terminal -- and that console stays, along
// with everything the manager logs to it.
//
// Either way the log also goes to %TEMP%\centroidx-manager.log (see
// initLogFile), so hiding the console never costs the diagnostics.
func hideOwnConsole() {
	kernel32 := syscall.NewLazyDLL("kernel32.dll")
	getConsoleWindow := kernel32.NewProc("GetConsoleWindow")
	getConsoleProcessList := kernel32.NewProc("GetConsoleProcessList")
	freeConsole := kernel32.NewProc("FreeConsole")

	hwnd, _, _ := getConsoleWindow.Call()
	if hwnd == 0 {
		return // already a GUI app, or no console at all
	}

	var pids [4]uint32
	n, _, _ := getConsoleProcessList.Call(
		uintptr(unsafe.Pointer(&pids[0])),
		uintptr(len(pids)),
	)
	if n != 1 {
		return // a shell is attached; leave its window alone
	}

	user32 := syscall.NewLazyDLL("user32.dll")
	showWindow := user32.NewProc("ShowWindow")
	const swHide = 0
	showWindow.Call(hwnd, swHide)
	freeConsole.Call()
}
