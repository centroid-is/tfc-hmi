package ui

import (
	"context"
	"os"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"

	"github.com/centroid-is/centroidx-manager/internal/update"
)

// runPickerMode loads all available versions and displays the version picker UI.
// It shows a loading label while fetching, then calls ShowVersionPicker on success,
// or ShowError if the fetch fails. All Fyne UI updates from goroutines use fyne.Do().
func runPickerMode(w fyne.Window, eng *update.Engine) {
	label := widget.NewLabel("Loading versions...")
	w.SetContent(label)

	go func() {
		ctx := context.Background()
		releases, err := eng.ListAllReleases(ctx)
		fyne.Do(func() {
			if err != nil {
				ShowError(w, err)
				return
			}
			if len(releases) == 0 {
				w.SetContent(widget.NewLabel("No versions available."))
				return
			}
			list := ShowVersionPicker(w, releases, func(selected update.ReleaseInfo) {
				installVersion(w, eng, selected)
			})
			_ = list
		})
	}()
}

// ShowVersionPicker creates and sets a split list+detail layout in the window
// for selecting and installing versions. It returns the *widget.List for testing.
//
// Parameters:
//   - w: the Fyne window (may be nil in unit tests)
//   - releases: pre-fetched and sorted release list (newest first)
//   - onInstall: called when the user clicks "Install this version"
func ShowVersionPicker(w fyne.Window, releases []update.ReleaseInfo, onInstall func(update.ReleaseInfo)) *widget.List {
	// Detail panel widgets — updated when a list item is selected.
	detailNotes := widget.NewRichTextFromMarkdown("Select a version to see release notes.")
	detailNotes.Wrapping = fyne.TextWrapWord

	installBtn := widget.NewButton("Install this version", nil)
	installBtn.Disable()

	detailPanel := container.NewVBox(detailNotes, installBtn)

	// Build the list widget.
	list := widget.NewList(
		func() int { return len(releases) },
		func() fyne.CanvasObject {
			return widget.NewLabel("template")
		},
		func(id widget.ListItemID, obj fyne.CanvasObject) {
			label := obj.(*widget.Label)
			r := releases[id]
			// Always set text unconditionally to avoid widget-reuse pitfall.
			label.SetText(r.Version + "  " + r.PublishedAt.Format("2006-01-02"))
		},
	)

	// When an item is selected, update the detail panel.
	list.OnSelected = func(id widget.ListItemID) {
		selected := releases[id]
		detailNotes.ParseMarkdown(selected.Notes)
		installBtn.Enable()
		installBtn.OnTapped = func() {
			onInstall(selected)
		}
	}

	// If no window is provided (unit test context), return just the list.
	if w == nil {
		return list
	}

	splitLayout := container.NewHSplit(list, detailPanel)
	splitLayout.SetOffset(0.4) // 40% list / 60% detail

	w.SetTitle("CentroidX Version Manager")
	w.SetContent(splitLayout)
	return list
}

// installVersion opens a progress dialog and runs eng.Update in a goroutine
// for the selected version. On success shows an info dialog; on error calls ShowError.
// All UI updates from the goroutine are wrapped in fyne.Do().
func installVersion(w fyne.Window, eng *update.Engine, selected update.ReleaseInfo) {
	bar, progressDlg := NewProgressDialog(w, "Installing v"+selected.Version+"...")
	progressDlg.Show()

	go func() {
		ctx := context.Background()
		err := eng.Update(ctx, update.UpdateOptions{
			Version: selected.Version,
			DestDir: os.TempDir(),
			OnProgress: func(downloaded, total int64) {
				fyne.Do(func() {
					UpdateProgress(bar, downloaded, total)
				})
			},
		})
		fyne.Do(func() {
			progressDlg.Hide()
			if err != nil {
				ShowError(w, err)
			} else {
				dialog.ShowInformation("Install Complete",
					"CentroidX v"+selected.Version+" has been installed.", w)
			}
		})
	}()
}
