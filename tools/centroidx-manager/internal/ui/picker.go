package ui

import (
	"context"
	"fmt"
	"image"
	"os"

	"gioui.org/app"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/centroid-is/centroidx-manager/internal/update"
)

// pickerState holds all mutable state for the version picker UI.
type pickerState struct {
	releases    []update.ReleaseInfo
	selected    int
	listState   widget.List
	itemClicks  []widget.Clickable
	installBtn  widget.Clickable
	loading     bool
	err         error
	installing  bool
	progress    float32
	statusMsg   string
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
		state.itemClicks = make([]widget.Clickable, len(releases))
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
			fillBackground(gtx, th.Palette.Bg)
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
		lbl := material.H6(th, userFriendlyMessage(state.err))
		lbl.Color = ColorError()
		return layout.Center.Layout(gtx, lbl.Layout)
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

	// Handle list item clicks
	for i := range state.itemClicks {
		if state.itemClicks[i].Clicked(gtx) {
			state.selected = i
		}
	}

	// 35/65 split: list on left, detail on right
	return layout.Flex{}.Layout(gtx,
		layout.Flexed(0.35, func(gtx layout.Context) layout.Dimensions {
			return layoutVersionList(gtx, th, state)
		}),
		// Separator line
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			w := gtx.Dp(unit.Dp(1))
			h := gtx.Constraints.Max.Y
			rect := image.Rect(0, 0, w, h)
			c := clip.Rect(rect).Push(gtx.Ops)
			paint.ColorOp{Color: ColorMuted()}.Add(gtx.Ops)
			paint.PaintOp{}.Add(gtx.Ops)
			c.Pop()
			return layout.Dimensions{Size: image.Point{X: w, Y: h}}
		}),
		layout.Flexed(0.65, func(gtx layout.Context) layout.Dimensions {
			return layoutDetail(gtx, th, state)
		}),
	)
}

// layoutVersionList renders the scrollable version list with Solarized styling.
func layoutVersionList(gtx layout.Context, th *material.Theme, state *pickerState) layout.Dimensions {
	return material.List(th, &state.listState).Layout(gtx, len(state.releases), func(gtx layout.Context, i int) layout.Dimensions {
		r := state.releases[i]

		return layout.Inset{Top: unit.Dp(1)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			// Draw selection highlight
			if i == state.selected {
				rect := image.Rect(0, 0, gtx.Constraints.Max.X, gtx.Dp(unit.Dp(40)))
				c := clip.Rect(rect).Push(gtx.Ops)
				paint.ColorOp{Color: ColorSurface()}.Add(gtx.Ops)
				paint.PaintOp{}.Add(gtx.Ops)
				c.Pop()
			}

			return material.Clickable(gtx, &state.itemClicks[i], func(gtx layout.Context) layout.Dimensions {
				return layout.Inset{
					Top: unit.Dp(8), Bottom: unit.Dp(8),
					Left: unit.Dp(12), Right: unit.Dp(12),
				}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := material.Body1(th, "v"+r.Version)
							if i == state.selected {
								lbl.Color = ColorAccent()
							}
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							lbl := material.Caption(th, r.PublishedAt.Format("2006-01-02"))
							lbl.Color = ColorMuted()
							return lbl.Layout(gtx)
						}),
					)
				})
			})
		})
	})
}

// layoutDetail renders the right panel with release notes and install button.
func layoutDetail(gtx layout.Context, th *material.Theme, state *pickerState) layout.Dimensions {
	return layout.Inset{Left: unit.Dp(16), Right: unit.Dp(16), Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			// Title
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 {
					lbl := material.H6(th, "Select a version")
					lbl.Color = ColorMuted()
					return lbl.Layout(gtx)
				}
				r := state.releases[state.selected]
				lbl := material.H5(th, "v"+r.Version)
				lbl.Color = ColorAccent()
				return lbl.Layout(gtx)
			}),
			layout.Rigid(layout.Spacer{Height: unit.Dp(12)}.Layout),

			// Release notes
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 {
					return layout.Dimensions{}
				}
				r := state.releases[state.selected]
				notes := r.Notes
				if notes == "" {
					notes = "No release notes available."
				}
				return material.Body1(th, notes).Layout(gtx)
			}),

			// Status + progress (when installing)
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if state.statusMsg == "" {
					return layout.Dimensions{}
				}
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := material.Body2(th, state.statusMsg)
						if state.err != nil {
							lbl.Color = ColorError()
						} else {
							lbl.Color = ColorSuccess()
						}
						return lbl.Layout(gtx)
					}),
					layout.Rigid(layout.Spacer{Height: unit.Dp(6)}.Layout),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return drawProgressBar(gtx, state.progress)
					}),
					layout.Rigid(layout.Spacer{Height: unit.Dp(12)}.Layout),
				)
			}),

			// Install button
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 || state.installing {
					return layout.Dimensions{}
				}
				return layout.Inset{Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					btn := material.Button(th, &state.installBtn, "Install this version")
					btn.Background = ColorAccent()
					return btn.Layout(gtx)
				})
			}),
		)
	})
}
