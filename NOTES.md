# Session notes - 2026-11-04

## Current state

- Windows baseline `434c14b` is published on `main` at https://github.com/LandonPatam/ForgeRevamp. Source, tests, required assets and Forge patches are tracked; builds/caches stay local. History backup: `backups/ForgeUI-baseline-2026-11-04.bundle`.
- Agreed update workflow: Windows implements/tests on a feature/fix branch and commits/pushes it, then supplies a Mac rebuild/test prompt with branch/commit. Mac pulls that exact code and pushes compatibility fixes on the same branch; Windows pulls/rechecks. Merge after both platforms pass final affected code. Documentation-only updates need review rather than game builds. See `docs/development-workflow.md` and AGENTS.md.
- ForgeUI supports host-authoritative online play and joining-player reconnect persistence; see current source and `docs/online-play.md`. Older notes claiming online play is absent are obsolete. Solo/host crash recovery is not requested.
- Tapped pile members shift down to expose the card behind, including dragged piles. Anchors and neighbors stay fixed. The rendered UI suite passed and the pile capture was inspected before repository setup.
- Baseline checks: Godot 4.7.2 import and all 12 browser protocol checks passed; the recorded Forge patch passes reverse-application validation against the local patched dependency checkout. Mac checks remain pending.

## Known issues

- The existing Mac checkout contains platform work unavailable here. Current baseline launchers include Windows-specific commands. Preserve the Mac copy; the baseline is not Mac-validated.
- Forge can occasionally reject a generated Talrand bot deck before readiness (previously observed). The 900-frame smoke wrapper can expire early; see CLAUDE_HANDOFF.txt for the extended command.
- Historical handoffs may be outdated. Prefer current source, AGENTS.md and the shared workflow.

## Next steps

- Mac: preserve the old project, clone into a new sibling directory and create `chore/mac-reconciliation`. Compare/import unique fixes, launchers, export presets and packaging; reconcile unique Forge patches.
- Finish reconciliation before new online work. Push Mac reconciliation, test affected Windows behavior, then merge after both platforms pass. Online hosting/protocol fixes need Windows-host/Mac-join and the reverse when affected. `.exe` and `.app` packages come from the same tagged source.
