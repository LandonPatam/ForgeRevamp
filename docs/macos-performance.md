# macOS rendering optimization

This pass reduces redundant work without changing renderer, resolution, MSAA,
visual effects, animation timing, game rules or online protocol.

- Hidden scaled UI surfaces suspend their render targets. Settings and game
  zooms explicitly keep their borrowed CRT textures live until reveal finishes.
  Logic and networking retain their existing lifecycle.
- Hand/hover mirroring runs once immediately before drawing, rather than in both
  processing and drawing callbacks. Disabled viewports skip these frame callbacks.
- Stationary combat arrows retain their exact drawing until endpoints change.
  Moving cards and live targeting still update every frame when their geometry
  or pointer changes.

Historical measurements imported from the preserved Mac project on Apple M2 with Godot 4.7.2 GL Compatibility, uncapped
and isolated at 1600×1000:

| Arrow fixture | Before p95 | After p95 | Before geometry CPU/frame | After when stationary |
| --- | ---: | ---: | ---: | ---: |
| 8 stationary arrows | 1.77 ms | 1.39 ms | 153 µs | 0 µs |
| 32 stationary arrows | 3.33 ms | 1.85 ms | 604 µs | 0 µs |
| 32 moving arrows | 3.33 ms | 3.33 ms | 600 µs | 610 µs while moving |

The moving result is within measurement variation; it retains one redraw per
frame. The stationary before/after images are pixel-identical. These are arrow
microbenchmarks, not an overall-game FPS or battery-life claim. The idle full
battlefield benchmark did not show a reliable overall frame-time improvement;
measured hand/hover calls dropped from two to one per visible frame and from one
to zero per suspended frame. Full Retina resolution and animation rate remain.

The real UI suite exercises settings zoom, artwork input, match reveal, parking,
resume and cleanup. `ScaledSurfaceChecks.gd` also samples actual texture pixels
while hidden to verify that borrowed CRT frames update and suspended frames are
retained. Existing source smoke assertions about attacker-scroll containment and
hand reordering fail identically on the unchanged baseline and this build; full
source smoke success is not claimed. Real-engine combat checks retain exact
resulting-state assertions.

Profiling logs, reference images and task-specific source backups are under
`artifacts/mac-*` and `client-godot/artifacts/mac-*` in this checkout. Those historical build paths belong to the preserved Mac project, not this shared clone.
See `docs/mac-reconciliation.md` for checks of the consolidated source.
