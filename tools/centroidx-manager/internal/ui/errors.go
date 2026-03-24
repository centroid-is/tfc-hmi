package ui

import (
	"strings"

	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/centroid-is/centroidx-manager/internal/update"
)

// ConfirmState tracks whether the user has confirmed an action.
type ConfirmState struct {
	installBtn widget.Clickable
	cancelBtn  widget.Clickable
	confirmed  bool
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

// layoutReleaseNotes shows release notes with Install/Cancel buttons.
func layoutReleaseNotes(gtx layout.Context, th *material.Theme, info *update.ReleaseInfo, state *ConfirmState) layout.Dimensions {
	notes := info.Notes
	if notes == "" {
		notes = "No release notes available."
	}

	if state.installBtn.Clicked(gtx) {
		state.confirmed = true
	}

	fillBackground(gtx, th.Palette.Bg)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(500))
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := material.H5(th, "Update Available: v"+info.Version)
				lbl.Color = ColorAccent()
				return lbl.Layout(gtx)
			}),
			layout.Rigid(layout.Spacer{Height: unit.Dp(12)}.Layout),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return material.Body1(th, notes).Layout(gtx)
			}),
			layout.Rigid(layout.Spacer{Height: unit.Dp(12)}.Layout),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Spacing: layout.SpaceStart}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := material.Button(th, &state.installBtn, "Install")
						btn.Background = ColorAccent()
						return btn.Layout(gtx)
					}),
					layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						btn := material.Button(th, &state.cancelBtn, "Cancel")
						btn.Background = ColorSurface()
						return btn.Layout(gtx)
					}),
				)
			}),
		)
	})
}
