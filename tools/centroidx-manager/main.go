package main

import (
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/widget"
)

func main() {
	a := app.New()
	w := a.NewWindow("CentroidX Manager")
	w.SetContent(widget.NewLabel("CentroidX Manager v0.1"))
	w.ShowAndRun()
}
