package ui

import (
	"archive/zip"
	"bytes"
	"context"
	"fmt"
	"image"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"gioui.org/app"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	ghclient "github.com/centroid-is/centroidx-manager/internal/github"
)

// prPickerState holds state for the PR artifact picker UI.
type prPickerState struct {
	prs          []ghclient.PRInfo
	selected     int
	listState    widget.List
	itemClicks   []widget.Clickable
	installBtn   widget.Clickable
	uninstallBtn widget.Clickable
	loading      bool
	err          error
	installing   bool
	progress     float32
	statusMsg    string
	isInstalled  bool
}

// runPRPickerMode fetches PRs with artifacts and shows a picker.
func runPRPickerMode(w *app.Window, th *material.Theme, client ghclient.PRCapableClient, installer PRInstaller, platformAsset string) {
	state := &prPickerState{
		loading:     true,
		selected:    -1,
		isInstalled: installer.IsInstalled(),
	}
	state.listState.List.Axis = layout.Vertical

	go func() {
		prs, err := client.ListPRsWithArtifacts(context.Background(), platformAsset)
		if err != nil {
			state.err = err
			state.loading = false
			w.Invalidate()
			return
		}
		state.prs = prs
		state.itemClicks = make([]widget.Clickable, len(prs))
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
			layoutPRPicker(gtx, th, state, client, installer, w)
			e.Frame(gtx.Ops)
		}
	}
}

func layoutPRPicker(gtx layout.Context, th *material.Theme, state *prPickerState, client ghclient.PRCapableClient, installer PRInstaller, w *app.Window) layout.Dimensions {
	if state.loading {
		return layout.Center.Layout(gtx, material.H6(th, "Fetching PRs with artifacts...").Layout)
	}
	if state.err != nil {
		lbl := material.H6(th, userFriendlyMessage(state.err))
		lbl.Color = ColorError()
		return layout.Center.Layout(gtx, lbl.Layout)
	}
	if len(state.prs) == 0 {
		lbl := material.H6(th, "No open PRs have build artifacts for this platform.")
		lbl.Color = ColorMuted()
		return layout.Center.Layout(gtx, lbl.Layout)
	}

	// Handle uninstall
	if state.uninstallBtn.Clicked(gtx) && state.isInstalled && !state.installing {
		state.installing = true
		state.statusMsg = "Uninstalling..."
		go func() {
			if err := installer.Uninstall(); err != nil {
				state.statusMsg = userFriendlyMessage(err)
				state.err = err
			} else {
				state.statusMsg = "Uninstalled!"
				state.isInstalled = false
			}
			state.installing = false
			w.Invalidate()
		}()
	}

	// Handle install — pick first MSIX artifact, fall back to first available
	if state.installBtn.Clicked(gtx) && state.selected >= 0 && !state.installing {
		state.installing = true
		pr := state.prs[state.selected]
		art := pickBestArtifact(pr.Artifacts)
		state.statusMsg = fmt.Sprintf("Downloading %s from PR #%d...", art.Name, pr.Number)
		go func() {
			err := downloadAndInstallArtifact(client, installer, art, func(msg string, pct float32) {
				state.statusMsg = msg
				state.progress = pct
				w.Invalidate()
			})
			if err != nil {
				state.err = err
				state.statusMsg = userFriendlyMessage(err)
			} else {
				state.statusMsg = fmt.Sprintf("PR #%d installed!", pr.Number)
				state.isInstalled = true
			}
			state.installing = false
			w.Invalidate()
		}()
	}

	// Handle list clicks
	for i := range state.itemClicks {
		if state.itemClicks[i].Clicked(gtx) {
			state.selected = i
		}
	}

	return layout.Flex{}.Layout(gtx,
		layout.Flexed(0.4, func(gtx layout.Context) layout.Dimensions {
			return layoutPRList(gtx, th, state)
		}),
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
		layout.Flexed(0.6, func(gtx layout.Context) layout.Dimensions {
			return layoutPRDetail(gtx, th, state)
		}),
	)
}

func layoutPRList(gtx layout.Context, th *material.Theme, state *prPickerState) layout.Dimensions {
	return material.List(th, &state.listState).Layout(gtx, len(state.prs), func(gtx layout.Context, i int) layout.Dimensions {
		pr := state.prs[i]

		if i == state.selected {
			rect := image.Rect(0, 0, gtx.Constraints.Max.X, gtx.Dp(unit.Dp(56)))
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
						lbl := material.Body1(th, fmt.Sprintf("#%d %s", pr.Number, pr.Title))
						if i == state.selected {
							lbl.Color = ColorAccent()
						}
						return lbl.Layout(gtx)
					}),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := material.Caption(th, fmt.Sprintf("%s · %s", pr.Author, pr.Branch))
						lbl.Color = ColorMuted()
						return lbl.Layout(gtx)
					}),
				)
			})
		})
	})
}

