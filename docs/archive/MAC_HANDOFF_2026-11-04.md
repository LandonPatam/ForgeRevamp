# ForgeUI Mac handoff — November 4, 2026

Implement the following changes in the Mac checkout, preserving its existing online fixes, packaging and platform-specific launchers. This document describes the final Windows implementation; the earlier display-only phase fix was incomplete and must not be ported by itself.

The user explicitly declined solo-game crash recovery and host crash recovery. Do not implement either. No commit, release package or upstream Forge change was made for this work. The Windows tree contains extensive pre-existing modified/untracked work; do not copy the whole tree or treat its entire diff as this task.

## 1. Remove large deck-editor hover previews

Files:

- `client-godot/scripts/library/DeckCollection.gd`
- `client-godot/tests/LibraryIntegration.gd`

Remove the editor's hover popup machinery: `hover_panel`, `hover_timer`, `hover_source`, `hover_card`, their initialization/cleanup, `_show_hover()`, and the tile `hovered`/`mouse_exited` connections that show/hide that popup. Keep `tile.chosen.connect(_inspect)` and `tile.context_requested.connect(_card_context)`: clicking still inspects a card and right-click actions still work. Keep normal tile hover styling and text tooltips. Import previews are unrelated and stay.

In `_style_workbench`, retain the exclusion `if node == overlay or node is Window: return` after removing its former `hover_panel` exclusion.

Change the library integration check that formerly waited for `ui.hover_panel.visible`: emit the tile hover, wait 0.5 seconds, assert that the editor's overlay is still hidden, and capture the unobstructed grid. The capture remains named `library-card-hover.png`.

## 2. Stable phase buttons AND real pauses during bot turns

Files:

- `bridge/src/main/java/forgeui/bridge/BridgeGuiGame.java`
- `bridge/src/main/java/forgeui/bridge/BridgeMain.java`
- `bridge/src/test/java/forgeui/bridge/BridgeChecks.java`
- New `bridge/tools/solo-phase-check.mjs` in Windows checkout (see portability notes below).

The bug had two parts:

1. `phaseStops()` reported `!human.isUiSetToSkipPhase(...)`. That includes transient legal-action availability, so every bot's buttons could light up, switch off, and switch back without a user change.
2. The existing nonactive-seat policy skipped empty-stack phases when the human had no legal response. Stabilizing the buttons alone left selected bot phases getting skipped.

Final implementation:

```java
private boolean onlineMatch;
void setOnlineMatch(boolean online) { onlineMatch = online; }

boolean configuredPhaseStop(PlayerView player, PhaseType phase) {
    return phaseStopOverrides.getOrDefault(
        player.getId() + ":" + phase.name(), defaultPhaseStop(phase));
}
```

`defaultPhaseStop` is true ONLY for `MAIN1`, `COMBAT_DECLARE_ATTACKERS`, `COMBAT_DECLARE_BLOCKERS`, `MAIN2` (M1/DA/DB/M2).

For every player's entry in `phaseStops()`, report `configuredPhaseStop(player, phase)`. Continue excluding UNTAP. Do not compute displayed selections from current response availability.

At the start of `isUiSetToSkipPhase`:

```java
if (!onlineMatch) return !configuredPhaseStop(playerTurn, phase);
```

After that early return, preserve the existing online logic, including explicit overrides, nonactive-seat legal-response checks, and skipping redundant declaration priority without a legal action. Do not replace online logic with the solo behavior.

In `BridgeMain`, after constructing the host and all remote `Seat`s, before starting the match/server:

```java
for (Seat seat : seats) seat.gui.setOnlineMatch(seats.size() > 1);
```

Here `seats` contains human connection seats, not all Forge players. One local human plus bots gets solo behavior; two or more humans gets the existing online behavior. Do not infer online mode from total player count or active player's type.

No networking, revision, token, snapshot visibility or game protocol changes are required for the phase fix. Forge still owns declarations, legal responses and all decisions.

Regression coverage added to `BridgeChecks`:

- Every solo player uses M1/DA/DB/M2 defaults regardless of available actions.
- Disabling/re-enabling a bot M1 stop changes actual skip behavior.
- Online inactive-seat and declaration behavior stays as before.
- Serialized phase selections remain stable as availability changes false/true/false.
- Explicit enabled/disabled overrides remain reflected in serialized state.
- The GUI fixture needs `setGameView(game.getView())` before inspecting `phaseStops()`.
- An existing `FixtureInput` test needed `@Override public String getActivateAction(forge.game.card.Card card) { return null; }` to compile against the current Forge Input interface.

