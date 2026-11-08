# Fixing and testing

How to take a reported problem to a verified fix without running every suite each time.
Everything goes through one quiet runner:

```
node client-godot/tools/check.mjs <ui|visual|scenario|bridge|online|solo|all> [Names,...] [--render]
```

It prints one `PASS`/`FAIL` line per step. A failure also prints the lines around it. The full output goes to `client-godot/artifacts/check-logs/<step>.log`; read that file only when the printed lines aren't enough.

## The pipeline

1. **Reproduce first.** For a gameplay bug (a card, ability, popup, stack or engine interaction), write a scenario that fails before you change any code (see below). Run it and confirm it fails for the reported reason. Most real bugs live between Forge and the table, and the mock suites can't see them.
2. **Fix it.** Keep the diff focused (AGENTS.md design rules still apply).
3. **Run only the checks for what you touched** (table below), plus the new scenario. Iterate on these alone.
4. **Visual changes:** run `visual <Name>` for that check only, then look at the one or two captures it lists. Don't review captures for changes that aren't visual.
5. **Before the push, once:** run `all` (it includes every real-engine scenario). Then commit/push the feature branch and hand off to Mac (AGENTS.md working rules).

Don't rerun the whole suite after every edit. When one check fails, rerun just that check.

## Keep testing proportional

- **UI-only changes** (layout, wording, colors, popups that don't change what is sent to Forge): run the matching `ui`/`visual` check once and let the user play it. Don't write a new scenario or run `all` for these.
- **Engine/rules bugs** (what Forge does, payment, targeting, stack, combat): reproduce with a scenario first, as above.
- **When a check fails but the feature looks right, stop and ask the user.** Report the failing assertion and why it may be the test, not the feature. Don't loop on rewriting working code to satisfy a check, and don't rerun a failing check more than twice.
- **Tests assert behavior, not implementation.** Check what a player can observe or what Forge receives (who is targeted, which instance was sent, that hidden faces stay hidden, that nothing replays). Don't pin exact wording, internal node names or pixel sizes; those belong in a `visual` capture the user looks at.
- Timeouts are short on purpose: a live wait fails after 30 s without a ready snapshot (`LiveIntegration.wait_ready`). Don't raise them to make a flaky check pass; find out why it stalls.

## Which check for which change

| Changed | Run |
|---|---|
| A table UI script (`scripts/ui/*`) | `ui <Name>`: the matching `tests/<Name>Checks.gd` (e.g. `PromptPanel` → `CardFeedback,RequiredModal`; `IncomingEffect.gd` → `IncomingEffect`; stack/priority → `AutoPriority,StackAttention`) |
| The look of something | `visual <Name>`, then inspect the listed PNGs |
| How the table talks to Forge (`LiveAdapter.gd`, prompts, payment, casting) | `ui <Name>` plus the closest `scenario` |
| Bridge Java (`bridge/src/...`) | `bridge`, plus a `scenario` if gameplay changed. Restart the game afterwards |
| Online lobby, seats, protocol, hidden information | `bridge` then `online` (serially; they share the online port) |
| Phase stops / auto-pass on bot turns | `solo` |
| Home/computer/editor/app flow, online lobby/ready | `node client-godot/tools/app-check.mjs --render` / `library-check.mjs --render` (not wrapped yet; about 5 min). Always pass `--render`: headless runs can't click onto the 3D monitor and fail at the search-bar check |
| Docs only | Nothing; review the diff and links |

`ui` with no names runs the whole headless smoke suite, and `visual` with no names runs every rendered check. Leave those to `all`.

## Real-engine scenarios

`scenario <name>` starts a real Forge `BridgeMain` with a prepared board and drives the real Godot table the way a player would (`client-godot/tools/live-check.mjs --scenario=<name>`). `--render` also saves `client-godot/artifacts/scenario-<name>-1600-<stage>.png`. Each scenario takes about 15–40 s. `scenario` with no name lists the existing ones.

Adding one (no other registration needed):

1. **Board:** `client-godot/tests/scenarios/<name>.state`, in Forge's game-state format. Copy `mind-stone.state`. Useful keys: `activeplayer`, `activephase`, `turn`, `p0battlefield=Card;Card|Id:1;Equipment|AttachedTo:1`, `p0hand`, `p0library`, `p1putonstack`, `removesummoningsickness=true`. p0 is you; p1/p2 are Forge AIs.
2. **Driver:** add `func <name_with_underscores>() -> bool` to `client-godot/tests/ScenarioIntegration.gd`. The board is already loaded at turn 5 with priority.
   - Act through the same UI paths as a player: `ui._click_card(id)`, `ui.modal_panel.option_buttons[i].pressed.emit()`, `cast(name)`, `tap(name)`, `select_named(name)`, `drop_equipment(a, b)`, `settle()`.
   - Call `wait_ready()` after each action.
   - Assert the *engine* result from `ui.snapshot` (tapped, `players[0].mana`, zones, counters, life, stack) with `check(condition, message)`.
   - `capture("stage")` saves a screenshot when `--render` is used.
3. **Prove it:** run it against the broken code (or temporarily reintroduce the bug) and confirm it fails with your message; then confirm it passes with the fix.

`mind_stone()` is the template: it clicks Mind Stone, clicks the "Add {C}" ability in the real Forge popup, and asserts that the stone tapped and `{C}` is floating. With the old Confirm-required popup it fails with "Choosing the ability must tap Mind Stone".

## Stale bridge classes

If incremental Maven output looks stale (source changes seem absent), compile the bridge directly before retesting (PowerShell), then restart any running service:

```
$bridgeSources = @(Get-ChildItem -LiteralPath bridge/src/main/java -Filter *.java -Recurse | ForEach-Object { $_.FullName })
javac -encoding UTF-8 -cp 'bridge/target/classes;bridge/target/lib/*' -d bridge/target/classes @bridgeSources
javac -encoding UTF-8 -cp 'bridge/target/classes;bridge/target/lib/*' -d bridge/target/test-classes bridge/src/test/java/forgeui/bridge/BridgeChecks.java
java -cp 'bridge/target/test-classes;bridge/target/classes;bridge/target/lib/*' forgeui.bridge.BridgeChecks
```

## Other tools

- `node bridge/tools/playtest.mjs`: plays whole precon games as the human seat and reports text/engine mismatches. Use it for broad sweeps, not single bugs (`docs/playtest.md`).
- Mock checks (`ui`/`visual`) run against `MockAdapter`, which is not Forge. They guard layout and UI wiring, not rules. Prefer a scenario when the question is "does the game actually do X". Don't add mock checks that only restate the implementation.
- Godot single-check flag, used by the runner: `--smoke --only=A,B` or `--visual-checks=DIR --only=A,B` runs `tests/<A>Checks.gd` and quits with `ONLY CHECKS DONE`.
