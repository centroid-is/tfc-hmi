package ui

import (
	"context"
	"fmt"
	"image"
	"log"
	"strings"
	"time"

	"gioui.org/app"
	"gioui.org/layout"
	"gioui.org/op"
	"gioui.org/op/clip"
	"gioui.org/op/paint"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/centroid-is/centroidx-manager/internal/platform"
	"github.com/centroid-is/centroidx-manager/internal/update"
)

// PickerInstaller abstracts the platform install check for the picker.
type PickerInstaller interface {
	IsInstalled() bool
	InstalledVersion() string
	// keepSettings: put the station's configuration aside for the next
	// install, or let it go with the application -- the checkbox beside the
	// Uninstall button.
	Uninstall(keepSettings bool) error
}

// pickerState holds all mutable state for the version picker UI.
type pickerState struct {
	releases       []update.ReleaseInfo
	selected       int
	listState      widget.List
	notesListState widget.List

	// The selected release's notes, one entry per line, and which selection
	// they belong to. A list of lines lays out only what is on screen; the
	// whole notes body as a single label was shaped in full on every frame,
	// and the newest build -- the rolling prerelease, whose notes carry every
	// commit since the last tag -- was the one that felt laggy to click.
	notesCache    []string
	notesCacheFor int

	// The install wizard (Destination -> Certificate -> Install).
	wizard wizardState
	itemClicks     []widget.Clickable
	installBtn     widget.Clickable
	uninstallBtn   widget.Clickable

	// Checked: the station's configuration -- key mappings, page layout,
	// update channel -- is put aside and comes back on the next install.
	// Cleared: it goes with the application. Checked by default, because an
	// uninstall from here is nearly always a step in a rollback or a version
	// change Windows will not do in place, and losing the configuration is
	// not what was being asked for.
	keepSettings   widget.Bool
	stableBtn      widget.Clickable
	latestBtn      widget.Clickable
	channel        string
	loading        bool
	err            error
	installing     bool
	progress       float32
	statusMsg      string
	isInstalled    bool

	// What Get-AppxPackage reports right now; shown beside "is installed"
	// so a failed update reads as "still on 2026.8.22", not as success.
	installedVersion string

	// What the manager last installed and when that build was published —
	// the only place a main-latest install's timepoint survives (the package
	// version 0.YYYY.M.run carries no date). Nil when the manager has never
	// installed here, or the record predates a build installed by other means.
	installRecord *update.InstallRecord
}

// runPickerMode fetches versions and runs the picker event loop.
func runPickerMode(w *app.Window, th *material.Theme, eng *update.Engine, installer PickerInstaller, channel string) {
	if !update.ValidChannel(channel) || channel == "" {
		channel = update.ChannelStable
	}
	state := &pickerState{
		loading:          true,
		selected:         -1,
		channel:          channel,
		notesCacheFor:    -1,
		isInstalled:      installer.IsInstalled(),
		installedVersion: installer.InstalledVersion(),
		installRecord:    loadInstallRecordOrNil(),
	}
	state.keepSettings.Value = true
	state.listState.List.Axis = layout.Vertical
	state.notesListState.List.Axis = layout.Vertical

	loadReleases(state, eng, w)

	var ops op.Ops
	for {
		switch e := w.Event().(type) {
		case app.DestroyEvent:
			return
		case app.FrameEvent:
			gtx := app.NewContext(&ops, e)
			fillBackground(gtx, th.Palette.Bg)
			layoutPicker(gtx, th, state, eng, installer, w)
			e.Frame(gtx.Ops)
		}
	}
}

