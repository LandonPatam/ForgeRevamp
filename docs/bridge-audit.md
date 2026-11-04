# Forge bridge audit

Godot integration update (2026-10-22): `LiveAdapter.gd` and the managed launcher now connect a real three-player Commander match. An isolated workspace deck verifies keep-hand input, land/second-land rejection, commander casting, mana payment, stack resolution, later-turn attacker/defender selection, hidden hands, duplicate submission gating, and reconnect without replay. Adapter fixtures cover session replacement, stale snapshots, ask removal and answer gating. The simple live fixture does not always produce generic blocking asks; those remain covered by adapter/Java checks, with broader live targeting/blocking/damage coverage still pending. See the client README for the current implementation; the original findings below remain historical context.

This records the baseline before hardening. The subsequent implementation adds answer validation, protocol v2 session/revision checks and request responses, fresh lookup maps per published snapshot, reconnect-safe snapshot delivery, browser ask replacement, reveal/weak-selection data, typed combat defenders, and stock-dialog combat allocation constraints. See [protocol.md](protocol.md) for the current contract and `bridge/tools/test.ps1` for regression checks. Remaining limitations below should be read with that update in mind.

Post-change validation on 2026-10-22: package succeeded; 60 Java regression checks and 12 browser protocol/recovery checks passed. A separate live three-player Commander smoke run passed 12 checks covering connection snapshots, reconnect, stale session/state rejection, malformed requests, origin rejection, unknown decisions, and controller input with a dealt hand. Startup dialogs vary by deck; invalid generic answers and all five decision mappings are covered by the Java harness even when a particular live startup does not exercise them. The updated browser test page was also captured and visually inspected at `bridge/target/bridge-smoke.png`. Complete casting/combat and game completion remain unverified. Test-owned JVMs were stopped; pre-existing Java processes were left alone.

Audited 2026-10-22 for the proposed Godot frontend. This is a source review and an incremental offline package check, not a new live gameplay verification. No bridge or upstream source was changed.

## Recommendation

Keep the Java bridge and its existing local WebSocket/JSON interface. Add a Godot client in `client-godot/`, with interchangeable mock and live adapters feeding the same presentation model. Forge remains authoritative. There is no need for another bridge or a new rules engine.

Start with a three-player mock Commander table, then connect one local human against two AI opponents using `--opponents 2`. This configuration is expressible by the existing startup code; three-player gameplay was not verified in this audit. Preserve stock Forge netplay as a later integration through Forge's own networking, not by exposing this local WebSocket as a multiplayer server.

## Evidence and build

- `FORGE_COMMIT` and `git -C forge rev-parse HEAD` both report `84f4983c1ce872932cf9a26a8bd54ca00056aae9`.
- `bridge/pom.xml` targets Java 17 and depends on `forge-gui` and `forge-ai` version `2.0.16-SNAPSHOT`. Gson and Netty arrive through Forge dependencies.
- Upstream is a separate checkout in `forge/`. This audit did not verify its working tree or independently prove that the installed snapshot jars were built from that exact commit. The snapshot Maven version alone does not establish build identity.
- Offline packaging succeeded using `.\.tools\apache-maven-3.9.9\bin\mvn.cmd -o -f bridge/pom.xml -DskipTests package`. Existing classes were up to date; this was not a clean compilation. Maven needed access to its local cache outside the sandbox. No bridge test sources were found; tests were skipped.
- `java` and `node` resolve on PATH. Neither `godot` nor `godot4` resolved; this does not establish whether a Godot executable exists elsewhere.
- `bridge-run.log` contains historical activity, but it is not evidence of successful client interactions during this audit.

## Startup and transport

`BridgeMain.run` installs `HeadlessGuiBase`, initializes `FModel`, starts `BridgeServer`, and starts a Commander match through `HostedMatch.startMatch`. One human uses a named Commander deck, or the first available deck; AI opponents cycle through the other stored decks. Opponent count defaults to three (four total players). There is no lobby API, attach-to-existing-process mode, deck listing endpoint, restart endpoint, or shutdown endpoint.

`BridgeServer` binds only to `127.0.0.1`, default port 7777. It serves a bundled browser test page at `/` and JSON text frames at `/ws`. All sockets receive the same broadcasts and can submit actions for the same human controller. No client authentication, seat ownership, spectator role, or origin validation is implemented in the bridge.

The game starts independently of a client connection and can wait for a prompt answer. Disconnecting does not cancel pending decisions or terminate the game. There is no explicit process cleanup lifecycle.

Windows PowerShell launch after packaging, from `D:\ForgeUI\bridge`:

```powershell
java -Xmx4g -cp "target/classes;target/lib/*" forgeui.bridge.BridgeMain --assets ../forge/forge-gui --opponents 2
```

