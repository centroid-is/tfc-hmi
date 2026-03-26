package ui

import (
	"context"
	"fmt"
	"os"

	"gioui.org/app"
	"gioui.org/op"
	"gioui.org/unit"
	"gioui.org/widget/material"

	ghclient "github.com/centroid-is/centroidx-manager/internal/github"
	"github.com/centroid-is/centroidx-manager/internal/platform"
	"github.com/centroid-is/centroidx-manager/internal/update"
)

// Options controls how the application is started.
type Options struct {
	Mode        string // "install", "update", "picker", "local-install", "url-install"
	Version     string
	WaitPID     int
	Token       string
	Owner       string
	Repo        string
	LocalPkg    string // Path to local package file (dev mode)
	ArtifactURL string // Direct download URL for CI artifact (dev mode)
}

// Run creates the window and engine, then runs the event loop.
func Run(opts Options) {
	token := opts.Token
	if token == "" {
		token = os.Getenv("CENTROIDX_GITHUB_TOKEN")
	}

	client := ghclient.NewClient(opts.Owner, opts.Repo, token, "")
	installer := platform.NewInstaller()
	eng := update.NewEngine(client, installer)

	go func() {
		w := new(app.Window)

		if opts.Mode == "picker" || opts.Mode == "prs" {
			w.Option(app.Title("CentroidX Version Manager"), app.Size(unit.Dp(700), unit.Dp(500)))
		} else {
			w.Option(app.Title("CentroidX Manager"), app.Size(unit.Dp(500), unit.Dp(400)))
		}

		th := SolarizedDarkTheme()

		switch opts.Mode {
		case "update":
			runUpdateMode(w, th, eng, opts)
		case "picker":
			runPickerMode(w, th, eng, installer)
		case "prs":
			prClient, ok := ghclient.AsPRClient(client)
			if !ok {
				runInstallMode(w, th, eng) // fallback
			} else {
				assetName := update.SelectManagerAssetName()
				runPRPickerMode(w, th, prClient, installer, assetName)
			}
		case "local-install":
			runLocalInstallMode(w, th, eng, opts.LocalPkg)
		case "url-install":
			runURLInstallMode(w, th, eng, opts)
		default:
			runInstallMode(w, th, eng)
		}
	}()
	app.Main()
}

// appState tracks the current UI state for the immediate-mode event loop.
type appState struct {
	status   string
	progress float32
	err      error
	done     bool
}

// runLocalInstallMode installs from a local package file (dev/testing mode).
func runLocalInstallMode(w *app.Window, th *material.Theme, eng *update.Engine, pkgPath string) {
	state := &appState{status: fmt.Sprintf("Installing from local file:\n%s", pkgPath)}

	go func() {
		if err := eng.InstallLocal(pkgPath); err != nil {
			state.err = err
			state.status = userFriendlyMessage(err)
		} else {
			state.status = "Installation complete!"
			state.done = true
		}
		w.Invalidate()
	}()

	var ops op.Ops
	for {
		switch e := w.Event().(type) {
		case app.DestroyEvent:
			return
		case app.FrameEvent:
			gtx := app.NewContext(&ops, e)
			layoutProgress(gtx, th, state)
			e.Frame(gtx.Ops)
		}
	}
}

// runURLInstallMode downloads from a direct URL and installs (dev/CI artifact testing).
func runURLInstallMode(w *app.Window, th *material.Theme, eng *update.Engine, opts Options) {
	state := &appState{status: fmt.Sprintf("Downloading from:\n%s", opts.ArtifactURL)}

	go func() {
		err := eng.InstallFromURL(context.Background(), opts.ArtifactURL, func(dl, total int64) {
			if total > 0 {
				state.progress = float32(dl) / float32(total)
				w.Invalidate()
			}
		})
		if err != nil {
			state.err = err
			state.status = userFriendlyMessage(err)
		} else {
			state.status = "Installation complete!"
			state.done = true
		}
		w.Invalidate()
	}()

	var ops op.Ops
	for {
		switch e := w.Event().(type) {
		case app.DestroyEvent:
			return
		case app.FrameEvent:
			gtx := app.NewContext(&ops, e)
			layoutProgress(gtx, th, state)
			e.Frame(gtx.Ops)
		}
	}
}

// runInstallMode handles first-time installation with a progress display.
func runInstallMode(w *app.Window, th *material.Theme, eng *update.Engine) {
	state := &appState{status: "Installing CentroidX..."}

	go func() {
		destDir := os.TempDir()
		err := eng.Install(context.Background(), destDir, func(dl, total int64) {
			if total > 0 {
				state.progress = float32(dl) / float32(total)
				w.Invalidate()
			}
		})
		if err != nil {
			state.err = err
			state.status = userFriendlyMessage(err)
		} else {
			state.status = "Installation complete!"
			state.done = true
		}
		w.Invalidate()
	}()

	var ops op.Ops
	for {
		switch e := w.Event().(type) {
		case app.DestroyEvent:
			return
		case app.FrameEvent:
			gtx := app.NewContext(&ops, e)
			layoutProgress(gtx, th, state)
			e.Frame(gtx.Ops)
		}
	}
}

// runUpdateMode fetches release info, shows notes, then downloads and installs.
func runUpdateMode(w *app.Window, th *material.Theme, eng *update.Engine, opts Options) {
	state := &appState{status: "Checking for updates..."}
	var releaseInfo *update.ReleaseInfo
	var confirmBtn ConfirmState

	go func() {
		ctx := context.Background()
		info, err := eng.FetchReleaseInfo(ctx, opts.Version)
		if err != nil {
			state.err = err
			state.status = userFriendlyMessage(err)
			w.Invalidate()
			return
		}
		releaseInfo = info
		state.status = fmt.Sprintf("Update available: v%s", info.Version)
		w.Invalidate()
	}()

	var ops op.Ops
	for {
		switch e := w.Event().(type) {
		case app.DestroyEvent:
			return
		case app.FrameEvent:
			gtx := app.NewContext(&ops, e)

			if releaseInfo != nil && !confirmBtn.confirmed {
				layoutReleaseNotes(gtx, th, releaseInfo, &confirmBtn)
				if confirmBtn.confirmed {
					go func() {
						state.status = "Downloading update..."
						w.Invalidate()
						destDir := os.TempDir()
						err := eng.Update(context.Background(), update.UpdateOptions{
							Version: opts.Version,
							WaitPID: opts.WaitPID,
							DestDir: destDir,
							OnProgress: func(dl, total int64) {
								if total > 0 {
									state.progress = float32(dl) / float32(total)
									w.Invalidate()
								}
							},
						})
						if err != nil {
							state.err = err
							state.status = userFriendlyMessage(err)
						} else {
							state.status = fmt.Sprintf("CentroidX v%s installed. Relaunching...", releaseInfo.Version)
							state.done = true
						}
						w.Invalidate()
					}()
				}
			} else {
				layoutProgress(gtx, th, state)
			}
			e.Frame(gtx.Ops)
		}
	}
}
