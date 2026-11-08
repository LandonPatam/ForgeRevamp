# Mac handoff: online synchronization, combat and multiplayer starting rolls

Apply the changes in the accompanying `online-turn-sync.patch` to the Mac ForgeUI checkout, rebuild its Java bridge, and include the rebuilt classes in the Mac application. This handoff concerns ForgeUI's host-authoritative online mode, not stock Forge netplay.

## User report and resulting behavior

A joined player could see enabled phase buttons and an old turn prompt while another human or a bot was playing. Combat also needed redundant OK clicks after the defender had confirmed blockers.

Forge removes an input from a seat's queue before it necessarily replaces that seat's prompt. Its delayed `InputLockUI` presentation can leave the old buttons/message behind. The old bridge serialized that stored prompt without checking which input owned it, and validated OK against those stored buttons. The actual game view and the displayed prompt could therefore disagree. The bridge already broadcast game changes to all seats, and the existing online test passed before these changes; it did not check this input lifecycle or human-versus-human combat.

The fix binds prompt controls to their actual Forge input instance, invalidates all seats' snapshots when a human's input queue changes, masks stale controls/selections in waiting snapshots, and rejects actions against a removed, replaced, or not-yet-presented input. Turn/phase/active-player data continues to come from the shared Forge game view. Each viewer keeps its own hidden-card permissions and controller.

Default empty-stack priority after attacker/blocker declarations now auto-passes for the active player when Forge reports no legal action. Declaration inputs still require their owner's confirmation. Legal responses and explicitly enabled phase stops still pause. Payment, targeting, block legality, damage and resolution remain Forge decisions.

## Apply carefully

The repository already had extensive modified and untracked work. This patch was generated against a backup made at the start of this task, **not** against Git HEAD. It contains only this task's changes. Do not reset the checkout or replace whole files from another platform's older build.

From the Mac repository root, with the patch outside the checkout or at a known path:

```sh
git apply --check /path/to/online-turn-sync.patch
git apply /path/to/online-turn-sync.patch
```

If the check fails because the Mac branch differs, inspect and port the individual hunks. Preserve the Mac packaging/runtime paths and all existing online/mulligan/toss work. The zip also contains final source copies under `reference/` for comparison; these are references, not instructions to overwrite different Mac files.

Changed files:

- `bridge/src/main/java/forgeui/bridge/BridgeGuiGame.java`: input-queue notifications, presented-input identity, and no-response combat priority policy. Explicit stop overrides take precedence.
- `bridge/src/main/java/forgeui/bridge/GameStateJson.java`: capture one input per snapshot; disable stale prompt controls and selections; supply `InputLockUI` plus a waiting message for idle seats.
- `bridge/src/main/java/forgeui/bridge/BridgeMain.java`: retain the snapshot's input identity and require it to match the current presented input before dispatching input actions. Phase-stop settings, draw acknowledgments and concession keep their separate handling.
- `bridge/src/test/java/forgeui/bridge/BridgeChecks.java`: policy, explicit-stop and input-removal/replacement regressions. New EDT checks propagate assertions to the test thread; the headless GUI otherwise logs callback exceptions.
- `bridge/tools/online-turn-check.mjs`: portable real-engine tests for host/friend/bot combat, later turn agreement, inactive-seat rejection, four seats and preserved combat responses. Launches the actual Java executable from `java.home` so Windows launcher shims cannot orphan the test JVM; classpath uses the platform delimiter.
- `client-godot/tests/ScenarioIntegration.gd`: wait for the toss animation before accessing starting-player buttons. The old scenario harness mistook `CoinTossPanel` for `StartingPlayerPanel`.
- `client-godot/tests/LibraryImageChecks.gd` and `client-godot/tests/LiveAdapterChecks.gd`: perform local socket listen/accept calls outside assertions. Release exports omit assertion expressions, so these setup side effects previously vanished and broke the packaged smoke check with port-zero URLs.
- `docs/online-play.md` and `AGENTS.md`: document the input-identity rule and combat priority behavior.