Add `--deck "Exact Commander deck name"` if needed. Requires the pinned Forge dependencies already installed in Maven, upstream assets, and Commander decks in Forge's normal user directory. `run.sh` provides the same startup path through a shell but uses a Windows classpath separator.

## Implemented protocol

| Direction / type | Behavior |
| --- | --- |
| Server `state` | Full snapshot, or `{type:"state", loading:true}` during initialization. Contains `me`, game, players, zones, stack, combat, prompt, log, and outstanding asks. |
| Server `ask` | Blocking dialog represented as `choose`, `order`, `distribute`, `input`, or `message`, with an integer decision ID. |
| Server `askClosed` | Removes a resolved decision by ID. |
| Server `flash` | Generic feedback for an incorrect action; no explanation or action correlation. |
| Client `hello` | Invalidates snapshot deduplication and requests a full state broadcast. |
| Client `action` | `ok`, `cancel`, `card`, `player`, `stack`, `mana`, `undo`, or `concede`, plus an ID when needed. |
| Client `answer` | Completes a pending decision using its ID and a JSON value. |

Actions resolve IDs through maps and invoke Forge's `IGameController` on the bridge's single-thread EDT. Mana IDs use Forge color bytes: W=1, U=2, B=4, R=8, G=16, C=0. Clicking a card is a contextual intent: Forge determines whether it plays a land, activates an ability, pays a cost, or selects something. There is no independent client command to set tapped state or declare an action legal.

Answers complete `CompletableFuture`s directly from the socket handler. The waiting engine caller interprets the result. Choose/order answers are option indices, distributions are positional amounts, input is a string or null, and message prompts accept an acknowledgment.

## State and identifiers

`GameStateJson` sends full snapshots on a dirty flag, checked every 60 ms after an initial delay. Identical JSON is suppressed. There are no public JSON deltas, structured animation events, protocol versions, session/game IDs, snapshot sequence numbers, timestamps, command IDs, or acknowledgments. Underlying Forge networking has additional mechanisms, but they are not exposed in this JSON protocol.

- Cards, players, and stack entries use Forge view instance IDs. These are not card-definition IDs or globally stable identities across games/processes. Their types have separate namespaces.
- `prompt.targets` and `prompt.chosen` prefix references (`card:5`, `player:1`, `stack:9`); selectable cards are bare integer IDs. Actions supply the namespace through the action name.
- Decisions use an atomic increasing integer within the `BridgeGuiGame` instance. Ability choices use option positions and labels, not standalone ability IDs. Zones use enum names under each player, not unique zone IDs.
- Card/player/stack lookup maps are populated during serialization and never cleared. Removed objects can remain addressable; a failed snapshot can partially update those maps.
- Combat defenders are serialized as display text, not a typed entity reference. Reliable multiplayer targeting/combat lines need a defender ID and kind.
- Only Battlefield, Hand, Graveyard, Exile, and Command are serialized as card arrays. Library is a count. Other zones and temporary reveal presentations need separate support.
- Weakly selectable cards are stored by the inherited implementation but not serialized. A selectable highlight is contextual selection information, not a complete enumeration of legal plays.
- Game log output is limited to 40 entries. No cursor/history API exists.

Reads occur off the game thread. Runtime exceptions during snapshot generation silently mark the state dirty for retry. A successful read is not necessarily an atomic view of a game transition. Godot should initially reconcile by full snapshot and instance ID; animations cannot assume every intermediate transition is delivered.

## Prompt coverage and limitations

`BridgeGuiGame` implements generic choices, orderings, confirmations, input dialogs, ability selection, entity choices, combat damage, and generic distributions. Targeting, priority, mana payment, mulligans, discards, attackers, and blockers use contextual prompt/buttons/selection plus controller clicks. Inherited convenience methods route many requests to these generic implementations.

The fallback is useful but does not yet prove that every decision is safe or fully represented:

| Finding | Impact / recommended correction |
| --- | --- |
| Answers resolve before server-side shape and constraint validation | `choose` filters duplicate/out-of-range indices but does not enforce min/max. `order` does not enforce required counts. Distributions do not enforce totals, bounds, or required recipients. Invalid answers can reach engine callers or fail after the ask closes. Validate before completing the future and keep invalid asks open with an error. |
| Combat damage drops `overrideOrder` and `maySkip` | Generic allocations omit important interaction semantics and do not express lethal/trample constraints. Compare with pinned Forge's stock implementation and test these cases before claiming combat completeness. |
| `manipulateCardList` reduces everything to ordering all cards | Ignores the manipulable subset and top/bottom/anywhere flags. Some library manipulation decisions need richer representation. |
| `order` ignores sideboarding and remember-decision flags | Remember behavior is absent; sideboarding is outside the Commander target. |
| `showRevealedCards` / `hideRevealedCards` inherit no-ops | Temporary revealed cards can be missing from the UI. Generic reveal asks carry labels/IDs but not necessarily inspectable card details for cards outside serialized zones. |
| `canPickStackTargets` inherits false | Stack-target choices should use Forge's dialog fallback. Having a `stack` action alone does not enable direct stack targeting. |
| `showPromptMessageNoCancel` inherits a no-op | Some waiting/auto-pass messages will not appear. |
| Application-level GUI hooks return defaults or do nothing | `HeadlessGuiBase` does not route its own choice/input/card-list dialogs to WebSocket. Trace gameplay-relevant call sites before asserting comprehensive dialog coverage. |
| Game finish only marks dirty state | Winner/game-over data can render, but next-game decisions, restart, and complete lifecycle are not exposed. |

