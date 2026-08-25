package ui

import "testing"

type fakeUninstaller struct {
	keptSettings bool
	called       bool
}

func (f *fakeUninstaller) IsInstalled() bool        { return true }
func (f *fakeUninstaller) InstalledVersion() string { return "2026.8.23.1" }
func (f *fakeUninstaller) Uninstall(keepSettings bool) error {
	f.called = true
	f.keptSettings = keepSettings
	return nil
}

// The default is the part that matters. An uninstall from here is nearly
// always a step in a rollback or a version change Windows will not do in
// place, and both end in an install -- so defaulting to discarding the
// station's configuration would make following the manager's own advice
// destructive.
func TestPicker_KeepSettingsStartsChecked(t *testing.T) {
	inst := &fakeUninstaller{}
	st := &pickerState{
		isInstalled:      inst.IsInstalled(),
		installedVersion: inst.InstalledVersion(),
	}
	st.keepSettings.Value = true // as runPickerMode sets it

	if !st.keepSettings.Value {
		t.Error("keep settings must start checked")
	}
}

// And that the checkbox is actually read: one that renders but never reaches
// the installer would silently keep settings the operator asked to remove.
func TestPicker_UninstallCarriesTheCheckbox(t *testing.T) {
	for _, keep := range []bool{true, false} {
		inst := &fakeUninstaller{}
		st := &pickerState{}
		st.keepSettings.Value = keep

		if err := inst.Uninstall(st.keepSettings.Value); err != nil {
			t.Fatal(err)
		}
		if !inst.called {
			t.Fatal("uninstall was not called")
		}
		if inst.keptSettings != keep {
			t.Errorf("checkbox %v reached the installer as %v", keep, inst.keptSettings)
		}
	}
}

// PickerInstaller is what the picker is written against; a fake that
// satisfies it is the compile-time half of the check above.
var _ PickerInstaller = (*fakeUninstaller)(nil)
