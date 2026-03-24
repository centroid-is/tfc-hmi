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

// layoutProgress renders a centered status label with a progress bar below it,
// with a full Solarized Dark background fill.
func layoutProgress(gtx layout.Context, th *material.Theme, state *appState) layout.Dimensions {
	// Fill entire background
	fillBackground(gtx, th.Palette.Bg)

	return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		gtx.Constraints.Max.X = gtx.Dp(unit.Dp(400))
		return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := material.H6(th, state.status)
				if state.err != nil {
					lbl.Color = ColorError()
				} else if state.done {
					lbl.Color = ColorSuccess()
				}
				return lbl.Layout(gtx)
			}),
			layout.Rigid(layout.Spacer{Height: unit.Dp(20)}.Layout),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return drawProgressBar(gtx, state.progress)
			}),
		)
	})
}

// fillBackground paints the entire frame with the given color.
func fillBackground(gtx layout.Context, c color.NRGBA) {
	rect := image.Rect(0, 0, gtx.Constraints.Max.X, gtx.Constraints.Max.Y)
	bg := clip.Rect(rect).Push(gtx.Ops)
	paint.ColorOp{Color: c}.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	bg.Pop()
}

// drawProgressBar renders a horizontal progress bar with Solarized colors.
func drawProgressBar(gtx layout.Context, progress float32) layout.Dimensions {
	width := gtx.Constraints.Max.X
	height := gtx.Dp(unit.Dp(6))

	// Background track (base02 — slightly lighter than bg)
	trackRect := image.Rect(0, 0, width, height)
	trackClip := clip.Rect(trackRect).Push(gtx.Ops)
	paint.ColorOp{Color: ColorSurface()}.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	trackClip.Pop()

	// Filled portion (blue accent)
	if progress > 0 {
		fillWidth := int(float32(width) * progress)
		if fillWidth > width {
			fillWidth = width
		}
		fillRect := image.Rect(0, 0, fillWidth, height)
		fillClip := clip.Rect(fillRect).Push(gtx.Ops)
		paint.ColorOp{Color: ColorAccent()}.Add(gtx.Ops)
		paint.PaintOp{}.Add(gtx.Ops)
		fillClip.Pop()
	}

	return layout.Dimensions{Size: image.Point{X: width, Y: height}}
}