The real solo check launches an isolated BridgeMain with two bots, drives opening choices/draws/cleanup and passes priority, and verifies bot priority inputs remain waiting without a human pass. It requires both bots to pause at M1 and M2 on at least two turns each. It also checks DA/DB whenever those inputs occur. Use raw `game.phaseKey` for enum names; `game.phase` is a display string. DB did not occur in the short verified match; regression checks cover it.

## 3. Joining-player recovery after an app crash/restart

Files:

- New `client-godot/scripts/app/RemoteSession.gd`
- `client-godot/scripts/app/Application.gd`
- `client-godot/scripts/app/SessionDisk.gd`
- `client-godot/scripts/bridge/LiveAdapter.gd`
- New `client-godot/tests/RemoteSessionChecks.gd`
- `client-godot/tests/ApplicationIntegration.gd`
- `client-godot/tests/LiveAdapterChecks.gd`
- `docs/online-play.md`, `AGENTS.md`

This reconnects a joining client to an engine that is STILL RUNNING on the host. It does not serialize or resurrect a Forge game. Existing host behavior holds an absent remote seat for five minutes, then concedes it. Existing client retries give up after 180 seconds. Those limits were not changed.

### Persistence helper

`RemoteSession.gd` extends RefCounted and has an overridable `path`, default `user://online-session.cfg`.

- `read() -> Dictionary`: load ConfigFile; accept `[seat] version = 1` and a Dictionary `resume`. Validate string `url` beginning `ws://` or `wss://`, nonempty string `token`, Dictionary `deck` and `info`, and string `session_id` (empty is permitted before the first snapshot). Missing/invalid files return `{}`.
- `save(value: Dictionary) -> Error`: put version and resume into ConfigFile, save to `path + ".tmp"`, then `DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))`. Never truncate the active file before a successful write. Check replacement of an existing file on macOS.
- `clear()`: remove only that exact file and its `.tmp`, if present.

Stored shape:

```text
{
  url: host WebSocket URL,
  token: random seat credential,
  session_id: match UUID, initially empty until a real snapshot,
  deck: { id: local deck ID, name: display name },
  info: {
    name: display name, turn: last observed turn,
    phase: last observed display phase, life: local player's life,
    reconnect: true,
    decision: "Rejoin while the host is still running. Disconnected seats are held for up to five minutes."
  }
}
```

Only reconnect credentials and public disk metadata are persisted. Do NOT save hand contents, full snapshots, pending actions, answers, revision/request counters or hidden information. Do not log or include real credential files in a handoff/package.

### Application lifecycle

Add `remote_store` (helper instance) and `remote_resume: Dictionary` alongside existing `remote_game`/`remote_token` state.

- During `_ready`, load the saved seat before building the menu. Test runs override the helper path to `<--library-fixture>/online-session.cfg` when `--app-check` is set, keeping tests away from real user credentials.
- `_restore_remote_session()` reads the helper. If nonempty, set `remote_game = true`, `remote_token`, `match_deck` from saved metadata and `parked = true`. Leave `game == null`; there is no connection or engine until Resume is clicked. If the computer already exists, refresh its session disk.
- `_session_info()` returns saved `info` when `game == null`. `_ensure_computer()` creates the session disk from that info on startup.
- `_begin_remote_match(url, token)` saves initial reconnect data immediately, before its existing waits/insertion animation. This also covers crashes during loading. Continue the existing joined-player launch afterward.
- `_remember_remote_snapshot(state)` listens to the remote adapter's `state_changed`. Only update on `connectionReady`. Save the real `sessionId` and sanitized deck/disk metadata if changed. If `game.gameOver`, clear the saved file instead. This callback runs before Main consumes the snapshot, so use its argument rather than `game.snapshot`.
- `_show_game(url, resuming := false)` creates a NEW Main/LiveAdapter as before. For remote games set its token, expected session identity, snapshot callback and existing session-ended callback, then `_reveal_game(resuming)`.
- `resume_game()` accepts `parked` with no game if saved credentials exist. Set busy, unpark, and `await _show_game(remote_resume.url, true)`. This uses the existing session-disk insertion/reveal transition and waits for a fresh authoritative snapshot. Existing in-memory parked sessions still use their existing scene and adapter.
- A recovery disk reserves the one active-session slot: block PLAY and automatic online launch when `parked`, even if `game == null`. Set MatchSettings' `game_running = game != null or parked` to block joining/hosting a second table over it.
- `request_end_game()` also accepts an unconnected recovery disk. Its confirmation becomes **Forget online session?**, with **Forget session** and text explaining the host may keep waiting until the seat times out. This clears local recovery data and plays the existing silent FORMAT A: disk consumption. It does not stop a host or claim to concede while disconnected. `_forget_remote_session()` uses the ending-session flag during cleanup so the disk survives until formatting.
- `_clear_ended_match()` clears persistent credentials and `remote_resume` for remote games, alongside the existing in-memory cleanup.
- `_remote_session_ended(message)` clears persistence immediately, then follows the existing safe transition/end cleanup. Show the ending/failure message after returning home. Existing adapter timeout uses the same terminal path, so failed reconnects also clear persistence.
- Confirmed Quit during a connected/parked remote game clears the file, calls `leave_table()`, and quits directly. Do NOT then send local `match.stop` for a remote game. Closing the app with only an idle recovery disk preserves it for a later attempt.

