# Session notes - 2026-11-08 (evening)

## Current state

- `main` (`ad3d352`) merges `feature/hand-discard-pick` (34 commits + Mac fixture fix `9ba4082`), validated with `check.mjs all` on Windows and macOS. Includes the UI sandbox (`tools/sandbox.mjs`), tethers (decisions hanging off their card; guide in `docs/tethers.md`), the trigger stack builder, wipe/targeted table views that wait for the affected seat, Counterspell-style response tethers, scry with only the looked-at cards (fixed a hidden-card name leak), library carousel (source card beside it, line to its origin), CAN'T BLOCK / CAN'T ATTACK tags with plain reasons, red damage badge, X values, opponent choice/reveal notices.
- Forge carries a second local patch, `forge-patches/phase-scan.patch` (skip the actionable scan in skipped phases, solo only); recorded in `FORGE_PATCHES.md`. Every machine must apply it and rebuild `forge-gui`, then the bridge.
- `blocking` (bridge empty-stack NPE) and `insights` (harness coin-toss race) are fixed; all 56 scenarios pass.

## Known issues

- Red damage badge can sit under the phase strip on opponents' rows.
- A target tether applies to triggers/abilities from permanents or your zones; targets for a spell cast from hand still use the rail.
- Library search window can still cover its source when there is no room to slide (no line then).
- VS Code's Java extension writes into `bridge/target/classes`; Maven can then report PASS on code that does not compile. After bridge edits, compile with the direct `javac` in `docs/testing.md`.
- Not yet verified: live cross-platform online play with the new hold/notice behavior; packaged builds (`package.ps1` / `package-macos.py`) since these changes.

## Next steps

- Both machines: `git pull --ff-only`, apply `phase-scan.patch` if not already, rebuild Forge and the bridge, then repackage before sharing builds.
- Play online Windows-host/Mac-join and the reverse; watch for held priority on opponent wipes/targets and the reveal/choice notices.
- Possible follow-ups: explain other refused actions (targets, casts) like combat; move the opponent-row damage badge clear of the phase strip.
