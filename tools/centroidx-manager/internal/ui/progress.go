package ui

import (
	"image"
	"image/color"

	"gioui.org/layout"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget/material"
)

// layoutProgress renders a centered status label with a progress bar below it.
func layoutProgress(gtx layout.Context, th *material.Theme, state *appState) layout.Dimensions {
	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(400))
		return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := material.H6(th, state.status)
				if state.err != nil {
					lbl.Color = color.NRGBA{R: 200, A: 255}
				}
				return lbl.Layout(gtx)
			}),
			layout.Rigid(layout.Spacer{Height: unit.Dp(16)}.Layout),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return drawProgressBar(gtx, th, state.progress)
			}),
		)
	})
}

// drawProgressBar renders a simple horizontal progress bar.
func drawProgressBar(gtx layout.Context, th *material.Theme, progress float32) layout.Dimensions {
	width := gtx.Constraints.Max.X
	height := gtx.Dp(unit.Dp(8))

	// Background track
	trackRect := image.Rect(0, 0, width, height)
	trackClip := clip.Rect(trackRect).Push(gtx.Ops)
	paint.ColorOp{Color: color.NRGBA{R: 220, G: 220, B: 220, A: 255}}.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trackClip.Pop()

	// Filled portion
	if progress > 0 {
		fillWidth := int(float32(width) * progress)
		if fillWidth > width {
			fillWidth = width
		}
		fillRect := image.Rect(0, 0, fillWidth, height)
		fillClip := clip.Rect(fillRect).Push(gtx.Ops)
		paint.ColorOp{Color: th.Palette.ContrastBg}.Add(gtx.Ops)
		paint.PaintOp{}.Add(gtx.Ops)
		fillClip.Pop()
	}

	return layout.Dimensions{Size: image.Point{X: width, Y: height}}
}
