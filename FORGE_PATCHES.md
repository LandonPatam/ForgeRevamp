# Local patches to upstream Forge

`forge/` is the upstream Forge checkout pinned by `FORGE_COMMIT`
(`84f4983c1ce872932cf9a26a8bd54ca00056aae9`). The changes below are applied on top of it,
**uncommitted** in `forge/`, so `git -C forge status` / `git -C forge diff` always show exactly
what differs from upstream. The same changes are saved as a patch:
[`forge-patches/netplay-fixes.patch`](forge-patches/netplay-fixes.patch).

## 2026-10-29: online play stability ("game stuck on a turn")

Found from the host's network logs (`%APPDATA%\Forge\networklogs`, sessions of 10-19 and 10-21)
and a review of Forge's netplay code. Everything is in Forge's own online mode; ForgeUI's local
bridge does not use these paths.

| # | Problem | Evidence | Fix |
|---|---|---|---|
| 1 | A reconnecting player is refused ("seat unavailable") while the server still holds their seat on the old, silently dead connection (up to the 45 s heartbeat timeout). The client takes that as final; the seat then sits empty for 5 min until the AI takes over. | 10-21 log: CP refused four times in 37 s, game abandoned. | Server: a login for a seated player from the **same IP** retires the stale connection and reconnects immediately. From another IP, the server answers "seat still held" and the client keeps retrying until the old connection times out. The retired connection is told its seat moved, so a second copy of the game cannot take it straight back. |
| 2 | After a reconnect, a client can show a card the server no longer has; every click on it is silently dropped. | 10-19 log: PP clicked card 327 seven times during declare blockers, server "not found in any zone"; PP could not block and died. | Server: when a remote click is rejected and the card is not in the game, send that player a full fresh state and re-show the prompt (at most once per 3 s). |
| 3 | The server keeps sending to a connection whose pipeline is gone, with one error per message. | 10-21 log: 191 x "No encoder in pipeline for PP". | Sends to a closed connection are dropped quietly (logged once); a question asked on one returns "disconnected" instead of hanging or answering null. |
| 4 | A player who disconnects while being asked something (order blockers/triggers, choose cards, divide damage...) answers `null`; several callers then throw and the **game thread dies**, freezing the match for everyone. | Code: `IGuiGame.order(...).ordered()`, `PlayerControllerHuman` getChoices loop and divided damage. | The question is not answered by a disconnect: the game waits for the reconnect resync and asks again. If the AI takes over (timeout or `/skipreconnect`) or the server stops, it takes a safe default (keep given order, first N choices, even split, default yes/no) and never null. Null guards added at the two crash sites. |
| 5 | Client UI freezes forever if the connection drops while it waits on the host (e.g. ability description on hover). | Code: client reply wait had no timeout and was never cancelled. | Client cancels pending requests on disconnect and never waits more than 15 s. |
| 6 | A pending reply could be lost on reconnect: the reply pool was replaced without releasing threads still waiting on the old one; releasing could also race a thread between registering and waiting (`NullPointerException`). | Code review; the race was caught by the new unit test. | Old pool is released on swap; release completes entries without removing them. |
| 7 | When the host hit an error answering a client's request, a modal error dialog was shown before the reply was sent, so the client waited until the host clicked OK. | Code: `GameProtocolHandler`. | Reply first; show the dialog afterwards without blocking. |
| 8 | The disconnect handler threw if no host lobby listener was set (headless hosts), skipping the rest of its cleanup. | Found by the disconnect test. Desktop hosts always set a listener, so this did not affect your games. | Null check, as elsewhere in the file. |

### Behavior changes to know about
- While a player is disconnected mid-decision, the game now **waits** for them (the existing 5-minute reconnect window; the host can still `/skipreconnect` or `/skiptimeout`) instead of continuing with an automatic answer.
- Seat reclaim trusts the same IP address as the dead connection, like the existing username-only reconnect it extends. Two friends behind one router who use the **same username** could take each other's seat; use different names.
- Not identified: *why* the client in #2 ended up with a card the server did not have. #2 recovers from it rather than preventing it.

