# Device-local UI size

Windows and Mac use the same controls and layout code. Scaling is a local display
preference, not a separate game version or online setting.

Open the physical Settings key, find **UI SIZE**, choose a size, then **Save & Return**.
Automatic starts at 100% on Windows and 200% on Mac. Either platform can choose
100%, 125%, 150%, 175% or 200%; the choice is saved on that device in
`user://display.cfg`. Cancel leaves the previous choice intact. A Mac connected
to a larger monitor can choose a smaller size without changing the Windows build.

At 100%, home header/carousel dimensions retain the original Windows proportions.
Larger sizes use the same code to increase them. Editor, settings, game and
confirmation surfaces retain native-resolution rendering while using a logical
viewport divided by the selected scale. Input conversion stays with Godot, and
logical viewport sizes round down to whole pixels for odd native window sizes.
The surface explicitly fits its root control to the logical viewport on resize;
descendant Controls retain normal layout. This prevents stale anchor offsets from
shrinking dialogs after switching window dimensions or fractional scales.
The physical computer, CRT projection, cameras and drive dimensions are unchanged.

Save applies sizing after returning home, updating existing editor and parked-game
surfaces without replacing their scenes, adapters or engines. Display preferences
are stored separately from match settings and never enter lobby configuration.
Changing only UI size therefore does not invalidate online readiness.

`--ui-scale=1`, `--ui-scale=1.5` and `--ui-scale=2` provide temporary diagnostic
overrides. They do not change the saved choice and take precedence while present.
Integration runners isolate saved preferences in their disposable library fixture.

## Verification and Mac handoff

Run `node client-godot/tools/ui-scale-check.mjs` for the platform default and
save/reopen of a 150% preference; explicit overrides skip the preference-changing
part. Run `node client-godot/tools/ui-scale-check.mjs --ui-scale=2` for 200%, and
add `--ui-scale=1.5 --artwork-only` for fractional input/printing-gallery coverage.
The shared surface checks cover every supported factor at odd window dimensions
and preserve visible render textures across live scale changes.

Mac must pull the pushed feature branch and verify its 13-inch display at Automatic,
intermediate sizes and 100%, including settings, home/header/carousel, editor
dialogs/artwork, opening hands, gameplay and park/resume. Check saving, canceling,
restarting, and any external monitor. Preserve Mac packaging/runtime support.
Merge only after Mac validation; Windows rendering at 200% does not establish
physical Mac/Retina results.

Windows verification on November 4, 2026 passed the full integration at 100% and
200%, the 150% artwork flow at both window sizes, every supported factor's root
geometry/render texture, persistence/reopen of a 150% choice and scaling a parked
table without replacing its engine/adapter. Rendered home/editor navigation also
passed, including search, online join/recovery, read-only precons, retained drafts
and light/dark layout. Captures were inspected. Logs are local under
`artifacts/windows-reconciliation/scale-*`; source changes are frontend-only.
