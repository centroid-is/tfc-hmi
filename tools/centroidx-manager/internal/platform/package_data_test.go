package platform

import (
	"strings"
	"testing"
)

// Removing the package removes its data container, and the station keeps real
// work in there: key mappings, the page layout, the update channel. The
// publisher change is the only thing that reaches the removal path, so this
// runs once per station -- and once is enough to lose it.
func TestSavePackageDataScript_ReadsTheContainerWindowsReports(t *testing.T) {
	script := savePackageDataScript()

	if !strings.Contains(script, "Get-AppxPackage -Name '"+windowsPackageName+"'") {
		t.Errorf("the container has to be located through Windows: %s", script)
	}
	// The family name embeds a hash of the publisher -- which is exactly what
	// is changing -- so it can never be spelled out here.
	if !strings.Contains(script, "$p.PackageFamilyName") {
		t.Errorf("the family name must come from Windows, not from us: %s", script)
	}
	if !strings.Contains(script, `LocalCache\Roaming`) {
		t.Errorf("SharedPreferences lives under LocalCache/Roaming: %s", script)
	}
	if !strings.Contains(script, "$env:TEMP") {
		t.Errorf("the copy has to land outside the container it is saved from: %s", script)
	}
	if !strings.Contains(script, dataNoneToken) || !strings.Contains(script, dataSavedToken) {
		t.Errorf("the script has to say which of the two happened: %s", script)
	}
}

// Nothing to save is the normal case on a fresh station, and it must not read
// as saved -- restoring from a stale backup would put an old configuration
// onto a machine that never had one.
func TestSavePackageData_NoContainerIsNotSaved(t *testing.T) {
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte(dataNoneToken)}, errors: []error{nil}}
	if savePackageData(runner) {
		t.Error("a station with no container reported saved data")
	}
}

func TestSavePackageData_SavedIsReported(t *testing.T) {
	runner := &mockRunnerSeq{outputs: [][]byte{[]byte(dataSavedToken)}, errors: []error{nil}}
	if !savePackageData(runner) {
		t.Error("a saved container was not reported")
	}
}

// The restore reads the family name again: after the install it is a
// different one, which is the entire point of the exercise.
func TestRestorePackageDataScript_TargetsTheNewContainer(t *testing.T) {
	script := restorePackageDataScript()

	if !strings.Contains(script, "$p.PackageFamilyName") {
		t.Errorf("the destination must be re-read after the install: %s", script)
	}
	if !strings.Contains(script, "New-Item -ItemType Directory -Force") {
		t.Errorf("a freshly installed package may have no Roaming folder yet: %s", script)
	}
	if !strings.Contains(script, "-Force") {
		t.Errorf("the saved configuration must win over the defaults: %s", script)
	}

	// The copy is a wildcard -- the container's *contents* move, not the
	// folder itself. -LiteralPath does not expand wildcards: it looked for a
	// file actually named "*", found none, copied nothing, and said it was
	// done. A simulated container caught it; nothing in the Go tests could,
	// so this is the guard.
	if strings.Contains(script, "Copy-Item -LiteralPath") {
		t.Errorf("the wildcard copy must use -Path, or it silently copies nothing: %s", script)
	}
	if !strings.Contains(script, "Copy-Item -Path (Join-Path $src '*')") {
		t.Errorf("expected a wildcard copy of the container contents: %s", script)
	}
}

// Both halves report only what they can see afterwards. Announcing a copy that
// did not happen is how a station loses its settings without anyone noticing:
// the save says done, the removal goes ahead, and the restore finds nothing.
func TestPackageDataScripts_CountFilesBeforeClaimingSuccess(t *testing.T) {
	for name, script := range map[string]string{
		"save":    savePackageDataScript(),
		"restore": restorePackageDataScript(),
	} {
		if !strings.Contains(script, "Get-ChildItem -Recurse -File") {
			t.Errorf("%s: the token is announced without checking anything moved: %s", name, script)
		}
	}
}