Auto-yield controls, phase-stop editing, and alpha strike are not exposed. Phase stops are read from shared stock Forge preferences. Preserve the bridge's avoidance of new preference writes.

## Recovery, errors, and privacy

- **Reconnect foundation:** outstanding asks are retained and included in snapshots, and `hello` forces a new snapshot. Socket handshake alone only marks dirty, so deduplication can suppress delivery to a new client; clients must send `hello`.
- **Client reconciliation gap:** the current browser page merges `state.asks` into an existing map instead of replacing the set. If it misses `askClosed` while disconnected, a closed ask can remain visible after reconnect. Godot should replace outstanding asks from each full snapshot, including clearing an obsolete active dialog.
- **No restart recovery:** engine state and pending futures are in memory. Restarting Java starts a new match, not a resumed session.
- **Stale actions:** unknown ask IDs are silently ignored; duplicates may complete an already completed future without a useful response. Actions have no game/revision context and can run against a later prompt. Unknown card IDs are silently ignored; malformed messages print exceptions without a structured client error.
- **Disconnect waits:** a decision can wait indefinitely while the client is absent. Reconnection can answer it, but there is no controlled cancellation or shutdown path. Do not auto-answer player decisions on a timeout.
- **Player visibility:** zone-card serialization uses `gui.mayView` and replaces unauthorized cards with `{id, hidden:true}`. That permission is based on the GUI's local-player set, not the connecting socket. This is suitable only as a single local player's UI connection, not isolated remote seats.
- **Visibility audit still needed:** option labels, stack source fields/text, combat defender text, commander names, logs, and face-down current-state fields are serialized through separate paths. Zone-card filtering alone does not prove absence of private-data leaks; use fixtures for face-down cards, reveals, and private choices. All sockets currently receive the local player's private information and decisions.

## Verification status

The previous `HANDOFF.md` reports live checks for Commander setup, startup notices, coin toss, mulligans, passing phases, cleanup discards, land play, and rejecting a second land. Those checks were not repeated here. Casting, mana payment, targeting, combat, ordering, completion, and next-game flow remain unverified as end-to-end Godot gameplay. Source coverage is not equivalent to successful play.

## Smallest integration path and completion checks

1. **Mock Godot prototype:** isolate transport from scenes; use a mock adapter with the existing snapshot and five ask shapes. Done when a readable three-player table supports inspection, movement/tapping, targeting visuals, stack, and every fallback kind. Label mock interaction clearly and verify screenshots. No bridge change is required for this phase.
2. **Local connection:** use the current `/ws` transport, send `hello`, render full snapshots, reconcile open asks by replacement, and disable submissions while disconnected. Initially start Java separately with `--opponents 2`; add managed process startup after the connection works. Done when the local player's hidden information and pending decisions survive disconnect/reconnect correctly.
3. **Minimum bridge hardening before playable validation:** validate answers before resolving decisions, report structured errors, and add protocol version, session/game identity, monotonic snapshot revision, and action/answer correlation. Bind actions to the relevant decision/revision and avoid stale object lookups. Capture real fixtures and test answer mapping, invalid/stale submissions, and reconciliation.
4. **Real gameplay slice:** play land, cast/pay for a basic creature, pass priority, and attack/block using Forge controller actions. Add missing reveal details, weak selection data, typed combat defenders, and damage-choice semantics where the slice exposes the need. Done when the same small match is playable entirely from Godot, with invalid input rejected and state correct after each action, including reconnect tests.
5. **Completeness and online:** cover complex prompts, Commander interactions, elimination and match lifecycle; then integrate host/join through pinned Forge netplay and test against a stock client of the same build. Multiple JSON sockets are not multiple player seats. Keep upstream source unchanged and Swing usable.

The mock prototype is the recommended next implementation task. Its visual direction should reconcile the new Godot handoff with the earlier Claude Design mockup requirement before committing to screen design. Menu priority versus match-first prototyping also remains a product decision; this audit does not silently rewrite the original handoff.