### Disk appearance and adapter guard

In `SessionDisk.update_info`, when `info.reconnect` is true:

- Printed heading **ONLINE SESSION**.
- Final state line **CLICK TO REJOIN**.
- Details **REJOIN ONLINE GAME** plus deck name.
- Lower button **Forget session**.

Keep existing styling, physical floppy, transitions and the ordinary parked-session appearance. Set the normal lower button back to **End Game** when reconnect is false.

`LiveAdapter` adds `expected_session := ""`. After receiving a nonloading state with a nonempty `sessionId`, before accepting/normalizing it: if the expected identity is nonempty and differs, call `_finish_session("This online game is no longer available.")` and return. This guard is for restored credentials; do not change ordinary unpinned session behavior. The token remains the host's authentication mechanism. Fresh adapters start without pending inputs; do not restore/replay actions.

### Recovery tests

- `RemoteSessionChecks`: absent file, save/load through a fresh helper, replacement of an existing save, no leftover `.tmp`, deletion visible across instances, invalid endpoint ignored. Use a fixture path, not real user state.
- `LiveAdapterChecks`: a saved seat pinned to one match rejects a different match and clears credentials without publishing it.
- `ApplicationIntegration.online_join_check`: real host/lobby/joined app, persistence before a disconnect, remove the joined scene and clear its reconnect memory WITHOUT Leave, reload the file, assert a recovery disk exists and PLAY is disabled, Resume through insertion, confirm the original engine session and player identity, and confirm no pending action/answer was recreated. Then host stop must clear the file and return home. Keep the reverse-role automatic-host-readiness checks afterward.
- This application test simulates losing the client scene and memory; it does not kill/relaunch the Godot process. Real macOS force-quit/relaunch remains a useful manual acceptance check.

## Validation already performed on Windows

- Rendered library integration passed; inspected `client-godot/artifacts/library-card-hover.png` (grid unobstructed).
- 445 Java bridge regression checks passed after compiling directly with javac.
- `node bridge/tools/online-check.mjs`: all 61 checks passed after the phase fix, including seat isolation, reconnect, readiness, inactive-seat progression and terminal host shutdown. No Java/protocol changes followed for recovery.
- Real solo phase check observed both bots waiting at M1/DA/M2 across repeated turns. As noted above, no DB opportunity occurred in that short match.
- `node client-godot/tools/app-check.mjs --render --menu-preview` passed with final recovery implementation, persistence checks, real host-seat reconnect and cleanup, plus existing online join and automatic host launch checks.
- Extended Godot mock smoke reached PASS, including live-adapter recovery/privacy checks. The restricted Windows environment emitted a system CA-store error; initial smoke also lacked writable user caches. Re-running with APPDATA redirected inside the workspace resolved the cache assertion. Do not mistake these environment messages for a clean no-warning log.
- Inspected final rendered recovery disk. Reference captures in Windows checkout: `app-online-recovered-session.png`, `app-online-recovered-table.png`, `app-online-host-ended-home.png` under `client-godot/artifacts/`.

Windows Maven's normal test wrapper encountered stale/missing classpath output. The documented direct javac build of ALL bridge main sources, followed by BridgeChecks compilation/execution, succeeded. Rebuild/restart services after Java edits; a running engine retains old classes.

## Mac port and acceptance

Use Mac-native existing build/test scripts. Windows Node checks often hardcode `java.exe`, Godot `.exe` paths and Java classpath `;`. Adapt to macOS Java/Godot and classpath `:` (`node:path`'s `delimiter`) before running them. Do not replace working Mac packaging or launchers with Windows versions. Godot `user://`, ConfigFile and ProjectSettings path globalization should remain portable.

Run relevant Godot parsing/smoke, editor rendered integration, bridge regressions, online checks, and the rendered application join/recovery flow. Then manually force-quit ONLY a joining app while the host stays running, reopen it, and click its Rejoin disk before the five-minute seat timeout. Verify same hand/board/seat/current decision, no replayed action, and unchanged legal response windows. Verify Leave/host end removes the saved file; test forgetting an idle recovery disk and an unavailable host. Rebuild the Mac export with the new GDScript and test resources included.

Do not promise solo recovery, host recovery, recovery after the engine exits, or recovery after the host has conceded an expired seat. The user explicitly decided against implementing those features.