There are no vendored `forge/` changes or new dependencies. Preserve the existing Forge patches and bridge-local mulligan overrides. Lobby protocol remains 4 and game protocol remains 2. All players should use the same updated build; the host's match JVM must contain the rebuilt bridge classes.

## Upgrade the Mac's single coin to multiplayer starting rolls

The Mac build currently shows a single coin at every table size. Port the existing Windows presentation so the animation uses the **total seated player count, including bots**:

| Table size | Animation | Outcome labels |
| --- | --- | --- |
| 2 players | Gold coin | Heads/tails, followed by the real winner's name |
| 3 players | Purple triangular prism die | Three rectangular outcome faces, one player's initial on each; triangular end caps are decorative |
| 4 players | Purple tetrahedral die | Four triangular outcome faces, one player's initial on each |

The included `starting-rolls.patch` upgrades `CoinTossPanel.gd` and `StartingPlayerChecks.gd` from the **single-coin implementation in the earlier `ForgeUI-online-coin-toss-mac.zip`** to the current implementation. This is separate from `online-turn-sync.patch`: applying the synchronization patch alone does not add the dice. From the Mac checkout root:

```sh
git apply --check /path/to/starting-rolls.patch
git apply /path/to/starting-rolls.patch
```

If the Mac files differ, port its hunks manually using the additional source references in this bundle:

- `reference/client-godot/scripts/ui/CoinTossPanel.gd`: `present()` builds the participant labels and winner index; `_draw_coin()` selects coin versus die; `_draw_die()` constructs, rotates, shades and draws the prism/tetrahedron. It uses Godot Control drawing and `Vector3`/`Basis` math, so no models, image assets, native plugins or Forward+ effects are required. Despite its filename, this panel handles all three table sizes.
- `reference/client-godot/tests/StartingPlayerChecks.gd`: `_die_variants()` exercises counts 2/3/4, every possible winner, repeated initials and rotated viewer seat order; `_shared_toss()` checks waiting, reconnection and session cleanup.
- `reference/client-godot/scripts/ui/Main.gd`: preserve `_present_coin_toss()`, `coin_toss_seen`, the animation `settled` callback, and modal/session cleanup. The current version matches the earlier coin handoff; merge only if the Mac integration has diverged.
- `reference/client-godot/scripts/bridge/LiveAdapter.gd`: preserve `normalize()` mapping of authoritative `winnerId` to the viewer's `winnerSeat`, and player `engineId`. This also matches the earlier coin handoff.
- `reference/client-godot/scripts/ui/StartingPlayerPanel.gd`: the actual portrait/name chooser remains separate from the animation, with the normal Forge player-selection submission.

The animation presents **Forge's existing authoritative result**; it never rolls a new winner or sends an automatic starting-player choice. `BridgeMain.observeStartingToss()` already publishes the shared `startingToss` identity, winner ID/name, coin face and choosing state, then first-player ID/name after the winner chooses. Dice land on that same winner rather than using the heads/tails field to invent an outcome. The existing bridge and protocol support this; the dice upgrade itself is frontend-only and requires a fresh Godot export, not an additional Java/protocol change.

Preserve these behaviors when porting:

- Start after the table is visible and the boot/zoom fade has completed. Spin for 1.8 seconds, then hold the named result until the 2.65-second animation completes.
- Use stable **engine player IDs** to assign die faces consistently across devices. `LiveAdapter` rotates players so the viewer is seat zero: normalized `id` is viewer-local, while `engineId` retains engine identity. Verify the Mac port with actual normalized snapshots as well as the rotated-array fixture; do not use viewer-local seat numbers as persistent face identity.
- Use the first letter of each player's name. Number repeated initials in stable order (`A1`, `A2`) and show the full-name key underneath the die.
- Only the actual winner proceeds from the animation to Forge's portrait/name chooser. Everyone else sees who won and who is choosing, without another acknowledgment click. Preserve Forge portraits without HP in the chooser.
- Repeated snapshots must not replay the animation. Preserve reconnection messaging; later-turn reconnects skip the old toss. Game/session completion cancels any unfinished animation and clears its presentation state.
- Package the updated Godot scripts/resources into the Mac app. Replacing only Java classes will leave its old single-coin presentation unchanged.