// loadReleases fetches the release list for the current channel in the
// background and repaints when it lands. Selection and any previous error are
// cleared, because they belong to the channel being replaced.
func loadReleases(state *pickerState, eng *update.Engine, w *app.Window) {
	state.loading = true
	state.err = nil
	state.selected = -1
	state.releases = nil
	state.itemClicks = nil
	channel := state.channel

	go func() {
		releases, err := eng.ListAllReleases(context.Background(), channel)
		// A slow response for a channel the user has since switched away from
		// must not overwrite the current one.
		if state.channel != channel {
			return
		}
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
}

// layoutPicker renders the channel switcher above the split list + detail view.
// notesLines returns the selected release's notes split into lines, cached
// until the selection changes.
// selectedVersion is the version the picker is pointed at, empty when
// nothing is selected (which the engine reads as "newest on the channel").
func (s *pickerState) selectedVersion() string {
	if s.selected < 0 || s.selected >= len(s.releases) {
		return ""
	}
	return s.releases[s.selected].Version
}

func (s *pickerState) notesLines() []string {
	if s.selected < 0 || s.selected >= len(s.releases) {
		return []string{"No release notes available."}
	}
	if s.notesCache != nil && s.notesCacheFor == s.selected {
		return s.notesCache
	}
	notes := s.releases[s.selected].Notes
	if strings.TrimSpace(notes) == "" {
		notes = "No release notes available."
	}
	s.notesCache = strings.Split(strings.ReplaceAll(notes, "\r\n", "\n"), "\n")
	s.notesCacheFor = s.selected
	return s.notesCache
}

// loadInstallRecordOrNil reads the install record, treating a missing or
// unreadable one the same way: the picker simply cannot date the installed
// build. The failure still goes to the log — it is the answer to "why does my
// station not say when its build is from".
func loadInstallRecordOrNil() *update.InstallRecord {
	rec, err := update.LoadInstallRecord()
	if err != nil {
		log.Printf("warn: could not read the install record: %v", err)
		return nil
	}
	return rec
}

// formatBuildTime renders a publish/install timepoint for the UI, in local
// time and to the minute — the rolling main-latest build is republished on
// every merge, so the date alone cannot tell two of the same day's builds
// apart.
func formatBuildTime(t time.Time) string {
	return t.Local().Format("2 Jan 2006 15:04")
}

// upgradeBanner is the line above the version list that answers the question
// the list itself cannot: is the newest build here newer than what this
// station is running? Returns "" when there is nothing trustworthy to say.
// upgrade=true means the banner announces a newer build (and should be loud),
// false means it confirms the station is current.
//
// The comparison is by publish time via the install record, because on the
// latest channel the versions are opaque (main-latest vs 0.YYYY.M.run). On
// stable, when no record helps, the package versions themselves are ordered,
// so a fallback comparison still catches "a release is newer than installed".
func upgradeBanner(releases []update.ReleaseInfo, rec *update.InstallRecord, installedVersion string, isInstalled bool, channel string) (text string, upgrade bool) {
	if !isInstalled || len(releases) == 0 {
		return "", false
	}
	newest := releases[0]
	if rec.DescribesCurrentInstall(installedVersion) {
		if newest.PublishedAt.After(rec.PublishedAt) {
			return fmt.Sprintf(
				"A newer build is available: %s, published %s. The installed build is from %s.",
				displayVersion(newest.Version), formatBuildTime(newest.PublishedAt), formatBuildTime(rec.PublishedAt),
			), true
		}
		return fmt.Sprintf(
			"Up to date: the installed build is the newest on this channel, published %s.",
			formatBuildTime(rec.PublishedAt),
		), false
	}
	// No usable record. Stable versions order on their own; latest-channel
	// tags do not, so there the picker stays silent rather than guessing.
	if channel == update.ChannelStable && installedVersion != "" {
		if platform.ComparePackageVersions(newest.Version, installedVersion) > 0 {
			return fmt.Sprintf(
				"A newer version is available: %s, published %s. Installed: %s.",
				displayVersion(newest.Version), formatBuildTime(newest.PublishedAt), installedVersion,
			), true
		}
	}
	return "", false
}

// installedSummary is the "what is on this machine" line: the package version
// always, and — when the install record vouches for the current build — which
// release it came from, when that build was published, and when it was
// installed.
func installedSummary(rec *update.InstallRecord, installedVersion string) string {
	text := "CentroidX is installed"
	if installedVersion != "" {
		text = "CentroidX " + installedVersion + " is installed"
	}
	if rec.DescribesCurrentInstall(installedVersion) {
		text += fmt.Sprintf(" — the %s build published %s, installed %s",
			displayVersion(rec.ReleaseVersion), formatBuildTime(rec.PublishedAt), formatBuildTime(rec.InstalledAt))
	}
	return text
}

func layoutPicker(gtx layout.Context, th *material.Theme, state *pickerState, eng *update.Engine, installer PickerInstaller, w *app.Window) layout.Dimensions {
	// Channel switching is handled before the loading/error/empty returns, and
	// the switcher is drawn above them — a channel with nothing installable is
	// exactly when the user needs to switch back.
	if state.stableBtn.Clicked(gtx) && state.channel != update.ChannelStable && !state.installing {
		state.channel = update.ChannelStable
		loadReleases(state, eng, w)
	}
	if state.latestBtn.Clicked(gtx) && state.channel != update.ChannelLatest && !state.installing {
		state.channel = update.ChannelLatest
		loadReleases(state, eng, w)
	}

	// Handle install button click: open the wizard rather than starting a
	// download. Where it lands and whether the certificate is trusted are
	// the two things that decide whether an install works at all.
	if state.installBtn.Clicked(gtx) && state.selected >= 0 && state.selected < len(state.releases) && !state.installing {
		state.wizard.open()
	}

	// Handle uninstall button click
	if state.uninstallBtn.Clicked(gtx) && state.isInstalled && !state.installing {
		state.installing = true
		keep := state.keepSettings.Value
		state.statusMsg = "Uninstalling, keeping settings..."
		if !keep {
			state.statusMsg = "Uninstalling and removing settings..."
		}
		go func() {
			if err := installer.Uninstall(keep); err != nil {
				state.statusMsg = userFriendlyMessage(err)
				state.err = err
			} else {
				state.statusMsg = "Uninstalled. Settings come back on the next install."
				if !keep {
					state.statusMsg = "Uninstalled, settings removed."
				}
				state.isInstalled = false
				state.installedVersion = ""
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

	handleWizardEvents(gtx, state, eng, installer, w)

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layoutChannelBar(gtx, th, state)
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return horizontalRule(gtx)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			// The wizard owns the body while it is open.
			if state.wizard.step != stepNone {
				return layoutWizardBody(gtx, th, state, &state.wizard)
			}
			return layoutPickerBody(gtx, th, state, installer, w)
		}),
	)
}

// layoutChannelBar renders the Stable/Latest switcher and says what the
// current channel means, so "development build" is never a surprise.
func layoutChannelBar(gtx layout.Context, th *material.Theme, state *pickerState) layout.Dimensions {
	channelBtn := func(gtx layout.Context, click *widget.Clickable, label, channel string) layout.Dimensions {
		btn := material.Button(th, click, label)
		if state.channel == channel {
			btn.Background = ColorAccent()
		} else {
			btn.Background = ColorSurface()
			btn.Color = ColorMuted()
		}
		return btn.Layout(gtx)
	}

	blurb := "Released versions, tested before release."
	if state.channel == update.ChannelLatest {
		blurb = "Development builds from main — no release testing."
	}

	return layout.Inset{
		Top: unit.Dp(10), Bottom: unit.Dp(10),
		Left: unit.Dp(12), Right: unit.Dp(12),
	}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Alignment: layout.Middle}.Layout(gtx,
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := material.Body2(th, "Channel")
				lbl.Color = ColorMuted()
				return lbl.Layout(gtx)
			}),
			layout.Rigid(layout.Spacer{Width: unit.Dp(10)}.Layout),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return channelBtn(gtx, &state.stableBtn, "Stable", update.ChannelStable)
			}),
			layout.Rigid(layout.Spacer{Width: unit.Dp(6)}.Layout),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return channelBtn(gtx, &state.latestBtn, "Latest", update.ChannelLatest)
			}),
			layout.Rigid(layout.Spacer{Width: unit.Dp(14)}.Layout),
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				lbl := material.Caption(th, blurb)
				lbl.Color = ColorMuted()
				return lbl.Layout(gtx)
			}),
		)
	})
}

