# Mac reconciliation against Windows 434c14b

Branch: `chore/mac-reconciliation`. Merge only after affected Windows checks pass.

Windows acceptance is recorded in [windows-reconciliation.md](windows-reconciliation.md).
The user chose live Windows/Mac play after the reconciliation merge; those
physical tests remain pending, along with the reported in-game online issue.
The Mac verification below is retained as the original record.

## Preservation

The old Mac project remains at `/Users/landonpatam/ForgeUI/ForgeUI`.
A complete archive, including untracked source, local Forge edits, tools and builds,
is stored beside it at `../mac-backups/ForgeUI-pre-reconciliation-20261104.tar.gz`
with a SHA-256 sidecar. The new sibling clone is `../ForgeRevamp`.
Neither Git history nor user decks, caches, credentials, build outputs or sessions
were imported into tracked source. Local tools/dependencies were copied for testing.

## Comparison decisions

- Imported Mac universal packaging, bundled Java discovery, macOS export preset,
  ASTC imports, rendered/online/bundled test tools and their resource UIDs.
  The Windows preset and PowerShell launchers remain intact; Bash dispatches to
  a native Python launcher on macOS and keeps its existing Windows path otherwise.
- Imported native 2x editor/table/settings/modal surfaces, Retina home sizing,
  physical key input ordering, editor modal/artwork mouse fixes, hidden viewport
  suspension, shared hand-face textures, retained combat arrows, stable LED shaders,
  layout-loop recovery and optional diagnostics (off by default).
- Imported accepted-deck/configuration validation before lobby replacement and
  expanded four-seat/CRLF/UTF-8/readiness coverage. No wire protocol change.
- Reconciled remote-seat persistence and normalized die engine IDs, adding the Mac
  integration checks without discarding Windows' existing protocol protections.
- Added a short-viewport opening-hand layout after rendered verification exposed
  overlapping cards/decisions at 2x. Full-size layouts retain their original sizing.
  The focused opening-hand suite passes at 800x500 and 640x400 logical sizes.
- Retained Windows' newer downward pile-tap offset in both automatic/manual piles,
  its regression checks, stable solo phase-stop implementation and broader Java tests.
  The older Mac sideways nudge and alternate implementations of equivalent solo
  stop checks were deliberately not imported. Existing shared UIDs take precedence.
- Both Forge copies pin `84f4983c1ce872932cf9a26a8bd54ca00056aae9`.
  All 15 changed upstream files match the existing tracked netplay patch; reverse
  application validates. No additional Mac-only Forge patch was found. The Mac ZIP
  lost empty `.git/refs`; only the copied dependency's metadata directory was repaired
  to permit inspection. The original dependency was not changed.
- Kept the Windows shared workflow, accurate README setup and reconnect rules;
  imported only current Mac documentation rather than stale handoff instructions.
  All tracked source differences and Mac-only scripts/tests/docs were reviewed;
  generated `.export-templates`, Python bytecode, build and diagnostic artifacts stay local.

## Verification

Verified on Apple M2 / macOS 26.3.1 / Godot 4.7.2 / JDK 17.
Implementation commits: `23380b5` (Mac reconciliation) and `f4fae0e`
(short opening-hand viewport layout and related checks). Final package source: clean `b6b61b4`. The final branch also incorporates the
documentation-only upstream commit `8f915d8`; runtime source is unchanged from
`b6b61b4`. Each package records its exact source commit and dirty state.

- Full Forge reactor and bridge Maven package: passed; Java regression harness:
  **445 checks passed** after rebuilding the pinned, patched Forge modules.
- Browser protocol/recovery: **12 checks passed**.
- Real source lobby/seats/privacy/reconnect/leave: **73 checks passed**.
- Four-seat online turn/combat: **8 checks passed**.
- Real solo phase runner: both bots paused at M1/M2 over repeated turns.
- Godot import: passed with no script errors.
- Retina UI integration: passed settings, portraits, online field, editor/artwork
  mouse input, import dialogs, real match, park/resume and end cleanup; captures
  of the table, small settings and editor were inspected.
- Full rendered application integration after the short-viewport fix: passed
  navigation, settings/profiles, saved/generated decks, two/three/four-player
  Commander, retained drafts, session ownership, park/resume, end and quit cleanup.
  The corrected opening-hand capture was inspected: cards and all three decisions
  are visible without overlap.
- Focused opening-hand suite: passed short viewport geometry, hover, decision and
  bottom-selection/hidden-hand guards.
- Library integration: passed catalog, printing selection, import/export, undo/redo,
  quantities, metadata and conflict guards.
- Packaged Intel JVM under Rosetta: **73 online checks passed**.
- Final exported Intel Godot plus bundled Intel JVM under Rosetta: real-match startup,
  hidden information and owned-process cleanup passed.
- Universal export, signature, DMG checksum verification, release smoke and bundled
  Apple Silicon real-match startup/cleanup: passed. Release exports disable GDScript assertions; this is
  separate from the source assertion failures below.

The final local artifact is `dist/ForgeUI-mac-reconciliation-final-universal.dmg`
(601.6 MiB), SHA-256
`27e846c907945b5a24b2655763c67d9c141378bc975f2fcba3d1c4cbc82ff979`.
Its app, source archive, build receipt and installation notes are in
`dist/ForgeUI-mac-reconciliation-final/`. The earlier candidate remains local.
Backup SHA-256: `510cc69ef805d596346666a89ec7b1d2157ec0336afd11f57fb97d1fed9ed6e8`
(archive integrity and checksum verified).

The source launcher passes Bash/Python syntax checks and native help dispatch.
Windows PowerShell scripts, Windows export preset, downward pile implementation
and its tests, and solo phase-stop Java implementation remain unchanged from
`434c14b`.

Local logs and captures are retained under `artifacts/mac-reconciliation/` and
`client-godot/artifacts/`. Build logs are under `dist/`.

## Remaining issues and Windows gate

- Source `bash client-godot/tools/run.sh -Check` correctly fails on two existing
  assertions: attacker controls inside the scroll viewport at 1280x800, and hand
  drag reordering. Both reproduce in an isolated copy of the preserved original
  Mac source. The attacker-scroll assertion also reproduces on untouched Windows
  `434c14b` on Mac; that baseline additionally halts on opponent-card size bounds.
  These failures have not been hidden or weakened. The preserved Mac's failing
  sideways moved-pile assertion is superseded by the retained Windows downward
  pile implementation/checks.
- Physical Mac-to-Windows play, external internet/router behavior and native Intel
  hardware still require verification. Rosetta checks do not establish those.
- Builds are ad-hoc signed; Developer ID/notarization remains separate.
- Windows must fetch this branch and run import, rendered app/library/UI scale,
  Java/browser/online/solo phase checks, downward pile capture checks, and its
  `package.ps1` export/launch. Review source smoke failures on Windows too.
- Do not merge `main` before the Windows checks pass; resolve or explicitly triage
  the source smoke issues before treating this as a fully green release.
