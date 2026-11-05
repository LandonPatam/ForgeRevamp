# Session notes - 2026-11-04

## Current state

- Shared `main` incorporates UI-scale implementation `e3cda90` from `fix/display-ui-scale`. Automatic = 100% Windows / 200% Mac, with manual 100/125/150/175/200% in Settings > UI SIZE. Save & Return persists `user://display.cfg`; Cancel leaves it unchanged. Display choice is separate from match/lobby configuration.
- At 100%, original Windows header/carousel proportions are restored. Editor, settings, game and confirmations use the selected scale; workspace/input conversion follows it. ScaledSurface explicitly fits root content on native/fractional resize, avoiding stale offsets and clipped dialogs. Physical computer/CRT dimensions and engine/adapter ownership are preserved.
- Windows checks passed: full UI integration at 100% and 200% (including real match, settings/artwork input, park/resume, parked-adapter continuity and end cleanup), saved 150% preference/reopen, 150% artwork input at two sizes, all five scale geometries/textures, and rendered home/editor/online-join preview. Captures inspected. No Java changes/checks needed.
- User reported Mac tests passed on November 4 for the pushed UI-scale branch; fetch confirmed no additional code commits beyond `e3cda90`. Accepted for merge with existing Windows results. Exact Mac commands/results were not supplied. Separate Windows package: `dist/ForgeUI-ui-scale/ForgeUI.exe` (keep the whole folder); export/smoke passed and its receipt records `e3cda90`. Acceptance update is documentation-only.

## Known issues

- User will personally test live Windows/Mac play and describe another in-game online issue; it is not yet fixed. Prior reconciliation records and Mac source-smoke exceptions remain in `docs/mac-reconciliation.md` and `docs/windows-reconciliation.md`.
- Run local lobby suites serially and launch the actual JVM rather than the Windows PATH shim. Preserve existing processes and the original Mac checkout/backup.

## Next steps

- Both machines should update clean checkouts to current `main`. Existing UI-scale builds at `e3cda90` have the same runtime code as the acceptance update.
- Investigate the user's separate online issue on a new feature/fix branch once described; test both host/join directions. Continue Windows implement/test/push, Mac pull/rebuild/test, Windows recheck, then merge.
