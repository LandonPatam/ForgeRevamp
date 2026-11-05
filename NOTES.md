# Session notes - 2026-11-04

## Current state

- `fix/display-ui-scale` starts from consolidated main `43a4257`. One shared UI now has a device-local size: Automatic = 100% Windows / 200% Mac, with manual 100/125/150/175/200% in Settings > UI SIZE. Save & Return persists `user://display.cfg`; Cancel leaves it unchanged. Display choice is separate from match/lobby configuration.
- At 100%, original Windows header/carousel proportions are restored. Editor, settings, game and confirmations use the selected scale; workspace/input conversion follows it. ScaledSurface explicitly fits root content on native/fractional resize, avoiding stale offsets and clipped dialogs. Physical computer/CRT dimensions and engine/adapter ownership are preserved.
- Windows checks passed: full UI integration at 100% and 200% (including real match, settings/artwork input, park/resume, parked-adapter continuity and end cleanup), saved 150% preference/reopen, 150% artwork input at two sizes, all five scale geometries/textures, and rendered home/editor/online-join preview. Captures inspected. No Java changes/checks needed.
- Separate Windows package: `dist/ForgeUI-ui-scale/ForgeUI.exe` (keep the whole folder). Export/smoke checked; its build receipt records the feature revision. Source and Windows/Mac workflow guidance are in AGENTS.md and `docs/display-scaling.md`. Feature remains unmerged pending Mac validation.

## Known issues

- Physical Mac/Retina validation of configurable scaling is pending. Rendering 200% on Windows does not establish the 13-inch Mac result. Main still has the prior unconditional 2x UI until the scale branch is accepted and merged.
- User will personally test live Windows/Mac play and describe another in-game online issue; it is not yet fixed. Prior reconciliation records and Mac source-smoke exceptions remain in `docs/mac-reconciliation.md` and `docs/windows-reconciliation.md`.
- Run local lobby suites serially and launch the actual JVM rather than the Windows PATH shim. Preserve existing processes and the original Mac checkout/backup.

## Next steps

- Mac pulls `fix/display-ui-scale` at the Windows handoff commit, rebuilds and tests Automatic, 100%, intermediate sizes, resize, save/cancel/restart and parked-game resume on the 13-inch display (and external monitor if available). Use `node client-godot/tools/ui-scale-check.mjs` and the fractional artwork command in `docs/display-scaling.md`.
- Mac pushes compatibility fixes during its coordinated turn; Windows pulls/rechecks. Merge after both platforms pass. Then investigate the separate online issue on a new branch; test both host/join directions.
