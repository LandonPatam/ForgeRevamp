# Mac reconciliation against Windows 434c14b

Branch: `chore/mac-reconciliation`. Merge only after affected Windows checks pass.

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

Mac verification is in progress. Final results are recorded below before handoff.