func layoutPRDetail(gtx layout.Context, th *material.Theme, state *prPickerState) layout.Dimensions {
	return layout.Inset{Left: unit.Dp(16), Right: unit.Dp(16), Top: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 {
					lbl := material.H6(th, "Select a PR to install from")
					lbl.Color = ColorMuted()
					return lbl.Layout(gtx)
				}
				pr := state.prs[state.selected]
				return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := material.H5(th, fmt.Sprintf("PR #%d", pr.Number))
						lbl.Color = ColorAccent()
						return lbl.Layout(gtx)
					}),
					layout.Rigid(layout.Spacer{Height: unit.Dp(4)}.Layout),
					layout.Rigid(material.Body1(th, pr.Title).Layout),
					layout.Rigid(layout.Spacer{Height: unit.Dp(8)}.Layout),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						lbl := material.Body2(th, fmt.Sprintf("Branch: %s\nAuthor: %s\nArtifacts: %d", pr.Branch, pr.Author, len(pr.Artifacts)))
						lbl.Color = ColorMuted()
						return lbl.Layout(gtx)
					}),
				)
			}),
			layout.Rigid(layout.Spacer{Height: unit.Dp(12)}.Layout),
			// Status + progress
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
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				return layout.Dimensions{}
			}),
			// Install / Uninstall buttons
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 || state.installing {
					return layout.Dimensions{}
				}
				return layout.Inset{Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Spacing: layout.SpaceStart}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := material.Button(th, &state.installBtn, "Install from this PR")
							btn.Background = ColorAccent()
							return btn.Layout(gtx)
						}),
						layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if !state.isInstalled {
								return layout.Dimensions{}
							}
							btn := material.Button(th, &state.uninstallBtn, "Uninstall")
							btn.Background = ColorError()
							return btn.Layout(gtx)
						}),
					)
				})
			}),
		)
	})
}

// PRInstaller abstracts the platform install step.
type PRInstaller interface {
	Install(assetPath string) error
	LaunchApp() error
	IsInstalled() bool
	Uninstall() error
}

// pickBestArtifact selects the best artifact to install for the current platform.
// On macOS prefers DMG, on Windows prefers MSIX, falls back to first.
func pickBestArtifact(artifacts []ghclient.PRArtifact) ghclient.PRArtifact {
	for _, a := range artifacts {
		name := strings.ToLower(a.Name)
		if strings.Contains(name, "darwin") || strings.Contains(name, "dmg") {
			if runtime.GOOS == "darwin" {
				return a
			}
		}
		if strings.Contains(name, "msix") || strings.Contains(name, "windows") {
			if runtime.GOOS == "windows" {
				return a
			}
		}
	}
	return artifacts[0]
}

// downloadAndInstallArtifact downloads a GitHub Actions artifact zip, extracts
// the binary, and installs it.
func downloadAndInstallArtifact(client ghclient.PRCapableClient, installer PRInstaller, art ghclient.PRArtifact, onProgress func(string, float32)) error {
	ctx := context.Background()

	onProgress("Downloading artifact...", 0.1)
	body, _, err := client.DownloadArtifact(ctx, art.DownloadURL)
	if err != nil {
		return fmt.Errorf("download artifact: %w", err)
	}
	defer body.Close()

	onProgress("Reading artifact...", 0.4)
	data, err := io.ReadAll(body)
	if err != nil {
		return fmt.Errorf("read artifact: %w", err)
	}

	onProgress("Extracting...", 0.6)
	// GitHub artifacts are zip files — extract the binary
	zipReader, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return fmt.Errorf("open artifact zip: %w", err)
	}

	tmpDir := os.TempDir()
	var extractedPath string
	for _, f := range zipReader.File {
		destPath := filepath.Join(tmpDir, f.Name)
		rc, err := f.Open()
		if err != nil {
			return fmt.Errorf("open zip entry: %w", err)
		}
		outFile, err := os.Create(destPath)
		if err != nil {
			rc.Close()
			return fmt.Errorf("create extracted file: %w", err)
		}
		_, err = io.Copy(outFile, rc)
		rc.Close()
		outFile.Close()
		if err != nil {
			return fmt.Errorf("extract file: %w", err)
		}
		extractedPath = destPath
	}

	if extractedPath == "" {
		return fmt.Errorf("artifact zip was empty")
	}

	onProgress("Installing...", 0.8)
	if err := installer.Install(extractedPath); err != nil {
		return fmt.Errorf("install: %w", err)
	}

	onProgress("Done!", 1.0)
	return nil
}
