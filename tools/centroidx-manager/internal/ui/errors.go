package ui

import (
	"errors"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"

	"github.com/centroid-is/centroidx-manager/internal/update"
)

// ShowError categorises err and shows a user-friendly Fyne error dialog.
//
// Error categories:
//   - Contains "network", "dial", or "connection refused" → Network Error
//   - Contains "checksum" → Download Verification Failed
//   - Contains "permission" or "access denied" → Permission Error
//   - Default: original error message
func ShowError(win fyne.Window, err error) {
	msg := userFriendlyMessage(err)
	dialog.ShowError(errors.New(msg), win)
}

// userFriendlyMessage converts an error into a human-readable string.
func userFriendlyMessage(err error) string {
	if err == nil {
		return "An unknown error occurred."
	}
	lower := strings.ToLower(err.Error())
	switch {
	case strings.Contains(lower, "network") ||
		strings.Contains(lower, "dial") ||
		strings.Contains(lower, "connection refused") ||
		strings.Contains(lower, "no such host") ||
		strings.Contains(lower, "i/o timeout"):
		return "Network Error: Could not reach the update server. Check your internet connection."

	case strings.Contains(lower, "checksum"):
		return "Download Verification Failed: The downloaded file may be corrupted. Please try again."

	case strings.Contains(lower, "permission") ||
		strings.Contains(lower, "access denied") ||
		strings.Contains(lower, "access is denied"):
		return "Permission Error: The installer needs administrator privileges. Please try running as administrator."

	default:
		return err.Error()
	}
}

// ShowReleaseNotes shows a dialog with the release notes and Install/Cancel buttons.
// onConfirm is called when the user clicks "Install"; nothing happens on "Cancel".
//
// The notes content is rendered using widget.NewRichTextFromMarkdown so that
// GitHub Markdown (headings, lists, bold) is displayed correctly.
func ShowReleaseNotes(win fyne.Window, info *update.ReleaseInfo, onConfirm func()) {
	notes := info.Notes
	if notes == "" {
		notes = "No release notes available."
	}

	notesWidget := widget.NewRichTextFromMarkdown(notes)
	notesWidget.Wrapping = fyne.TextWrapWord

	dialog.NewCustomConfirm(
		"Update Available: v"+info.Version,
		"Install",
		"Cancel",
		notesWidget,
		func(ok bool) {
			if ok {
				onConfirm()
			}
		},
		win,
	).Show()
}