// layoutPickerBody renders whatever the current channel has to show: a
// progress message, an error, an empty note, or the list + detail split.
func layoutPickerBody(gtx layout.Context, th *material.Theme, state *pickerState, installer PickerInstaller, w *app.Window) layout.Dimensions {
	if state.loading {
		return layout.Center.Layout(gtx, material.H6(th, "Loading versions...").Layout)
	}
	if state.err != nil && len(state.releases) == 0 {
		lbl := material.H6(th, userFriendlyMessage(state.err))
		lbl.Color = ColorError()
		return layout.Center.Layout(gtx, lbl.Layout)
	}
	if len(state.releases) == 0 {
		return layout.Center.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical, Alignment: layout.Middle}.Layout(gtx,
				layout.Rigid(material.H6(th, "No versions available on this channel.").Layout),
				layout.Rigid(layout.Spacer{Height: unit.Dp(6)}.Layout),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					lbl := material.Body2(th, "Nothing published here has an installable package for this platform.")
					lbl.Color = ColorMuted()
					return lbl.Layout(gtx)
				}),
			)
		})
	}

	bannerText, bannerUpgrade := upgradeBanner(
		state.releases, state.installRecord, state.installedVersion, state.isInstalled, state.channel)

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return layoutUpgradeBanner(gtx, th, bannerText, bannerUpgrade)
		}),
		layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
			return layoutPickerSplit(gtx, th, state)
		}),
	)
}

