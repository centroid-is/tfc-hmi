package ui

import (
	"image/color"

	"gioui.org/font"
	"gioui.org/widget/material"
)

// Solarized color palette — matches the Flutter CentroidX app theme.
var (
	solBase03  = color.NRGBA{R: 0, G: 43, B: 54, A: 255}
	solBase02  = color.NRGBA{R: 7, G: 54, B: 66, A: 255}
	solBase01  = color.NRGBA{R: 88, G: 110, B: 117, A: 255}
	solBase00  = color.NRGBA{R: 101, G: 123, B: 131, A: 255}
	solBase0   = color.NRGBA{R: 131, G: 148, B: 150, A: 255}
	solBase1   = color.NRGBA{R: 147, G: 161, B: 161, A: 255}
	solBase2   = color.NRGBA{R: 238, G: 232, B: 213, A: 255}
	solBase3   = color.NRGBA{R: 253, G: 246, B: 227, A: 255}
	solBlue    = color.NRGBA{R: 38, G: 139, B: 210, A: 255}
	solCyan    = color.NRGBA{R: 42, G: 161, B: 152, A: 255}
	solGreen   = color.NRGBA{R: 133, G: 153, B: 0, A: 255}
	solYellow  = color.NRGBA{R: 181, G: 137, B: 0, A: 255}
	solOrange  = color.NRGBA{R: 203, G: 75, B: 22, A: 255}
	solRed     = color.NRGBA{R: 220, G: 50, B: 47, A: 255}
	solMagenta = color.NRGBA{R: 211, G: 54, B: 130, A: 255}
	solViolet  = color.NRGBA{R: 108, G: 113, B: 196, A: 255}
)

// SolarizedDarkTheme returns a Gio material.Theme styled to match the
// CentroidX Flutter app's Solarized Dark theme.
func SolarizedDarkTheme() *material.Theme {
	th := material.NewTheme()

	// Use monospace font to match Flutter's roboto-mono
	th.Face = "monospace"

	// Dark Solarized palette
	th.Palette = material.Palette{
		Bg:         solBase03,  // Dark background
		Fg:         solBase0,   // Light foreground text
		ContrastBg: solBlue,    // Primary accent (buttons, progress)
		ContrastFg: solBase02,  // Text on accent
	}

	// Text styling
	th.TextSize = 14

	return th
}

// SolarizedLightTheme returns a light variant matching Flutter's light theme.
func SolarizedLightTheme() *material.Theme {
	th := material.NewTheme()

	th.Face = "monospace"

	th.Palette = material.Palette{
		Bg:         solBase3,
		Fg:         solBase00,
		ContrastBg: solGreen,
		ContrastFg: solBase2,
	}

	th.TextSize = 14

	return th
}

// ColorError returns the Solarized red for error messages.
func ColorError() color.NRGBA { return solRed }

// ColorSuccess returns Solarized green for success states.
func ColorSuccess() color.NRGBA { return solGreen }

// ColorWarning returns Solarized yellow for warnings.
func ColorWarning() color.NRGBA { return solYellow }

// ColorAccent returns Solarized blue for primary interactive elements.
func ColorAccent() color.NRGBA { return solBlue }

// ColorMuted returns a muted text color for secondary information.
func ColorMuted() color.NRGBA { return solBase01 }

// ColorSurface returns the slightly lighter surface for cards/panels.
func ColorSurface() color.NRGBA { return solBase02 }

// MonospaceFont returns the monospace font face for consistent text rendering.
func MonospaceFont() font.Font {
	return font.Font{Typeface: "monospace"}
}
