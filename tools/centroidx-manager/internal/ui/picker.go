package ui

import (
	"context"
	"fmt"
	"os"

	"gioui.org/app"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/centroid-is/centroidx-manager/internal/update"
)

// pickerState holds all mutable state for the version picker UI.
type pickerState struct {
	releases   []update.ReleaseInfo
	selected   int
	listState  widget.List
	installBtn widget.Clickable
	loading    bool
	err        error
	installing bool
	progress   float32
	statusMsg  string
}

// runPickerMode fetches versions and runs the picker event loop.
func runPickerMode(w *app.Window, th *material.Theme, eng *update.Engine) {
	state := &pickerState{
		loading:  true,
		selected: -1,
	}
	state.listState.List.Axis = layout.Vertical

	go func() {
		releases, err := eng.ListAllReleases(context.Background())
		if err != nil {
			state.err = err
			state.loading = false
			w.Invalidate()
			return
		}
		state.releases = releases
		state.loading = false
		w.Invalidate()
	}()

	var ops op.Ops
	for {
		switch e := w.Event().(type) {
		case app.DestroyEvent:
			return
		case app.FrameEvent:
			gtx := app.NewContext(&ops, e)
			layoutPicker(gtx, th, state, eng, w)
			e.Frame(gtx.Ops)
		}
	}
}

// layoutPicker renders the split list + detail view.
func layoutPicker(gtx layout.Context, th *material.Theme, state *pickerState, eng *update.Engine, w *app.Window) layout.Dimensions {
	if state.loading {
		return layout.Center.Layout(gtx, material.H6(th, "Loading versions...").Layout)
	}
	if state.err != nil {
		return layout.Center.Layout(gtx, material.H6(th, userFriendlyMessage(state.err)).Layout)
	}
	if len(state.releases) == 0 {
		return layout.Center.Layout(gtx, material.H6(th, "No versions available.").Layout)
	}

	// Handle install button click
	if state.installBtn.Clicked(gtx) && state.selected >= 0 && !state.installing {
		state.installing = true
		selected := state.releases[state.selected]
		state.statusMsg = fmt.Sprintf("Installing v%s...", selected.Version)
		go func() {
			err := eng.Update(context.Background(), update.UpdateOptions{
				Version: selected.Version,
				DestDir: os.TempDir(),
				OnProgress: func(dl, total int64) {
					if total > 0 {
						state.progress = float32(dl) / float32(total)
						w.Invalidate()
					}
				},
			})
			if err != nil {
				state.err = err
				state.statusMsg = userFriendlyMessage(err)
			} else {
				state.statusMsg = fmt.Sprintf("CentroidX v%s installed!", selected.Version)
			}
			state.installing = false
			w.Invalidate()
		}()
	}

	// 40/60 split: list on left, detail on right
	return layout.Flex{}.Layout(gtx,
		layout.Flexed(0.4, func(gtx layout.Context) layout.Dimensions {
			return layoutVersionList(gtx, th, state)
		}),
		layout.Flexed(0.6, func(gtx layout.Context) layout.Dimensions {
			return layoutDetail(gtx, th, state)
		}),
	)
}

// layoutVersionList renders the scrollable version list.
func layoutVersionList(gtx layout.Context, th *material.Theme, state *pickerState) layout.Dimensions {
	return material.List(th, &state.listState).Layout(gtx, len(state.releases), func(gtx layout.Context, i int) layout.Dimensions {
		r := state.releases[i]
		label := fmt.Sprintf("%s  %s", r.Version, r.PublishedAt.Format("2006-01-02"))

		var clickable widget.Clickable
		if clickable.Clicked(gtx) {
			state.selected = i
		}

		btn := material.Button(th, &clickable, label)
		if i == state.selected {
			btn.Background = th.Palette.ContrastBg
		} else {
			btn.Background = th.Palette.Bg
			btn.Color = th.Palette.Fg
		}
		return btn.Layout(gtx)
	})
}

// layoutDetail renders the right panel with release notes and install button.
func layoutDetail(gtx layout.Context, th *material.Theme, state *pickerState) layout.Dimensions {
	return layout.Inset{Left: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 {
					return material.Body1(th, "Select a version to see release notes.").Layout(gtx)
				}
				r := state.releases[state.selected]
				notes := r.Notes
				if notes == "" {
					notes = "No release notes available."
				}
				return material.Body1(th, notes).Layout(gtx)
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if state.statusMsg != "" {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(material.Body2(th, state.statusMsg).Layout),
						layout.Rigid(layout.Spacer{Height: unit.Dp(4)}.Layout),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return drawProgressBar(gtx, th, state.progress)
						}),
						layout.Rigid(layout.Spacer{Height: unit.Dp(8)}.Layout),
					)
				}
				return layout.Dimensions{}
			}),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 || state.installing {
					return layout.Dimensions{}
				}
				return material.Button(th, &state.installBtn, "Install this version").Layout(gtx)
			}),
		)
	})
}
