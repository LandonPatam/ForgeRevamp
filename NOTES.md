# Session notes - 2026-11-04

## Current state

- `chore/mac-reconciliation` consolidates Windows baseline `434c14b` with unique Mac work. Implementation commits: `824ce26` (lobby/portable bridge checks), `23380b5` (Mac UI/runtime/packaging), `f4fae0e` (opening-hand layout for short 2x viewports). See `docs/mac-reconciliation.md` for decisions, artifacts and checks.
- Original Mac project remains intact at `../ForgeUI`; full verified backup is `../mac-backups/ForgeUI-pre-reconciliation-20261104.tar.gz` with SHA-256 sidecar. This new sibling clone contains the shared source; caches, builds and credentials remain untracked.
- Imported 2x UI surfaces, editor artwork/input fixes, render optimizations, layout-loop recovery, remote-seat recovery improvements and lobby validation. Retained Windows downward pile tap behavior, solo phase stops, protocol protections, Windows scripts and export preset.
- Forge stays pinned to `84f4983`; all 15 local upstream modifications exactly match the existing tracked patch. No additional Mac patch was required. Full Forge/bridge build, 445 Java checks, 12 browser checks, 73 source online checks, 8 four-seat turn checks, repeated solo bot phase stops, library and Retina integration passed.
- Universal Mac DMG built and verified at `dist/ForgeUI-mac-reconciliation-universal.dmg`, from clean implementation commit `23380b5`; a final rebuild is pending after the verified short-viewport opening-hand fix. Apple Silicon and Intel/Rosetta bundled real-match launch/cleanup passed; packaged Intel runtime passed all 73 online checks.

## Known issues

- Source smoke still fails existing attacker-scroll containment at 1280x800 and hand drag reorder assertions. Both reproduce in an isolated original Mac source copy; attacker-scroll also fails on untouched Windows baseline on Mac. Release smoke disables assertions, so its pass does not resolve these source failures.
- Native Intel hardware, physical Mac-to-Windows play and outside-network/router behavior remain unverified. Mac signing is ad hoc, without Developer ID/notarization.
- Historical handoffs and original Mac NOTES are outdated; use current source and the reconciliation record.

## Next steps

- Windows: fetch `chore/mac-reconciliation`; run affected import/UI/library/pile, Java/browser/online/solo phase, and Windows packaging/launch checks. Report the tested commit.
- Resolve or explicitly triage source smoke issues. Merge into `main` only after Windows checks pass; this session does not merge.
- Keep the original Mac project and backup until consolidation is accepted on both platforms.
