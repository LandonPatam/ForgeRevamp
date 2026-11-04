# Molded floppy recess and insertion alignment

The drive is one continuous horizontal slot. The former right-hand eject cap, pocket and excess slot length are removed. The fitted slot is centered between the SETTINGS well's right edge and the flat fascia's right edge. Its feed axis, backing, flap and hinge translate together, retaining equal small disk clearance, width, height and depth. The screen, camera and PLAY/SETTINGS wells are unchanged. The activity dot is aligned vertically with the slot in its right-hand margin.

Originally four inset contours formed one long, shallow sloped recess. At the home camera angle the upper slope was nearly edge-on while the lower slope looked broad. The right pocket contained a small dark eject bar and catch, backed by a flat black box. PLAY/SETTINGS instead used rounded contours, a short chamfer, dark vertical walls, a contact-gradient seam and separate molded caps.

## Geometry and material values

All dimensions below are scene units.

| Item | Value |
| --- | --- |
| Locked drive center/feed axis | `(0.5975, -0.39, 0.83)`, world Z |
| Locked front plane | `z = 0.88` |
| Locked front slot | `x = 0.0675..1.1275`, `y = -0.46..-0.32`; width 1.06, centered in the available fascia space |
| Throat cross-section | `x = 0.1035..1.0915`, `y = -0.424..-0.356`; reference plane `z = 0.715`; `0.034` side clearance around the 0.92-wide face |
| Main bevel | `44.9848°` from the fascia plane; depth `0.0335` |
| Main outer/inner edge rolls | `0.010 / 0.004`, three segments each, analytic smooth normals |
| Outline corner rounding | `0.008`, two quadratic segments per corner; intersected offset edges form consistent miters |
| Straight wall | starts at `z = 0.8465`, continues behind the flap to `z = 0.670` |
| Flap | front `z = 0.792`; visible wall depth before flap `0.0545`; top hinge groove at `y = -0.368` |
| Recess shading | vertex tone `1.0` at fascia to `0.48` at inner edge and `0.23` deep inside; restrained lower-wall darkening |
| Materials | existing matte case plastic (`roughness 0.84`); darker flap `#3b4346`, roughness `0.73`; no new texture assets, lights, SSAO or mode-specific geometry |

`_beveled_recess` solves the constant straight draft between two circular edge rolls while preserving the chosen outline/inset. Shared analytic normals keep the rolls smooth without rounding the flat fascia itself. Flat corner shoulders meet the opening boundary exactly. The continuous recess uses 576 vertices. Its full-width flap and hinge line follow the new uninterrupted opening; the pinhole/activity dot sits at `(1.335, -0.39, 0.884)`, aligned with the slot centerline.

## Disk orientation and flap clearance

The original final orientation was already mechanically square to the opening: the shutter points along world forward, the label faces up, and the disk's width follows the slot. The old recess shading and rotation continuing until the last approach frame made the angle harder to read.

The disk now completes lift/rotation in `0.70s` while still clear of the fascia, then travels straight on the drive axis for the remaining `0.30s` approach. The existing `disk_entering` event still fires at `1.00s`; the subsequent `0.95s` slide, final position, scale and ejection timing remain unchanged. PLAY, resume and FORMAT all use this same helper and canonical rotation.

The flap hides conservatively while the shared physical disk crosses its depth range, then reappears after the disk clears it. This uses disk position/orientation/visibility, with no independent tween or timer. It covers insertion, ejection and reset, avoiding any panel/disk intersection or stale open state. FORMAT remains silent and consumes its session disk normally.

## Captures and checks

- `node client-godot/tools/drive-check.mjs --before` captured the original hardware before source edits.
- `node client-godot/tools/drive-check.mjs` captures home views and native crops in light/dark mode at 1280×800 and 1600×1000, then captures aligned/contact/seated stages for PLAY, resume and FORMAT at each setting. It checks locked coordinates, draft, unit normals, mesh size, early alignment, throat clearance and flap state during insertion/ejection.
- `artifacts/drive-before-after-review.png` compares the four before/after crops; `drive-insertion-review.png` shows aligned/seated frames for all three insertion paths. Full-size frames and individual crops use the `drive-` prefix in `client-godot/artifacts/`.
- The fixture changes viewport size only; it uses the normal home camera throughout.

Original beveled-drive verification: the drive fixture, `node client-godot/tools/app-check.mjs --render`, `node client-godot/tools/library-check.mjs --render`, the extended 3600-frame headless `--smoke`, and `client-godot/tools/run.ps1 -Capture` all passed. The before/after crops, home views and insertion frames were inspected in both modes and sizes. No Java files changed.

## Changed files

- `scripts/app/ComputerWorld.gd`: reusable rounded recess, straight walls/occlusion, full-width flap, removal of the stepped pocket/eject cap, shared canonical disk rotation and earlier alignment.
- `tests/DriveGeometryChecks.gd`: isolated procedural geometry/alignment/capture fixture.
- `tools/drive-check.mjs`: bounded native fixture runner; no Forge service or installed deck writes.
- `AGENTS.md`, `CLAUDE_HANDOFF.txt`, `docs/computer-menu.md`, this document: current construction, fixed coordinates and verification guidance.

Continuous-slot follow-up: the drive fixture passed; it checks removal of both eject nodes, original feed clearance, unchanged pinhole location, and PLAY/resume/FORMAT/ejection at both sizes and room modes.

`artifacts/drive-slot-review.png` compares the removed eject cap/pocket with the current continuous slot in both modes and sizes. The insertion review and individual drive captures now show the continuous slot.

Width correction: the right edge moved from `1.30` to `0.86`, centering the slot at the unchanged feed X of `0.33`. The left edge, slot height/depth, feed transform/timing and pinhole dot remain fixed. The backing, flap and hinge match the reduced width. The drive fixture now asserts equal small disk clearance on both sides.

Width-correction verification: the drive fixture passed PLAY/resume/FORMAT/ejection checks in light/dark mode at both sizes. `artifacts/drive-width-review.png` compares the oversized and fitted slots; the insertion review shows the fitted opening.

Centering follow-up: the complete drive and feed center shifted right by `0.2675`, from X `0.33` to `0.5975`. Margins to the SETTINGS well edge (`-0.34`) and flat fascia edge (`1.535`) are both `0.4075`. Width, bevels, vertical position, depth, timing and pinhole dot remain unchanged. The fixture asserts equal fascia margins and all insertion/ejection alignments.

Activity-dot alignment: X `1.335` and Z `0.884` stay fixed, while Y moves from `-0.445` to the slot centerline `-0.39`. Its material, size and activity behavior are unchanged.

Centering verification: the rendered application suite passed with the translated drive/feed. The final drive fixture passed after aligning the activity dot, checking equal fascia margins, disk clearance and PLAY/resume/FORMAT/ejection in both modes and sizes. `artifacts/drive-centered-review.png` shows before/after centering and inline-dot placement.
