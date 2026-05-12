# PR Handover — elevator → main (2026-05-12)

**Branch:** `elevator`
**Base:** `main` (at `d5a8d5d merge: plan 04-05 read-only details dialog`)
**Commits ahead:** 127
**Working tree (at handover):** clean except for the 3 uncommitted/untracked items below — these are stale from session start and not part of this PR.

```
 M .planning/config.json          # uncommitted — gsd-sdk side-effect, can be reverted or committed separately
?? .planning.bak/                 # leftover backup directory, can be deleted
?? packages/tfc_dart/test/core/state_man_test.dart   # untracked, not authored this session
```

---

## What's in this PR

The session combined Phase 5 retrofit work with a long tail of visual-quality, regression, and architecture fixes. Suggested PR title:

> **feat(stb): Advantys STB I/O family + page-editor rotation/drag fixes + multi-asset polish**

### Scope by area

1. **Phase 5 — AdvantysSTBStack composite head (retrofit).**
   The phase originally introduced a standalone `AdvantysSTBStackConfig` wrapper, then mid-flight the user requested a refactor to put the composite behaviour directly on `STBNIP2311Config` (matching the Beckhoff CX5010/EK1100 precedent — the head device IS the parent, no separate stack frame). All STACK-01..05 + QUAL-06,07 requirements implemented and signed off via `.planning/phases/05-.../05-VERIFICATION.md` (status `passed`, user signed off the no-delete-confirmation CX5010 parity choice).

2. **STB painter visual quality.** Multiple passes against user feedback:
   - Real-hardware aspect ratios (NIP 0.303, DDI/DDO 0.219, PDT 0.18)
   - Subtle chamfer corners with shared `kStbCornerRadiusFraction`
   - Outline-INSIDE-fill structural fix (no more cream bleeding past the border)
   - Uniform border width + darker `stbBodyBorderColor` for visibility
   - DDI/DDO LED block: dark inset panel, RDY same-sized as channel LEDs at top-left of unified 2×9 grid, channels 1-16 squared LEDs with numeric labels
   - DDI/DDO A/B terminal plug bodies with 18 stacked wire-entry ports + spring clips
   - PDT3100 redesign from real-hardware reference photo: cream body with model number on top, dark IN/OUT viewport with two NIP-style LEDs (RUN/PWR scale), white-block+grey-block composite plug terminals with internal +/− markings, DC label + dashed line, blue accent strips
   - Removed vendor chrome (no `Schneider Electric`, no `24 VDC`, no decorative arrow on DDO)
   - Auto-shrinking title/label fonts so text fits at any aspect

3. **Page editor — selection rotation chain.**
   - Selection chrome and overlay GestureDetector now rotate with the asset's angle (`lib/pages/page_view.dart`)
   - Marquee gate (`page_editor.dart`) hit-tests in the asset's rotated local frame
   - Pan deltas projected back to canvas frame so rotated assets drag in the screen-direction the operator moves the mouse
   - Container-decoration hit-opacity regression fixed (was swallowing runtime taps on selected assets)

4. **Conveyor simulation toggle — two fixes.**
   - `8531b98` lifted the `simulateBatches` start/stop block out of `StreamBuilder.builder` so the toggle works with no PLC keys configured.
   - `58467d4` gated `_updateBatches` on `!simulateBatches` so a configured preview-key stream doesn't wipe the simulator's batches.

5. **Sensor label.** Sensor painter now reserves a bottom band for the label and renders at the operator-expected font size (revert of an earlier over-shrink).

6. **Arrow asset.** Label now routes via `BaseAsset.text` (uniform overlay path), icon scales with parent size, `@ColorConverter() Color color` field added to `ArrowConfig` with codegen + configure-dialog wiring + JSON back-compat.

7. **TextPos.inside.** `_labelOffset` switch had a fall-through that put `inside` labels at the right edge of the asset. Fixed + 6 unit tests.

8. **Version manager subsystem deleted.** `packages/centroidx_upgrader/`, `tools/centroidx-manager/`, `centroid-hmi/lib/pages/version_manager_page.dart`, 3 pub deps, `build-manager.yml` CI workflow, `CLAUDE.md` references — all removed at user request.

### Memory / process artifacts created

- `~/.claude/projects/.../memory/feedback_composite_head_pattern.md` — codifies that head devices ARE their own composites (no wrapper assets).
- `~/.claude/projects/.../memory/feedback_golden_quality_gap.md` — codifies "pixel-match ≠ quality; always read regenerated PNGs against a checklist".
- `.planning/phases/05-.../05-VISUAL-QUALITY-CHECKLIST.md` — 6-item per-PNG checklist for golden regens.

---

## Pre-PR steps (next session)

Execute in order. None should require user interaction unless flagged.

