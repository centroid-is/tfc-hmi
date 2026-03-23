package ui

import (
	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"
)

// NewProgressDialog creates a custom download-progress dialog containing a
// ProgressBar. The dialog uses dialog.NewCustomWithoutButtons (the deprecated
// dialog.NewProgress must NOT be used per project constraints).
//
// Returns the ProgressBar and the dialog. Caller must call dlg.Show() to
// display it and dlg.Hide() when the operation completes.
func NewProgressDialog(win fyne.Window, title string) (*widget.ProgressBar, dialog.Dialog) {
	bar := widget.NewProgressBar()
	bar.Min = 0
	bar.Max = 1

	dlg := dialog.NewCustomWithoutButtons(title, bar, win)
	return bar, dlg
}

// UpdateProgress sets the progress bar value based on bytes downloaded vs total.
// MUST be called via fyne.Do() when invoked from a goroutine (Fyne v2.6+ thread safety).
//
// Example:
//
//	fyne.Do(func() {
//	    ui.UpdateProgress(bar, downloaded, total)
//	})
func UpdateProgress(bar *widget.ProgressBar, downloaded, total int64) {
	if total <= 0 {
		return
	}
	bar.SetValue(float64(downloaded) / float64(total))
}
