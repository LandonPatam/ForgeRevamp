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

## UI sandbox (try a change by hand)

For UI work, open the real table directly on a prepared board instead of playing a game to reach it:

```
node client-godot/tools/sandbox.mjs                  # list boards with one-line descriptions
node client-godot/tools/sandbox.mjs busy-table       # real Forge on that board, playable window
node client-godot/tools/sandbox.mjs --mock           # MockAdapter table (layout only, no rules)
node client-godot/tools/sandbox.mjs decisions --shot # screenshot to client-godot/artifacts/sandbox-decisions.png, then exit
```

- It starts a real `BridgeMain` with `--test-state`, clicks through startup (notices, Keep, starting player) and stops on your priority in the board's phase. From there every decision is yours and Forge is the rules authority.
- Saving a `.gd`/`.tscn`/`.tres`/`.gdshader` relaunches only the window. The engine keeps running, so the new code opens on the same board as you left it. Saving the board file restarts the board. In the terminal: `r` relaunch window, `b` restart board, `q` quit. Closing the window also quits.
- Boards: `client-godot/tests/sandbox/` holds UI playgrounds (`busy-table`, `decisions`, `wide-combat`, `empty`). Every `tests/scenarios/` board works too. A sandbox board with the same name wins. The first `#` line is the description shown in the list; lines starting with `#` are comments. Copy `empty.state` to make a new one; the launcher strips blank lines (Forge's parser rejects them).
- Options: `--opponents=1..3`, `--deck=<tests/*.dck>` (commander/library fixture), `--size=WxH`, `--no-watch`.
- Logs: `client-godot/artifacts/sandbox-bridge.log` and `sandbox-godot.log`. Script errors and unknown card names are echoed in the terminal.
- Agents present every UI change through the sandbox (procedure in `AGENTS.md`, "Presenting a UI/table change"): a board that shows it, a `--shot` they looked at first, then the exact command, the steps to reach the change and what to expect. Example: `node client-godot/tools/sandbox.mjs discard`, "tap a Mountain, cast Faithless Looting, then click two hand cards". Sandbox boards have no driver and are not part of `check.mjs`; boards under `tests/scenarios/` do have one.

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

### Probe, then design

Before designing a UI change for an engine decision, see exactly what Forge sends. Add the board and a throwaway driver that reaches the moment and prints it, run it, read it, then design:

```gdscript
func my_case() -> bool:
	ui._click_card(find_card("Temple of Malice").id)
	await pass_until(func(): return not ui.snapshot.asks.is_empty())
	await dump("temple")  # prints prompt, asks, stack and which UI is showing; captures with --render
	return true
```

Turn the probe into the real check once the design works (assert what the player sees and the engine result). Delete probes the user does not need.

### Board and driver tricks

- Card modifiers: `|Tapped`, `|Damage:2`, `|Counters:P1P1=2`, `|Id:1`, `|AttachedTo:1`, `|IsCommander`, `|FaceDown`. Lines starting `#` are comments; the first one is the sandbox description.
- `p1putonstack=Card` or `Card->1` (target id 1) puts an opponent's **spell** on the stack (X is 0; activated abilities cannot be placed). For an AI X spell or ability, give the AI the card and mana on its turn (`activeplayer=p1`) and let it cast (Earthquake, Blaze work); for upkeep triggers start in your `MAIN2` and pass.
- Helpers in `ScenarioIntegration.gd` / `LiveIntegration.gd`:
  - `pass_until(cond, limit)` passes priority/declarations frame-fast until `cond` holds (no settle waits);
  - `dump(tag)` prints a probe;
  - `press_card_tether(name)` answers a card-list tether;
  - `answer_off_popup(value)` answers an ask shown on a tether instead of a popup;
  - `submit_choice()` and `step()` already handle tethers.
- `wait_ready()` waits at least 300 ms per call. Do not use it in timing measurements; `phase-timing` shows how to measure frame-fast.

### Working habits that keep this fast

- **One Godot run at a time.** Never start a check, a sandbox or a probe while a background suite runs, and do not edit scripts it will load (a half-edited file breaks every later scenario). Prepare edits in the scratchpad and apply them when the run finishes. The full scenario list: `node tools/check.mjs scenario "$(ls tests/scenarios/*.state | xargs -n1 basename | sed 's/\.state$//' | paste -sd, -)"` (`scenario all` is not a name).
- **Backslashes in GDScript regexes:** shell heredocs and Python string layers eat them (`" \\(\\d+\\)"` becomes an invalid `" \(\d+\)"`, `"\n"` becomes a real newline inside a string). Write those lines with the Edit tool, or check the file afterwards (`grep -n create_from_string`).
- **Bridge Java changes:** `node client-godot/tools/check.mjs bridge` rebuilds and tests. **Trap:** VS Code's Java extension compiles into the same `bridge/target/classes` and writes a class that throws "Unresolved compilation problem" for a file with errors; Maven then treats it as up to date and `check.mjs bridge` reports PASS while the bridge fails at runtime (symptom: scenarios time out "CONNECTING TO FORGE", no first snapshot, no error printed). After non-trivial bridge edits, compile with the direct `javac` command under "Stale bridge classes" below; it reports real errors. **Forge source changes** (rare; record them in `FORGE_PATCHES.md` with a patch file) also need `forge-gui` installed first (commands in `FORGE_PATCHES.md`, "Building").
- **Failures that look random:** rerun the scenario alone 2–3 times before changing code; several drivers time out only under the load of a long suite (`blink`, `tokens`). `blocking` and `insights` fail independently of recent work.
- **Look at every capture you mention to the user.** Several bugs (a frame under a window, a hidden Yes button, a counter off by meaning) were only visible in the PNG.

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
