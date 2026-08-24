package ui

import (
	"context"
	"fmt"
	"log"
	"os"

	"gioui.org/app"
	"gioui.org/layout"
	"gioui.org/unit"
	"gioui.org/widget"
	"gioui.org/widget/material"

	"github.com/centroid-is/centroidx-manager/internal/update"
)

// The install wizard: Destination -> Certificate -> Install.
//
// Pressing Install used to start downloading immediately, and the two things
// that decide whether an install works at all -- where it lands and whether
// the signing certificate is trusted -- were invisible until they failed.
// A release met a fresh station and died on 0x800B0109 with "CentroidX is
// installed" on screen. The wizard puts both in front of the operator first,
// in the order a normal installer asks them.

type wizardStep int

const (
	stepNone wizardStep = iota
	stepDestination
	stepCertificate
	stepInstalling
)

// installKind is what the Destination step chooses between.
type installKind int

const (
	// kindManaged is the MSIX: Windows owns the location, the package
	// updates itself, and the signing certificate has to be trusted once.
	kindManaged installKind = iota
	// kindPortable unpacks the release zip into a folder the operator picks.
	// No certificate, no elevation, no auto-update.
	kindPortable
)

// The radio group's values.
const (
	kindManagedValue  = "managed"
	kindPortableValue = "portable"
)

func kindFromValue(v string) installKind {
	if v == kindPortableValue {
		return kindPortable
	}
	return kindManaged
}

type wizardState struct {
	step wizardStep
	kind installKind

	// Destination step. A radio group, not two buttons: side by side their
	// labels were squeezed until "Portable (choose a folder)" wrapped one
	// character per line, and nothing said which one was chosen.
	kindEnum   widget.Enum
	folder     string
	folderInit bool
	browseBtn  widget.Clickable

	// Certificate step
	trusted     bool
	trustKnown  bool
	trustStatus string

	// Navigation
	backBtn   widget.Clickable
	nextBtn   widget.Clickable
	cancelBtn widget.Clickable
}

func (wz *wizardState) open() {
	wz.step = stepDestination
	if wz.kindEnum.Value == "" {
		wz.kindEnum.Value = kindManagedValue
	}
	if !wz.folderInit {
		wz.folder = update.DefaultPortableDir()
		wz.folderInit = true
	}
}

func (wz *wizardState) close() { wz.step = stepNone }

// handleWizardEvents processes the wizard's buttons. Called from the
// picker's layout pass, before anything is drawn.
func handleWizardEvents(
	gtx layout.Context,
	state *pickerState,
	eng *update.Engine,
	installer PickerInstaller,
	w *app.Window,
) {
	wz := &state.wizard
	if wz.step == stepNone {
		return
	}
	if wz.cancelBtn.Clicked(gtx) {
		wz.close()
		return
	}
	if wz.kindEnum.Update(gtx) || wz.kind != kindFromValue(wz.kindEnum.Value) {
		wz.kind = kindFromValue(wz.kindEnum.Value)
	}
	if wz.browseBtn.Clicked(gtx) && !state.installing {
		if picked, err := browseForFolder(wz.folder); err != nil {
			log.Printf("warn: folder picker: %v", err)
		} else if picked != "" {
			wz.folder = picked
		}
	}
	if wz.backBtn.Clicked(gtx) && wz.step == stepCertificate {
		wz.step = stepDestination
	}
	if wz.nextBtn.Clicked(gtx) && !state.installing {
		switch wz.step {
		case stepDestination:
			if wz.kind == kindPortable {
				// Portable needs no certificate: nothing verifies a zip.
				startInstall(state, eng, installer, w)
			} else {
				wz.step = stepCertificate
				wz.refreshTrust(installer)
			}
		case stepCertificate:
			if wz.trustKnown && wz.trusted {
				startInstall(state, eng, installer, w)
				return
			}
			// Next does the trusting -- there is no separate button to find.
			// Windows shows one approval prompt; the install follows it.
			state.installing = true
			wz.trustStatus = "Waiting for the Windows approval prompt..."
			version := state.selectedVersion()
			go func() {
				err := eng.TrustCertificateFor(context.Background(), version, state.channel)
				state.installing = false
				if err != nil {
					// Stay on the step: installing now would only fail with
					// 0x800B0109, and the message says what to do instead.
					wz.trustStatus = userFriendlyMessage(err)
					w.Invalidate()
					return
				}
				wz.trusted = true
				wz.trustKnown = true
				wz.trustStatus = "Certificate trusted."
				startInstall(state, eng, installer, w)
				w.Invalidate()
			}()
		}
	}
}

