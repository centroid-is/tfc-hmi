package ui

import (
	"context"
	"os"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"

	ghclient "github.com/centroid-is/centroidx-manager/internal/github"
	"github.com/centroid-is/centroidx-manager/internal/platform"
	"github.com/centroid-is/centroidx-manager/internal/update"
)

// Options controls how the Fyne application is started.
type Options struct {
	// Mode is either "install" (first-time) or "update" (triggered by Flutter app).
	Mode string

	// Version is the target version for update mode. Empty means latest.
	Version string

	// WaitPID is the PID of the Flutter process to wait for before installing.
	WaitPID int

	// Token is an optional GitHub API token.
	Token string

	// Owner is the GitHub repo owner (default: centroid-is).
	Owner string

	// Repo is the GitHub repo name (default: tfc-hmi).
	Repo string
}

// Run initialises the Fyne application, creates all engine dependencies,
// and routes to the correct mode (install, update, or picker). It blocks until
// the window is closed or the app exits.
func Run(opts Options) {
	a := app.New()
	w := a.NewWindow("CentroidX Manager")

	// Picker mode uses a wider window for the split list+detail layout.
	if opts.Mode == "picker" {
		w.Resize(fyne.NewSize(700, 500))
	} else {
		w.Resize(fyne.NewSize(500, 400))
	}

	// Resolve token from option or environment variable.
	token := opts.Token
	if token == "" {
		token = os.Getenv("CENTROIDX_GITHUB_TOKEN")
	}

	// Build engine dependencies.
	client := ghclient.NewClient(opts.Owner, opts.Repo, token, "")
	installer := platform.NewInstaller()
	eng := update.NewEngine(client, installer)

	switch opts.Mode {
	case "update":
		runUpdateMode(w, eng, opts)
	case "picker":
		runPickerMode(w, eng)
	default:
		runInstallMode(w, eng)
	}

	w.ShowAndRun()
}

// runInstallMode handles first-time installation:
//  1. Show a status label
//  2. Open a progress dialog
//  3. Spawn a goroutine that calls eng.Install
//  4. On success: success dialog → app exits
//  5. On error: ShowError
func runInstallMode(w fyne.Window, eng *update.Engine) {
	label := widget.NewLabel("Installing CentroidX...")
	w.SetContent(label)

	bar, progressDlg := NewProgressDialog(w, "Downloading CentroidX...")
	progressDlg.Show()

	go func() {
		destDir := os.TempDir()
		err := eng.Install(context.Background(), destDir, func(dl, total int64) {
			fyne.Do(func() {
				UpdateProgress(bar, dl, total)
			})
		})
		fyne.Do(func() {
			progressDlg.Hide()
			if err != nil {
				ShowError(w, err)
			} else {
				dialog.ShowInformation("Installation Complete",
					"CentroidX has been installed successfully.", w)
			}
		})
	}()
}

// runUpdateMode handles the update flow triggered by the Flutter app:
//  1. Fetch release info
//  2. Show release notes dialog (user must confirm)
//  3. On confirm: progress dialog + goroutine calls eng.Update
//  4. On success: success dialog → app exits
//  5. On error: ShowError
func runUpdateMode(w fyne.Window, eng *update.Engine, opts Options) {
	label := widget.NewLabel("Checking for updates...")
	w.SetContent(label)

	go func() {
		ctx := context.Background()
		info, err := eng.FetchReleaseInfo(ctx, opts.Version)
		fyne.Do(func() {
			if err != nil {
				ShowError(w, err)
				return
			}

			ShowReleaseNotes(w, info, func() {
				// User confirmed — start downloading.
				bar, progressDlg := NewProgressDialog(w, "Downloading update v"+info.Version+"...")
				progressDlg.Show()

				go func() {
					destDir := os.TempDir()
					updateErr := eng.Update(ctx, update.UpdateOptions{
						Version:   opts.Version,
						WaitPID:   opts.WaitPID,
						DestDir:   destDir,
						FirstTime: false,
						OnProgress: func(dl, total int64) {
							fyne.Do(func() {
								UpdateProgress(bar, dl, total)
							})
						},
					})
					fyne.Do(func() {
						progressDlg.Hide()
						if updateErr != nil {
							ShowError(w, updateErr)
						} else {
							dialog.ShowInformation("Update Complete",
								"CentroidX v"+info.Version+" has been installed.\nThe app will relaunch now.", w)
						}
					})
				}()
			})
		})
	}()
}
