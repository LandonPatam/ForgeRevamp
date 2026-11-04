# Home screen night lighting

Dark mode uses the existing `ComputerMenu.set_dark_mode` / `_apply_darkness` transition and saved preference. `LightSwitch.gd` remains its input/display control. No geometry, camera path, key timing, carousel motion, boot sequencing or monitor content was changed for this work. Light mode retains its original lights, original floor material and unshaded disk presentation.

## Final lighting

| Source | Light mode | Dark mode | Details |
| --- | ---: | ---: | --- |
| Ambient | 0.62 | 0.09 | Existing color interpolation: `#d7d9dc` to `#9aa9ad` |
| Directional key | 0.65 | 0.08 | Existing direction, no shadows |
| Omni fill | 0.35 | 0.015 | Existing position/range |
| CRT spill | 0 | 2.8 | `#72dfcf`; position `(0, 1.10, 1.655)`, range 4.0, attenuation 1.6; no shadows |
| Cool rear rim | 0 | 0.18 | `#879cbe`; rotation `(-38, 150, 0)`; no shadows |

The existing monitor light now supplies the main illumination, with real distance and surface-angle falloff over the bezel, lower front, keys and drive. One additional directional rim separates the upper/side silhouette. No shadow maps or Forward+ effects were added. Compatibility glow is not enabled; the CRT's existing unshaded presentation receives a restrained 10% emission contribution in dark mode, fading with `clean_view` during fullscreen transitions.

The existing floor mesh uses a night material only above zero darkness. It blends toward a `#111719` emissive base matching the environment, with lit albedo `(0.055, 0.070, 0.075)`, roughness 1 and specular 0. Its monitor-lit area receives the same real spill as the computer. The night floor excludes ambient/directional light so distant floor and background meet without a visible horizon during camera motion. At zero darkness, its original StandardMaterial3D is restored.

## Changes by file

- `scripts/app/ComputerWorld.gd`: night light balance, shadow-free rim, lit night floor, CRT emission and insertion-face material selection. All values follow the current darkness amount.
- `scripts/app/MenuAtmosphere.gdshader`: replaces the old flat teal bezel halo with a background-only radial night gradient and vignette. The gradient follows the projected CRT; surface matching preserves real object lighting. Night speckle/pigment contrast is reduced to 24%, with very quiet background grain. Existing room-scroll visibility and fade remain intact.
- `scripts/app/DiskNightLighting.gdshader` (new): 2D presentation shading for the carousel. Selected disk brightness is 90%, outer disks approach 52% before existing depth modulation; teal spill decays from the top, with a narrow cool rim. Strength follows fractional cursor distance rather than discrete selection.
- `scripts/app/DeckCartridge.gd` and `CarouselCopy.gd`: apply that shader to displayed faces/copies only. Unchanged uniform values are not resubmitted. Light mode removes the presentation material entirely. The cached face SubViewport, artwork pixels and shell color remain untouched.
- `scripts/app/DeckCarousel.gd`: supplies night strength and continuous center distance to visible disks, wrapped copies and transition ghosts.
- `scripts/app/ComputerMenu.gd`: fades carousel night shading out with the existing home-to-editor scroll, leaving the editor's previous appearance intact.
- `scripts/app/InsertionNightLighting.gdshader` (new): uses the original raw disk texture. Far from the computer it preserves a readable presentation; over the last 4 to 1 scene units of approach it blends into actual 3D illumination. Daylight uses the original unshaded face material.
- `tests/NightLightingChecks.gd` (new), `tests/ApplicationIntegration.gd`, `tools/app-check.mjs`: repeatable before/after captures, zero-state checks, interrupted toggle tests, shared-texture integrity checks, frame timing, and optional dark cinematic captures.

`LightSwitch.gd`, `MenuFrame.gd`, `FloppyDisk.gdshader` and the monitor UI content are unchanged. The separate presentation shader is intentional: baking night shading into `FloppyDisk.gdshader` would also change the texture used for color sampling and physical insertion.

## Verification and captures

Commands:

```powershell
node client-godot/tools/app-check.mjs --render --night-baseline
node client-godot/tools/app-check.mjs --render --night-review
node client-godot/tools/app-check.mjs --render --night-cinematics
node client-godot/tools/app-check.mjs --render --editor-preview --night-cinematics
```

The full real 2/3/4-player application regression and the dark editor-preview run passed. The final floor horizon correction also passed settings/editor captures and the lighting review. No Java was changed, so bridge checks were not rerun for this lighting-only task.

The baseline was captured before the lighting changes. Four interrupted light/dark cycles restore original energies/materials and zero night uniforms. Shared face texture identities and pixel bytes remain unchanged. No face viewport runs in `UPDATE_ALWAYS` for this effect.

Measured idle frame times on this workstation: daylight median 4.165 ms / p95 4.340 ms; night median 4.161 ms / p95 4.288 ms. This is no measurable practical frame-time regression in these captures; it is not a claim about every GPU.

Daylight before/after comparisons differ only at a handful of rasterized disk-edge pixels: 5 of 1,600,000 pixels at 1600x1000, 1 of 1,024,000 at 1280x800, and 1 of 1,536,000 at 1920x800. Maximum channel difference is 1/255. The computer, screen, background and controls retain their original daylight rendering. Detailed metrics: `client-godot/artifacts/night-lighting-pixel-comparison.json`.

| Size | Dark before | Dark after | Daylight before | Daylight after |
| --- | --- | --- | --- | --- |
| 1600x1000 | [Before](../client-godot/artifacts/night-before-dark-1600x1000.png) | [After](../client-godot/artifacts/night-after-dark-1600x1000.png) | [Before](../client-godot/artifacts/night-before-light-1600x1000.png) | [After](../client-godot/artifacts/night-after-light-1600x1000.png) |
| 1280x800 | [Before](../client-godot/artifacts/night-before-dark-1280x800.png) | [After](../client-godot/artifacts/night-after-dark-1280x800.png) | [Before](../client-godot/artifacts/night-before-light-1280x800.png) | [After](../client-godot/artifacts/night-after-light-1280x800.png) |
| 1920x800 | [Before](../client-godot/artifacts/night-before-dark-1920x800.png) | [After](../client-godot/artifacts/night-after-dark-1920x800.png) | [Before](../client-godot/artifacts/night-before-light-1920x800.png) | [After](../client-godot/artifacts/night-after-light-1920x800.png) |

Cinematic images use `night-app-*` names in the same artifacts directory: physical PLAY press, disk insertion, boot rules/READY, settings zoom, editor scroll and return. `night-deck-selected.png` captures carousel selection. These are generated review artifacts, not runtime assets.
