//go:build integration && windows

package platform

import (
	"strings"
	"testing"
)

// TestIntegration_PowerShellAvailable verifies that PowerShell is present on
// the CI runner and that the Add-AppxPackage cmdlet is available. If this test
// fails, the runner image is missing the expected PowerShell environment.
func TestIntegration_PowerShellAvailable(t *testing.T) {
	requireCommand(t, "powershell")

	stdout, stderr, err := runCommand(t,
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command", "Get-Command Add-AppxPackage",
	)
	if err != nil {
		t.Fatalf("Get-Command Add-AppxPackage failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}
	if !strings.Contains(stdout, "Add-AppxPackage") {
		t.Errorf("expected 'Add-AppxPackage' in output; got stdout=%q stderr=%q", stdout, stderr)
	}
}

// TestIntegration_AddAppxPackage_InvalidPath verifies that Add-AppxPackage
// returns a non-zero exit code (not a crash or hang) when given an invalid
// path. This confirms the cmdlet parses correctly and produces a meaningful
// error for bad input — matching the behavior our installer error handling
// relies on.
func TestIntegration_AddAppxPackage_InvalidPath(t *testing.T) {
	requireCommand(t, "powershell")

	stdout, stderr, err := runCommand(t,
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command",
		"Add-AppxPackage -Path 'C:\\nonexistent\\fake.msix' -ErrorAction Stop",
	)
	if err == nil {
		t.Fatalf("expected Add-AppxPackage to fail for nonexistent path, but it succeeded\nstdout: %s\nstderr: %s", stdout, stderr)
	}
	// Verify it produced meaningful error output (not a silent failure).
	combined := stdout + stderr
	if len(strings.TrimSpace(combined)) == 0 {
		t.Errorf("expected error output from Add-AppxPackage, got empty output")
	}
}

// TestIntegration_ImportCertificate_CommandExists verifies that the
// Import-Certificate cmdlet is available on the CI runner. This cmdlet is used
// by trustCertificateWindows to install self-signed certificates into the
// TrustedPeople store.
func TestIntegration_ImportCertificate_CommandExists(t *testing.T) {
	requireCommand(t, "powershell")

	stdout, stderr, err := runCommand(t,
		"powershell",
		"-NoProfile", "-NonInteractive",
		"-Command", "Get-Command Import-Certificate",
	)
	if err != nil {
		t.Fatalf("Get-Command Import-Certificate failed: %v\nstdout: %s\nstderr: %s", err, stdout, stderr)
	}
	if !strings.Contains(stdout, "Import-Certificate") {
		t.Errorf("expected 'Import-Certificate' in output; got stdout=%q stderr=%q", stdout, stderr)
	}
}