```bash
# 1. Confirm clean tree (these 3 are pre-existing — not part of the PR).
git status --short

# 2. Decide what to do with the 3 leftover items. Suggested:
git checkout -- .planning/config.json        # discard SDK side-effect
rm -rf .planning.bak/                        # leftover backup
# packages/tfc_dart/test/core/state_man_test.dart — inspect; commit separately or delete

# 3. Sanity check the suite locally before relying on CI.
flutter test test/page_creator/              # expect 599 passing
flutter analyze lib/page_creator/ lib/painter/ lib/pages/
cd centroid-hmi && flutter analyze && cd ..

# 4. Confirm no large/sensitive files in the diff (sanity).
git diff --stat main..HEAD | tail -5
```

### Optional but valuable

```bash
# Visually inspect the key STB goldens one more time before opening the PR.
# (run from project root; paths are absolute so any image viewer works)
for f in test/page_creator/assets/goldens/advantys_stb/*.png; do echo "$f"; done
```

---

## Creating the PR

```bash
# Push the branch (first push of elevator):
git push -u origin elevator

# Open the PR using gh. The body uses HEREDOC to preserve formatting.
gh pr create --base main --head elevator --title "feat(stb): Advantys STB I/O family + page-editor rotation/drag fixes + multi-asset polish" --body "$(cat <<'EOF'
## Summary

127 commits combining Phase 5 (AdvantysSTBStack composite head — retrofitted onto STBNIP2311Config to match the Beckhoff CX5010/EK1100 precedent), the four Advantys STB I/O painters (NIP2311/PDT3100/DDI3725/DDO3705) with real-hardware-photo-driven visuals, a page-editor selection-rotation chain (chrome + gesture detector + marquee + drag direction), two conveyor simulation-toggle regressions, an Arrow asset overhaul (label + scaling + declarable color), a label-position fix (`TextPos.inside` no longer falls through to right), and removal of the unused version-manager subsystem.

## Scope

- **Phase 5 — AdvantysSTBStack composite head** (architectural retrofit: composite behavior moved from a separate Stack class onto STBNIP2311Config; mirrors CX5010/EK1100 pattern). User-signed-off CX5010-parity deviations recorded in 05-VERIFICATION.md.
- **STB painter quality**: real-hardware aspect ratios; outline-inside-fill (no cream bleed); uniform borders; DDI/DDO LED block redesign (dark panel, RDY at top-left of 2×9 grid, 16 numbered squared LEDs); A/B terminal plugs (18 ports each + spring clips); PDT3100 redesign from reference photo (model number on cream, dark viewport with two NIP-style LEDs, composite white+grey plug terminals, DC label + dashed line, blue accent strips); vendor chrome removed.
- **Page editor**: selection chrome rotates with angle; overlay GestureDetector hit-area follows rotated visual; marquee gate respects rotation; drag delta projected back to canvas frame; runtime tap-through regression fixed.
- **Conveyor sim toggle**: works with no PLC keys (#1) and with a preview-key stream (#2).
- **Arrow asset**: label visibility + icon scaling + declarable `Color color` (codegen + dialog).
- **TextPos.inside**: actually centres labels on the asset.
- **Version manager removed**: \`packages/centroidx_upgrader/\`, \`tools/centroidx-manager/\`, related page, deps, CI workflow.

## Test plan

- [ ] Local: \`flutter test test/page_creator/\` → 599 passing
- [ ] Local: \`flutter analyze lib/page_creator/ lib/painter/ lib/pages/\` → clean
- [ ] CI: \`Flutter Tests\` workflow green on Ubuntu/macOS/Windows matrix
- [ ] CI: \`macOS Build\` workflow green
- [ ] CI: \`Windows MSIX Build\` workflow green
- [ ] CI: \`Build and Push centroid-hmi Docker Image\` workflow green
- [ ] Open the page editor and drop a NIP2311, PDT3100, DDI3725, DDO3705 — visuals match real Schneider Advantys hardware
- [ ] Rotate a sensor 90° in the page editor — selection box rotates, drag-direction matches mouse direction, marquee starts when clicking adjacent canvas
- [ ] Place a button with TextPos.inside — label centres on the button, button drags cleanly
- [ ] Place an arrow — color picker works, label scales with asset size, icon scales with parent

## Notes

- Most STB goldens render text as Ahem-font black rectangles (Flutter test-env limitation). Production renders real fonts.
- Two known minor approximations in PDT3100 (model text legibility at small canvas, blue accent strip thickness vs photo) — non-blocking, can be tightened later.
- Open marquee follow-up: \`page_editor.dart\`-region hit-detection bug related to the rotation chain — flagged in session, NOT in this PR.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Capture the PR URL. The next steps assume it's `https://github.com/centroid-is/tfc-hmi2/pull/<N>`.

---

## CI follow-up

Watch all checks and address failures in order. The CI matrix from `.github/workflows/`:

| Workflow file | What it tests |
|---|---|
| `test.yml` | `Flutter Tests` — full test suite, runs on push and pull_request |
| `macos.yml` | macOS Build of `centroid-hmi` |
| `windows.yml` | Windows MSIX build |
| `centroid-hmi.yml` | Docker image build (Linux/elinux) |
| `centroid-hmi-ivi.yml` | Docker image build (ivi-homescreen variant) |
| `tag.yml` | NOT relevant for a PR — fires on tag push |

