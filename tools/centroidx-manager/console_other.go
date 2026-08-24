//go:build !windows

package main

// hideOwnConsole is Windows-only: no other platform hands a GUI binary a
// console window it did not ask for.
func hideOwnConsole() {}