// layoutUpgradeBanner draws the upgrade/up-to-date line in a bordered strip
// above the list — bordered so "you can upgrade" is something the eye lands
// on, not a caption to hunt for.
func layoutUpgradeBanner(gtx layout.Context, th *material.Theme, text string, upgrade bool) layout.Dimensions {
	if text == "" {
		return layout.Dimensions{}
	}
	color := ColorSuccess()
	if upgrade {
		color = ColorAccent()
	}
	return layout.Inset{
		Top: unit.Dp(10), Bottom: unit.Dp(4),
		Left: unit.Dp(12), Right: unit.Dp(12),
	}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return widget.Border{Color: color, Width: unit.Dp(1), CornerRadius: unit.Dp(4)}.Layout(gtx,
			func(gtx layout.Context) layout.Dimensions {
				return layout.UniformInset(unit.Dp(8)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					gtx.Constraints.Min.X = gtx.Constraints.Max.X
					lbl := material.Body1(th, text)
					lbl.Color = color
					return lbl.Layout(gtx)
				})
			})
	})
}

// layoutPickerSplit is the 35/65 split: list on left, detail on right.
func layoutPickerSplit(gtx layout.Context, th *material.Theme, state *pickerState) layout.Dimensions {
	return layout.Flex{}.Layout(gtx,
		layout.Flexed(0.35, func(gtx layout.Context) layout.Dimensions {
			return layoutVersionList(gtx, th, state)
		}),
		// Separator line
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			wpx := gtx.Dp(unit.Dp(1))
			h := gtx.Constraints.Max.Y
			rect := image.Rect(0, 0, wpx, h)
			c := clip.Rect(rect).Push(gtx.Ops)
			paint.ColorOp{Color: ColorMuted()}.Add(gtx.Ops)
			paint.PaintOp{}.Add(gtx.Ops)
			c.Pop()
			return layout.Dimensions{Size: image.Point{X: wpx, Y: h}}
		}),
		layout.Flexed(0.65, func(gtx layout.Context) layout.Dimensions {
			return layoutDetail(gtx, th, state)
		}),
	)
}

// horizontalRule draws a 1dp separator across the available width.
func horizontalRule(gtx layout.Context) layout.Dimensions {
	wpx := gtx.Constraints.Max.X
	h := gtx.Dp(unit.Dp(1))
	rect := image.Rect(0, 0, wpx, h)
	c := clip.Rect(rect).Push(gtx.Ops)
	paint.ColorOp{Color: ColorMuted()}.Add(gtx.Ops)
	paint.PaintOp{}.Add(gtx.Ops)
	c.Pop()
	return layout.Dimensions{Size: image.Point{X: wpx, Y: h}}
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
							lbl := material.Body1(th, displayVersion(r.Version))
							if i == state.selected {
								lbl.Color = ColorAccent()
							}
							return lbl.Layout(gtx)
						}),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							// To the minute on the development channel: the
							// rolling build is republished on every merge, so
							// two builds from the same day differ only here.
							stamp := r.PublishedAt.Local().Format("2006-01-02")
							if state.channel == update.ChannelLatest {
								stamp = r.PublishedAt.Local().Format("2006-01-02 15:04")
							}
							lbl := material.Caption(th, stamp)
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
				lbl := material.H5(th, displayVersion(r.Version))
				lbl.Color = ColorAccent()
				return lbl.Layout(gtx)
			}),
			// The selected build's timepoint — for main-latest this is the
			// only thing that says which state of main it carries.
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 {
					return layout.Dimensions{}
				}
				r := state.releases[state.selected]
				lbl := material.Body2(th, "Published "+formatBuildTime(r.PublishedAt))
				lbl.Color = ColorMuted()
				return lbl.Layout(gtx)
			}),
			layout.Rigid(layout.Spacer{Height: unit.Dp(12)}.Layout),

			// Release notes (scrollable)
			layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 {
					return layout.Dimensions{}
				}
				lines := state.notesLines()
				return material.List(th, &state.notesListState).Layout(gtx, len(lines), func(gtx layout.Context, i int) layout.Dimensions {
					return material.Body1(th, lines[i]).Layout(gtx)
				})
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

			// Installed status
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if !state.isInstalled {
					return layout.Dimensions{}
				}
				lbl := material.Body2(th, installedSummary(state.installRecord, state.installedVersion))
				lbl.Color = ColorSuccess()
				return layout.Inset{Bottom: unit.Dp(8)}.Layout(gtx, lbl.Layout)
			}),

			// Install / Uninstall buttons
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if state.selected < 0 || state.installing {
					return layout.Dimensions{}
				}
				return layout.Inset{Bottom: unit.Dp(12)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Spacing: layout.SpaceStart}.Layout(gtx,
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							btn := material.Button(th, &state.installBtn, "Install this version")
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
						layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							if !state.isInstalled {
								return layout.Dimensions{}
							}
							cb := material.CheckBox(th, &state.keepSettings, "Keep settings")
							return layout.Inset{Top: unit.Dp(6)}.Layout(gtx, cb.Layout)
						}),
					)
				})
			}),
		)
	})
}