// refreshTrust asks the platform whether the certificate is already trusted,
// so the step can say "nothing to do here" instead of making every operator
// approve a prompt they do not need.
func (wz *wizardState) refreshTrust(installer PickerInstaller) {
	if checker, ok := installer.(interface{ CertificateTrusted() bool }); ok {
		wz.trusted = checker.CertificateTrusted()
		wz.trustKnown = true
		return
	}
	wz.trustKnown = false
}

func layoutWizardBody(gtx layout.Context, th *material.Theme, state *pickerState, wz *wizardState) layout.Dimensions {
	title := "Where should CentroidX go?"
	if wz.step == stepCertificate {
		title = "Publisher certificate"
	}

	return layout.UniformInset(unit.Dp(16)).Layout(gtx, func(gtx layout.Context) layout.Dimensions {
		return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
			layout.Rigid(material.H6(th, title).Layout),
			layout.Rigid(layout.Spacer{Height: unit.Dp(4)}.Layout),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				lbl := material.Body2(th, "Installing "+displayVersion(state.selectedVersion()))
				lbl.Color = ColorMuted()
				return lbl.Layout(gtx)
			}),
			layout.Rigid(layout.Spacer{Height: unit.Dp(14)}.Layout),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				if wz.step == stepDestination {
					return layoutDestinationStep(gtx, th, wz)
				}
				return layoutCertificateStep(gtx, th, wz)
			}),
			layout.Rigid(layout.Spacer{Height: unit.Dp(18)}.Layout),
			layout.Rigid(func(gtx layout.Context) layout.Dimensions {
				return layout.Flex{Spacing: layout.SpaceStart}.Layout(gtx,
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						return material.Button(th, &wz.cancelBtn, "Cancel").Layout(gtx)
					}),
					layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						if wz.step != stepCertificate {
							return layout.Dimensions{}
						}
						return material.Button(th, &wz.backBtn, "Back").Layout(gtx)
					}),
					layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
					layout.Rigid(func(gtx layout.Context) layout.Dimensions {
						label := "Next"
						if wz.step == stepCertificate || wz.kind == kindPortable {
							label = "Install"
						}
						btn := material.Button(th, &wz.nextBtn, label)
						btn.Background = ColorAccent()
						return btn.Layout(gtx)
					}),
				)
			}),
		)
	})
}

func layoutDestinationStep(gtx layout.Context, th *material.Theme, wz *wizardState) layout.Dimensions {
	option := func(gtx layout.Context, value, title, description string) layout.Dimensions {
		selected := wz.kindEnum.Value == value
		return layout.Inset{Bottom: unit.Dp(10)}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
			return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					rb := material.RadioButton(th, &wz.kindEnum, value, title)
					if selected {
						rb.Color = ColorAccent()
						rb.IconColor = ColorAccent()
					}
					return rb.Layout(gtx)
				}),
				layout.Rigid(func(gtx layout.Context) layout.Dimensions {
					return layout.Inset{Left: unit.Dp(34), Top: unit.Dp(2)}.Layout(gtx,
						func(gtx layout.Context) layout.Dimensions {
							lbl := material.Body2(th, description)
							lbl.Color = ColorMuted()
							return lbl.Layout(gtx)
						})
				}),
			)
		})
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return option(gtx, kindManagedValue, "Managed  —  recommended",
				"Windows installs the packaged app and keeps it up to date. Its folder "+
					"belongs to Windows (WindowsApps); settings live in %APPDATA%\\centroidx.")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			return option(gtx, kindPortableValue, "Portable  —  choose a folder",
				"Unpacks this build into the folder below -- Program Files by "+
					"default, which asks for administrator approval once -- and adds a "+
					"Start-menu entry. No certificate, and it will not update itself.")
		}),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if wz.kind != kindPortable {
				return layout.Dimensions{}
			}
			// A label and a Browse button, not a text editor: the operator
			// picks a folder the way every installer lets them, and there is
			// nothing to mistype.
			return layout.Inset{Left: unit.Dp(34), Top: unit.Dp(2)}.Layout(gtx,
				func(gtx layout.Context) layout.Dimensions {
					return layout.Flex{Alignment: layout.Middle}.Layout(gtx,
						layout.Flexed(1, func(gtx layout.Context) layout.Dimensions {
							return widget.Border{
								Color:        ColorMuted(),
								Width:        unit.Dp(1),
								CornerRadius: unit.Dp(4),
							}.Layout(gtx, func(gtx layout.Context) layout.Dimensions {
								return layout.UniformInset(unit.Dp(8)).Layout(gtx,
									func(gtx layout.Context) layout.Dimensions {
										gtx.Constraints.Min.X = gtx.Constraints.Max.X
										return material.Body1(th, wz.folder).Layout(gtx)
									})
							})
						}),
						layout.Rigid(layout.Spacer{Width: unit.Dp(8)}.Layout),
						layout.Rigid(func(gtx layout.Context) layout.Dimensions {
							return material.Button(th, &wz.browseBtn, "Browse...").Layout(gtx)
						}),
					)
				})
		}),
	)
}