### Files
- `forge-gui/.../gamemodes/net/ReplyPool.java` — `DISCONNECTED` marker, `abortForDisconnect()`, timed `get`, completion no longer removes waiting entries.
- `forge-gui/.../gamemodes/net/GameProtocolSender.java` — `sendAndWaitOrDisconnect`.
- `forge-gui/.../gamemodes/net/ProtocolGuiGame.java` — wait-for-reconnect and re-ask, `notifyResynced`/`abandon`, safe defaults, `resyncClientView`.
- `forge-gui/.../gamemodes/net/GameProtocolHandler.java` — reply before error dialog.
- `forge-gui/.../gamemodes/net/server/RemoteClient.java` — closed-channel handling, release old pool on swap.
- `forge-gui/.../gamemodes/net/server/FServerManager.java` — seat reclaim, pause-before-release on disconnect, resync/abandon notifications, release on server stop.
- `forge-gui/.../gamemodes/net/event/SeatLostEvent.java` — `seatStillHeld` flag (wire-compatible: `serialVersionUID` unchanged).
- `forge-gui/.../gamemodes/net/client/FGameClient.java` — retry on held seat, stand down when replaced, cancel/timeout pending requests.
- `forge-gui/.../player/PlayerControllerHuman.java` — stale-click refresh, two null guards.
- New tests (`forge-gui-desktop/src/test/java/forge/`): `gamemodes/net/NetplayResilienceTest`, `net/NetplaySeatReclaimTest`, `net/embedded/StaleSelectionResyncTest`, `net/NetplayDisconnectChaosTest`.
- Test helpers: `net/HeadlessNetworkGuiGame` (`answerHook`, called before each answer the host waits on) and `net/HeadlessNetworkClient` (`thinkTimeMs`, `getGui()`, prompt hook).

### Tests
- `NetplayResilienceTest` — unit level: a question dropped by a disconnect is asked again after the resync (not defaulted); abandoned questions get safe non-null defaults; reply-pool semantics; the new seat-lost flag survives the wire filter.
- `NetplaySeatReclaimTest` — real server: a connection goes silent, the player rejoins under the same name and gets the seat at once; the replaced copy stands down.
- `StaleSelectionResyncTest` — real game: a click on a card the game does not have sends one full refresh (once per burst).
- `NetplayDisconnectChaosTest` — **player vs player vs player**: host seat plus two remote friends who stay human and answer over the network (Forge's own harness swaps remote players to a server-side AI, so none of its tests ever waited on a remote player). At a human pace, it drops the friends 20+ times: abrupt close, silent drop (server must time it out), restart under the same name, rapid flapping, and drops exactly inside a dialog the host is blocked on, a yes/no or discard prompt, or a priority prompt. Fails on a stall while everyone is connected, a client that does not recover, a reconnected view that disagrees with the server (life, hand, library, graveyard, exile, battlefield), or a game that does not finish. Run it in its own Maven invocation: it shortens the server heartbeat to 5 s before the server class loads.

Against the **original** Forge jar, the three end-to-end tests fail the way the logged games did: the restarted player is refused ("seat unavailable"), the old copy never stands down and the player never recovers; the seat is not reclaimed; stale clicks get no refresh. Against the patched build they pass.

### Verification
`../.tools/apache-maven-3.9.9/bin/mvn -o -pl forge-gui-desktop test -Dtest='Netplay*,StaleSelectionResyncTest,Wire*,ProtocolGuiGame*,DeltaSyncUnitTest,LobbySlotAuthorizationTest,AbuseLimitsTest,NetworkPlayIntegrationTest'`
(from `forge/`, after installing `forge-gui`; about 6 minutes; add `-Drun.stress.tests=true` for Forge's multi-game stress tests, which take over an hour and never disconnect anyone).
Note: `-pl forge-gui-desktop` tests against the **installed** `forge-gui` jar in `~/.m2`, so install first.

## Building

Changes in `forge-gui` must be installed for the bridge and the desktop app to see them:

```sh
cd forge
../.tools/apache-maven-3.9.9/bin/mvn -o -DskipTests -pl forge-gui flatten:flatten install
cd ../bridge && ../.tools/apache-maven-3.9.9/bin/mvn -o -DskipTests package
```

**Online play needs everyone on a patched Forge desktop build.** Host-side fixes (#1–4, 6, 7)
need a patched host; client-side fixes (#1 retry, #5) need patched clients. Patched and stock
builds can still connect to each other. ForgeUI's own online mode does not use Forge's netplay
and cannot connect to Forge desktop; see `docs/online-play.md`.

## Reverting

```sh
git -C forge apply -R ../forge-patches/netplay-fixes.patch   # or: git -C forge checkout -- . && git -C forge clean -n (review) 
```
Then restore the original installed jars from `backups/forge-netplay-2026-10-29/m2-original/`
into `~/.m2/repository/forge/forge-gui/2.0.16-SNAPSHOT/` (and `forge-gui-desktop`), or simply
re-run the install command above, and rebuild the bridge.

## Updating Forge

After changing `FORGE_COMMIT` and checking out the new upstream commit, re-apply with
`git -C forge apply --3way ../forge-patches/netplay-fixes.patch`, resolve any conflicts, then
rebuild and re-run the tests above. Check whether upstream fixed any of these first.
