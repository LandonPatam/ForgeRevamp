# Windows acceptance of the Mac reconciliation

Reviewed on Windows on November 4, 2026, starting from Mac branch commit `015c08d`.
Runtime game/bridge source is unchanged by this Windows acceptance pass. The
Windows additions fix test portability and record verification; Mac launchers,
universal packaging, runtime discovery and export preset remain alongside the
Windows equivalents.

## Windows verification

- Godot 4.7.2 import: passed without script errors.
- Offline Maven bridge build and direct `forgeui.bridge.BridgeChecks` harness:
  445 regression checks passed. Forge emits Oracle-text warnings for synthetic
  test cards; capture native stderr without PowerShell converting them to errors.
- `node bridge/tools/client-checks.mjs`: 12 checks passed.
- `node bridge/tools/online-check.mjs`: 73 real local lobby, seat, privacy,
  readiness, opening-hand, reconnect, leave and host-stop checks passed.
- `node bridge/tools/online-turn-check.mjs --four`: 8 checks passed.
- `node bridge/tools/solo-phase-check.mjs`: both bots paused at M1/M2 across
  repeated turns; declaration stops were also observed. Final runner exits cleanly.
- Extended source `--smoke` (3600-frame limit): passed without script errors
  after correcting the headless-only containment expectation described below.
- `node client-godot/tools/app-check.mjs --render`: full navigation, online
  join/recovery, settings, saved/generated decks, two/three/four-seat games,
  park/resume, end/format and quit ownership checks passed.
- `node client-godot/tools/library-check.mjs --render`: passed catalog,
  printing/artwork, import/export, quantities, metadata and conflict guards.
- `node client-godot/tools/ui-scale-check.mjs`: passed 2x settings, portrait/server
  input, editor/artwork/import dialogs, real match, park/resume and end cleanup;
  final runner exits cleanly after the Java executable fix below.
- Rendered `--visual-checks`: passed at both sizes, including automatic/moved
  piles, tap/untap, hover, combat and decisions. Rendered `--hand-hover-check`
  passed 231 frames of slow/rapid sweeps, return, scrolling and selection.
- `package.ps1 -SkipBuild -NoZip -OutName ForgeUI-windows-reconciliation`:
  Windows export and exported smoke passed. Local output is
  `dist/ForgeUI-windows-reconciliation/ForgeUI.exe` (keep its whole folder).
- `node client-godot/tools/bundled-check.mjs dist/ForgeUI-windows-reconciliation/ForgeUI.exe`:
  passed bundled catalog, real Commander match, hidden hands and owned match/service
  cleanup from an unrelated working directory.
- Pinned Forge remains `84f4983`; its tracked patch passes reverse-application
  validation against the local dependency checkout. No upstream edits were made.

Library, opening-hand, starting-toss, small scaled settings and one-tapped-card
pile captures were inspected. Logs remain in `artifacts/windows-reconciliation/`;
captures remain in `client-godot/artifacts/`. Neither is committed.

## Test portability fixes

- Headless Godot reports a 64x64 root viewport even when smoke assigns the table
  its intended logical size. Starting-roll tests now use the logical table for
  headless containment; rendered tests still require the actual visible viewport.
- Windows can fit a window to odd pixel dimensions (observed 2485x1411).
  The 2x viewport correctly uses 1242x705 whole pixels. Scale checks now expect
  the floored half size rather than fractional viewport pixels.
- Windows PATH resolved Java through Oracle's launcher shim. Killing that shim
  left its actual JVM alive: the UI runner held inherited output pipes open, and
  the solo runner could leave a match behind. Both runners now resolve
  `java.home` and launch the actual Java executable, matching existing portable
  runners. Only identified JVMs owned by these runs were stopped; pre-existing
  match/editor processes were preserved.

Run local lobby suites serially: they share Forge's configured online port. The
first rendered application attempt overlapped the online suite and was discarded;
the application suite passed on its serial rerun.

## Remaining verification and user decision

The user explicitly chose physical Windows/Mac testing after the merge because an
additional in-game online issue needs investigation. Both host/join directions,
internet/router behavior and that issue remain unverified. Local online passes
do not establish those results. Keep the normal cross-platform online testing
requirement for subsequent fixes.

The Mac's pre-existing source smoke failures (attacker-scroll containment and hand
reordering) remain tracked in `mac-reconciliation.md`. Windows source smoke and
rendered checks passed; this pass does not claim to fix those Mac results.
Mac ad-hoc signing and lack of native Intel hardware verification are unchanged.
This reconciliation is not a fully green release or a published release artifact.
