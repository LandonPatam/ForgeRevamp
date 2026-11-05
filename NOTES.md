# Session notes - 2026-11-04

## Current state

- Windows and Mac use the consolidated source on shared `main`; reconciliation retains both platforms' launchers, packaging and presets. Mac implementation through `015c08d` and Windows acceptance are recorded in `docs/mac-reconciliation.md` and `docs/windows-reconciliation.md`; use `git log` for the acceptance commit.
- Windows checks passed: Godot import, 445 Java/12 browser/73 local online/8 four-seat checks, repeated solo bot stops, source smoke, full rendered app/library/2x UI, battlefield/piles and 231 hand-hover frames. Captures were inspected. Added test-only headless/whole-pixel expectations and actual-JVM lookup to prevent Windows Java shim cleanup leaks; game/bridge runtime source was unchanged by Windows acceptance.
- Windows validation package: `dist/ForgeUI-windows-reconciliation/ForgeUI.exe` with bundled runtime/service/assets. Exported smoke and bundled real-match/hidden-hand/process-cleanup checks passed. Keep the whole folder. Mac universal DMG and original-project backup remain on the Mac as recorded in its reconciliation document.
- User chose to test physical Windows/Mac play personally AFTER merging, because another in-game online issue needs addressing. That issue is not yet described or fixed; local automated checks do not verify physical cross-platform play.
- Workflow: Windows implements/tests and pushes a short-lived branch; Mac pulls/rebuilds/tests and pushes compatibility fixes during its turn; Windows pulls/rechecks; merge after affected checks pass. Handoffs give branch/commit and a test prompt. Packages use the same tagged source for Windows `.exe` and Mac `.app`.

## Known issues

- Mac source smoke still has documented pre-existing attacker-scroll and hand-reorder failures; Windows source and rendered suites passed. Native Intel hardware, live host/join in both directions and internet/router behavior remain unverified. Mac signing remains ad hoc.
- Local lobby suites share Forge's online port and must run serially. Test tools must launch the actual JVM, not the Windows PATH Java shim. Only test-owned orphan JVMs were stopped; pre-existing processes were preserved.
- Generated Talrand bot decks can occasionally fail Forge validation (previously observed). The 900-frame smoke wrapper can expire early; extended source smoke uses 3600 frames.

## Next steps

- Both machines should use current `main` and rebuild affected components for the user's live test. Preserve the original Mac project/backup.
- User will test the merged builds together and describe the additional online issue. Implement that fix once on a new shared branch and test both host/join directions.
- No GitHub Release was published. Historical handoffs are superseded by current source, AGENTS.md and `docs/development-workflow.md`.