Validate in the Mac's rendered visual suite (the existing `--visual-checks=<capture-directory>` mode runs `StartingPlayerChecks`) and its exported smoke check. Inspect `starting-roll-2-player-motion.png`, `starting-roll-3-player-motion.png`, `starting-roll-4-player-motion.png` and each `starting-roll-<count>-player-result-<winner>.png`. Check all winners, repeated initials, three humans plus a bot, and two devices with different local seat ordering. The Windows suite previously passed these draw/behavior checks; the Mac export and cross-device rendering still need validation after porting.

## Build and validate on macOS

Use JDK 17, Node 22 or newer, and the existing Forge dependencies/assets. From the repository root:

```sh
mvn -f bridge/pom.xml -DskipTests package
java -cp 'bridge/target/test-classes:bridge/target/classes:bridge/target/lib/*' forgeui.bridge.BridgeChecks
node bridge/tools/online-turn-check.mjs
node bridge/tools/online-turn-check.mjs --four
node bridge/tools/online-turn-check.mjs --response
node bridge/tools/online-check.mjs
```

Use the checkout's bundled Maven if `mvn` is not on PATH. Existing Forge jars must already be installed, as for the previous Mac build. Maven incremental compilation has sometimes reported up-to-date classes incorrectly in this project. If necessary, explicitly compile before packaging:

```sh
find bridge/src/main/java -name '*.java' > /tmp/forgeui-bridge-sources.txt
javac -encoding UTF-8 -cp 'bridge/target/classes:bridge/target/lib/*' -d bridge/target/classes @/tmp/forgeui-bridge-sources.txt
javac -encoding UTF-8 -cp 'bridge/target/classes:bridge/target/lib/*' -d bridge/target/test-classes bridge/src/test/java/forgeui/bridge/BridgeChecks.java
mvn -f bridge/pom.xml -DskipTests package
```

Expected checks: 289 bridge assertions; 8 checks in each normal/four-seat turn suite; 9 in the response suite; 61 in the existing online lobby/lifecycle suite. The response fixture gives the attacker a Forest and Giant Growth: priority must remain after attackers AND blockers. The other fixtures must resolve the block after one blocker confirmation and advance through both humans' turns and the bot's without idle-seat priority clicks.

The Windows Godot combat scenario also passed headless and rendered, including its existing exact game-state assertions. `client-godot/tools/live-check.mjs` currently has Windows-specific executable paths; use the Mac project's equivalent launcher, or adapt those launch paths before running `--scenario=combat --render`. Inspect the prepared board, damage-allocation and result captures.

Run the exported Mac application's `--headless -- --smoke` check too. The socket setup changes above are needed in release exports as well as editor tests; keep them in the Mac bundle's test scripts.

Rebuild/repackage the Mac application with its existing Mac packaging process. Replace the bundled bridge **classes**, not only its jar: exported ForgeUI launches `service/classes` ahead of `service/lib/*`. Include nested classes for all changed Java classes. Keep the bridge-local `forge/game/mulligan/` overrides in the bundle and keep JDK 17 runtime/native dependencies appropriate for the Mac architecture. Do not copy the Windows runtime or executable. Check that packaged class hashes match the newly built classes.

Close and relaunch the updated applications/services and start a fresh online match; an already-running JVM retains the old implementation. Manually verify host + joined human + bot, and then three humans + bot: every device follows the same active player and phase, the defender alone confirms its blocker choice, response cards still get a window, and an idle seat has disabled OK/Cancel with a waiting message. Normal packet latency can briefly separate snapshot arrival times; a client must converge on the latest authoritative state without replaying actions.

## Validation limits

Automated online tests used separate authenticated WebSocket seats over loopback on Windows with real Forge. The Godot combat scenario used the real bridge. A cross-machine Windows/Mac game and the Mac export still need validation on the Mac; no Mac binary was produced here. No user decks, caches or pre-existing processes were removed or stopped.

The rebuilt Windows export passed its packaged smoke check after the release-test setup fixes. All 15 packaged class files belonging to `BridgeGuiGame`, `BridgeMain` and `GameStateJson` matched the rebuilt/tested bridge by SHA-256.