func layoutCertificateStep(gtx layout.Context, th *material.Theme, wz *wizardState) layout.Dimensions {
	body := "This release is signed by Centroid's own certificate, and Windows refuses to " +
		"install the package until this machine trusts it — that is the 0x800B0109 error. " +
		"Press Install and approve the Windows prompt that follows; it is asked once, and " +
		"later updates will not ask again."
	if wz.trustKnown && wz.trusted {
		body = "The certificate is already trusted on this machine. Press Install to continue."
	}

	return layout.Flex{Axis: layout.Vertical}.Layout(gtx,
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			lbl := material.Body2(th, body)
			lbl.Color = ColorMuted()
			return lbl.Layout(gtx)
		}),
		layout.Rigid(layout.Spacer{Height: unit.Dp(12)}.Layout),
		layout.Rigid(func(gtx layout.Context) layout.Dimensions {
			if wz.trustStatus == "" {
				return layout.Dimensions{}
			}
			lbl := material.Caption(th, wz.trustStatus)
			if wz.trusted {
				lbl.Color = ColorSuccess()
			} else {
				lbl.Color = ColorError()
			}
			return lbl.Layout(gtx)
		}),
	)
}

// startInstall runs the install the wizard was configuring, managed or
// portable, and hands the UI back to the picker's own progress display.
func startInstall(state *pickerState, eng *update.Engine, installer PickerInstaller, w *app.Window) {
	wz := &state.wizard
	kind := wz.kind
	folder := wz.folder
	version := state.selectedVersion()
	wz.close()

	state.installing = true
	state.err = nil
	state.statusMsg = fmt.Sprintf("Installing %s...", displayVersion(version))
	go func() {
		var err error
		if kind == kindPortable {
			err = eng.InstallPortable(context.Background(), version, state.channel, folder,
				func(dl, total int64) {
					if total > 0 {
						next := float32(dl) / float32(total)
						if next-state.progress >= 0.005 || next >= 1 {
							state.progress = next
							w.Invalidate()
						}
					}
				})
		} else {
			err = eng.Update(context.Background(), update.UpdateOptions{
				Version: version,
				Channel: state.channel,
				DestDir: os.TempDir(),
				OnProgress: func(dl, total int64) {
					if total > 0 {
						next := float32(dl) / float32(total)
						if next-state.progress >= 0.005 || next >= 1 {
							state.progress = next
							w.Invalidate()
						}
					}
				},
			})
		}
		if err != nil {
			state.err = err
			state.statusMsg = userFriendlyMessage(err)
		} else if kind == kindPortable {
			state.statusMsg = "CentroidX " + displayVersion(version) + " unpacked into " + folder
		} else {
			state.statusMsg = fmt.Sprintf("CentroidX %s installed!", displayVersion(version))
		}
		// Whatever happened, say what is actually on the machine now.
		state.isInstalled = installer.IsInstalled()
		state.installedVersion = installer.InstalledVersion()
		state.installing = false
		w.Invalidate()
	}()
}
