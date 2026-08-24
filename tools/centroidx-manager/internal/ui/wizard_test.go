package ui

import (
	"image"
	"testing"

	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget/material"
	"gioui.org/font/gofont"
	"gioui.org/text"
)

func testTheme() *material.Theme {
	th := material.NewTheme()
	th.Shaper = text.NewShaper(text.WithCollection(gofont.Collection()))
	return th
}

func testContext(w, h int) layout.Context {
	var ops op.Ops
	return layout.Context{
		Ops:         &ops,
		Metric:      unit.Metric{PxPerDp: 1, PxPerSp: 1},
		Constraints: layout.Constraints{Max: image.Pt(w, h)},
	}
}

// The folder field has to fill the step's width. Left to shrink-wrap it took
// the width of one character, and the default path came out reading downwards
// -- one letter per line -- which is what Jon saw on the Destination step.
func TestWizard_PortableFolderFieldFillsTheWidth(t *testing.T) {
	th := testTheme()
	wz := &wizardState{}
	wz.open()
	wz.kindEnum.Value = kindPortableValue
	wz.kind = kindPortable
	wz.folder = `C:\Users\Centroid\CentroidX`

	const width = 600
	dims := layoutDestinationStep(testContext(width, 400), th, wz)

	if dims.Size.X < width-40 {
		t.Errorf("the destination step laid out %d px wide inside %d px: the "+
			"folder field is shrink-wrapping again", dims.Size.X, width)
	}
	// A path on one line is about one line tall plus the options above it. A
	// field that wraps per character is taller than the window.
	if dims.Size.Y > 400 {
		t.Errorf("the step is %d px tall in a 400 px box: the path is "+
			"wrapping again", dims.Size.Y)
	}
}

// Managed is the default, and the folder field belongs to Portable alone.
func TestWizard_ManagedStepHasNoFolderField(t *testing.T) {
	th := testTheme()
	wz := &wizardState{}
	wz.open()

	if wz.kindEnum.Value != kindManagedValue {
		t.Fatalf("expected managed selected by default, got %q", wz.kindEnum.Value)
	}
	managed := layoutDestinationStep(testContext(600, 400), th, wz)

	wz.kindEnum.Value = kindPortableValue
	wz.kind = kindPortable
	portable := layoutDestinationStep(testContext(600, 400), th, wz)

	if portable.Size.Y <= managed.Size.Y {
		t.Errorf("portable (%d px) should be taller than managed (%d px): it "+
			"shows the folder field", portable.Size.Y, managed.Size.Y)
	}
}