### Monitor

```bash
# Watch the PR's checks live.
gh pr checks --watch
```

If `--watch` isn't available or you want a one-shot snapshot:

```bash
gh pr view --json statusCheckRollup --jq '.statusCheckRollup[] | {name, status, conclusion, detailsUrl}'
```

### Triage by failure type

For each failing check, run:

```bash
gh run view <run-id> --log-failed | tail -200
```

(Find `<run-id>` from `gh pr checks` or the GitHub UI.)

**Likely failure classes and the right fix:**

1. **Flutter Tests** — if any test that wasn't run locally fails (e.g., a Windows-specific golden or a path-separator test), reproduce locally, fix, push the fix as a new commit on `elevator`. Do not force-push; let the new commit go through CI.

2. **macOS / Windows builds** — if `centroid-hmi/pubspec.yaml` lockfile drift surfaces (`upgrader`/`centroidx_upgrader` removal is the most likely culprit), regenerate locally:
   ```bash
   cd centroid-hmi && flutter pub get && cd ..
   git add centroid-hmi/pubspec.lock && git commit -m "chore: refresh centroid-hmi pubspec.lock after version-manager removal"
   git push
   ```

3. **Docker image builds** — usually slow but stable; check the build log for any `pdfrx`/`libpdfium`/`open62541` native-library issues. If a native compile fails, that's a separate bug — flag in the PR comments and fix on a follow-up branch rather than blocking the PR.

4. **Codegen drift** — if `*.g.dart` files differ between the PR and CI, regen locally and commit:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   git add lib/ packages/ centroid-hmi/lib/
   git commit -m "chore: regenerate codegen"
   git push
   ```

5. **Stale .planning artifacts** — if CI complains about `.planning/STATE.md` or `.planning/ROADMAP.md` mismatch with anything checked in `tests/`, this is a planning side-effect. Inspect; either commit the regeneration or revert it.

### What NOT to do

- **Do NOT force-push to `elevator`** — the PR commit history is a meaningful audit trail of the session's iterations. Fix forward with new commits.
- **Do NOT amend signed commits** to add CI-fix changes — keep them as new commits.
- **Do NOT merge until all required checks are green.** If a required check is broken by something unrelated to this PR (e.g., a flaky test on macOS), surface it in the PR comments and ask the user before bypassing.

---

## Open items NOT in this PR (defer / future work)

1. **Marquee-gate hit-detection sibling bug** (`page_editor.dart`-region): the rotation agent flagged a related but separate bug where pointer-down at a position that geometrically hits the rotated visual but lies outside the unrotated AABB doesn't trigger the marquee gate's "did we hit an asset?" check. Same root cause shape as the rotation chain but in a different code path. Sketch of fix: apply `marqueeHitTestRotatedAsset` consistently to the pre-marquee pointer-down resolution.
2. **PDT3100 model-text legibility** at very small canvas sizes — auto-shrink lands at sub-pixel sizes. Tweak the min-font clamp.
3. **PDT3100 blue accent strip thickness** — currently 3% body height, visually thinner than the reference photo suggests. Bump to ~4-5%.
4. **NIP2311 DXF is corrupted** at `.planning/research/dxf/NIP2311_mcadid0005722.dxf` (renders as a building, not the head module). Replace with a clean Schneider source DXF when one is available.
5. **Selection-box gesture audit** — the rotation fix exposed an implicit-coordinate-system trap. There are probably more lurking in resize handles, snap-to-grid, multi-select drag, alt-key modifiers. Worth a focused audit pass.
6. **`feedback_golden_quality_gap.md` enforcement** — codified as a memory note but not yet enforced as a CI gate. Could be a lint or a pre-commit hook that fails if `--update-goldens` runs without a co-located visual-inspection commit message.

---

## Quick-reference: where to find things

| Topic | Path |
|---|---|
| Phase 5 verification (signed off) | `.planning/phases/05-advantysstbstack-composite-parent/05-VERIFICATION.md` |
| Phase 5 retrofit doc | `.planning/phases/05-advantysstbstack-composite-parent/05-RETROFIT.md` |
| Visual quality checklist | `.planning/phases/05-advantysstbstack-composite-parent/05-VISUAL-QUALITY-CHECKLIST.md` |
| STB painters | `lib/painter/advantys_stb/` |
| Page editor (rotation + marquee) | `lib/pages/page_editor.dart`, `lib/pages/page_view.dart` |
| Conveyor sim toggle | `lib/page_creator/assets/conveyor.dart`, `test/page_creator/assets/conveyor_simulate_batches_test.dart` |
| Arrow asset | `lib/page_creator/assets/arrow.dart`, `test/page_creator/assets/arrow_test.dart` |
| Selection rotation tests | `test/page_creator/selection_rotation_test.dart`, `test/page_creator/marquee_hit_test_test.dart` |
| TextPos.inside test | `test/page_creator/label_offset_test.dart` |
