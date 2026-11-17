# Session notes - 2026-11-17

## Current state

- `main` is still `cda06eb`. Work waits on `feature/stuck-guard-and-reports` (pushed; it contains `fix/playtest-issues-nov16`): `206e0f3` playtest fixes, `79831e3` stuck guard + F8 reports, `083ba8d` step-2 reliability, plus this wrap-up's docs commit. Windows: targeted checks pass; last full `check.mjs all` passed except `blink`, fixed and rerun 3/3.
- Playtest fixes: Deepglow Skate targets, Maze of Ith during blocks (`hold_phase`), `effectiveCost` (Hazoret's Monument, commander tax, command-zone cost overlay), Outpost Siege modes, Duelist's Heritage yes/no first (`optionalTrigger`), online lobby reopens after a match and friends rejoin.
- Reliability: `ui/DecisionGuard.gd` shows Forge's raw question when nothing on screen answers it and saves a report; F8 reports (host includes `board.state`); `tools/report-to-scenario.mjs`. Target tether declines what it can't fully handle, staged picks use checked senders, questions are keyed by structure. Rule recorded in AGENTS.md ("Reliability first").
- Local only, deliberately uncommitted: card-shape sweep (`tools/shape-sweep.mjs`, `check.mjs shapes`, `shape_probe` in `ScenarioIntegration.gd`, `.gitignore` line). Last run: 55/72 resolved, 4 not castable, 13 failures, all in the test robot; the guard never fired. Leave these files out of commits.

## Known issues

- Mac has not built or tested any of these branches. Online lobby rejoin is unverified between real machines (Windows-host/Mac-join and reverse).
- Shape-sweep robot gaps: waits on AI/engine are treated as stuck; can't target a player from the rail; can't answer scry.
- Resolving cleanly isn't proof of the right result: nothing yet compares what the player chose on screen with what Forge received.
- Forge's board export omits the stack and triggers in flight: reports from mid-trigger moments need a step earlier or a recast in the driver.
- Older items: red damage badge can sit under the phase strip on opponents' rows; spells cast from hand target from the rail; VS Code's Java extension can leave stale `bridge/target/classes` (use the direct `javac` in `docs/testing.md`).

## Next steps

- Mac: `git fetch && git switch feature/stuck-guard-and-reports && git pull --ff-only`, rebuild the bridge, run `check.mjs bridge`, `ui OnlineRejoin`, `online`, and scenarios `maze,skate,monument,outpost,heritage,heritage-yes,guard,panther-claws,reanimate,blink`. Then cross-platform online play, then merge to `main`.
- If wanted: choice log (bridge records what Forge received; compare with on-screen choices in tests and F8 reports).
- Teach the shape robot the three gaps above, then add more cards per shape.
