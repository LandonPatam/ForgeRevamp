# Session notes - 2026-11-17

## Current state

- Windows checkout is on `feature/stuck-guard-and-reports` at pushed commit `45eafa9`. Local `main` is `cda06eb`. This session's changes and new fixtures are uncommitted in `D:\ForgeUI`. Inspect Git status before switching or packaging.
- ForgeUI now confirms a trigger's sole legal creature, pauses for Continue without blockers, explains ward and its remaining mana, and asks for Heritage's target before its Yes/No resolution choice. The existing Godot tethers and combat rail present these decisions.
- Fixed zero-mode answers, order at both library ends, and whole-library scry counts. Distinct Forge input IDs invalidate staged picks on replacement. Disconnect clears unsent local actions, and Forge's accepted picks remain available through the ordinary controls.
- Windows targeted checks passed. Coverage includes exact target identity, Heritage Yes/No, mode combinations/repeats/pawprints, both trigger orders, partial ward and cancel, optional targets under Auto-resolve, scry order/privacy, and two-seat ordering and reconnect. The isolated build is `bridge/target/verified-coverage`. See [coverage and remaining plan](docs/interaction-reliability.md).
- The vendored checkout has the prior patches plus `forced-decisions.patch` and `library-ends.patch` applied locally. See [rebuild and apply order](FORGE_PATCHES.md). Rebuild Forge Game, Forge GUI and the bridge before validating on another machine.

## Known issues

- The full suite and Mac/live cross-platform validation are pending for these changes. During this session the Windows game held the standard bridge JARs open. The verified build used separate output and did not restart that match.
- The earlier local shape sweep is separate work. Preserve `client-godot/tools/shape-sweep.mjs`, the `check.mjs shapes` changes, `shape_probe`, and the ignore entry. Keep those hunks out of the reliability commits. Its last recorded full run was 55/72 resolved, 4 uncastable and 13 driver failures. The driver still needs better AI waits, rail player targets and scry answers.
- Forge's board export omits the stack and triggers in flight. Reproduce mid-trigger F8 reports from an earlier step or recast in the driver. If Maven claims success but Forge throws an unresolved compilation error, check compilation directly as described in [testing.md](docs/testing.md).

## Next steps

1. Custom vs generic presentation pairs are done for targets, players, modes, trigger order and library search (see [reliability](docs/interaction-reliability.md); uncommitted). Add a pair for any new presentation.
2. Interruptions and the Stack responses matrix are covered (`flagbearer-replaced`, `discard-interrupted`, `matrix-*`). Open: a notice-and-pass ability case for the matrix, then the same checks on a two-seat online table.
3. Add a decision-variant inventory to the precon playtester report and map observed variants to named Godot checks. Keep discovery runs distinct from checks that verify the exact result.
4. Coordinate the local handoff before publishing. Run `check.mjs all` before a push, review the mixed test-file hunks, and send the exact branch and commit for Mac rebuild and Windows–Mac play in both host directions.
