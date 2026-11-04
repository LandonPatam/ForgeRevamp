# Online play

One player hosts; up to three friends join by typing the host's IP. Everyone runs the matching build of ForgeUI for their operating system. macOS and Windows use the same lobby and game protocols; neither side sends local filesystem paths to the other.
Regular Forge cannot join: this does not use Forge's netplay protocol, and the `forge/` netplay patches are unrelated to it.

## Using it

All of it lives in the ONLINE section at the bottom of the match settings screen.

- **Host:** press HOST SESSION and read the IP to your friends. Every seat the roster leaves empty is open, and a player who connects takes one with nothing for the host to do. Remove a bot to open its seat. Save, then press PLAY to mark yourself ready.
- **Join:** type the host's IP and press JOIN SESSION. You play the disk selected on the carousel; changing it updates the lobby. Save settings and press your own PLAY key to mark yourself ready.
- The host launches automatically once every seated human has pressed PLAY. Bots are ready automatically; empty seats do not need confirmation. The lobby shows readiness. Changing a deck, host settings or the seated players clears readiness, so everyone confirms the new setup. The service refuses a start while any human is unready.

The default port is TCP 36743 (Forge's `NET_PORT` preference), and the IP alone is enough when it is in use. `IP:port` also works.

## Connectivity

The host's settings screen shows both addresses. Friends on the same network use the "same network" one; others use the public one, which needs the port reachable:

- UPnP asks the router to forward the port automatically, and the screen says whether that worked.
- Otherwise forward TCP 36743 to the host's LAN address, or use a VPN such as Tailscale or ZeroTier and share that address.
- Windows Firewall asks about `java.exe` the first time someone hosts. Allow it.
- Carrier-grade NAT can make a public IP unreachable whatever the router does; a VPN is the way round it.

Hosting asks `checkip.amazonaws.com` for the public IP, the same lookup Forge makes. The router mapping is removed when hosting or the match stops; if the service is force-killed the mapping can remain until the router forgets it.

## How it works

The host's machine runs the one real game. Forge's rules, hidden information and undo all stay there.

```
Host's app -- loopback --> LibraryMain: OnlineLobby holds port 36743 until PLAY
                       --> BridgeMain (match JVM): host seat on loopback, online seats on port 36743
Friend's app -- port 36743 --> OnlineLobby, then that friend's own seat in BridgeMain
```

1. `OnlineLobby` (library service) owns the port before the match. Friends send `join` with their profile and the bytes of their deck file; the host validates the deck on its own Forge. Rosters and seats are pushed to joined players and polled by the host's app (`lobby.*` operations).
2. On PLAY, `MatchService` has the lobby issue each player a random seat token and release the port, then starts `BridgeMain` with those seats in its setup file. It binds the same port, so forwarding keeps working.
3. `BridgeMain` holds one `Seat` per human: its own `BridgeGuiGame`, `PlayerControllerHuman`, revision and visibility-filtered snapshots. Friends present their token as the first message (`{"type":"auth","token":...}`), then speak the normal game protocol (`protocol.md`). Godot's `LiveAdapter` is the same as for a local game plus that one message, so every table feature works unchanged for joined players.

Each seat keeps its own phase stops. By default, a player without a legal action automatically passes empty-stack priority during somebody else's turn. Legal instant/activated actions still get their response windows, and explicit phase stops still work. Stack responses, targeting, payment, blocking and other required decisions remain controlled by Forge. The host has no special authority to approve another player's phase progression.

Prompt controls belong to a specific Forge input instance. Each seat observes its input queue so entering or leaving a decision invalidates every seat's snapshots. Waiting snapshots replace old buttons, selections and declaration text with disabled controls and a waiting message. Actions must match both the published revision and the still-current, presented input; a delayed click cannot approve a replacement input. The shared Forge game view continues to supply everyone's turn, active player and phase, independently of which seat currently has a decision.

After attacker and blocker declarations, default empty-stack priority also passes automatically for the active player when Forge finds no playable response. The declaration itself still needs its owner's confirmation. A legal combat trick/activation or an explicitly enabled phase stop retains the priority window, so combat needs extra clicks only when there is a response opportunity or a requested stop.

Lobby protocol version 4 includes readiness, opening/session lifecycle and the shared starting-toss presentation. Clients send `{ "type": "ready", "ready": true }`; the local host uses `lobby.ready`, per-human `ready` roster flags, and `hostReady`/`allReady` host status. Deck and roster changes invalidate readiness. Both Java and Godot must use version 4; older builds are refused at join. The game protocol still uses its session/revision/request identities at version 2.

### Loading and opening hands

- `tableReady` is shared across seats once Forge reaches its first real input or blocking question. Every connected device can reveal the table while the selected player answers; another seat's acknowledgment never gates loading.
- All seats receive the same `startingToss` from Forge's actual starting-coin event: toss identity, winner, face and whether the winner is choosing. The game-start event supplies the selected first player. The observer is attached during controller registration, before the game thread starts, so the toss cannot be missed. No client rolls its own result.
- A short starting-roll animation begins after each device's table reveal: a coin for two players, a triangular prism die for three, or a tetrahedral die for four. Dice faces carry each player's first initial, with a numbered suffix for repeated initials and a full-name key. Stable engine-ID order keeps the face assignments identical across viewers' rotated seat lists. The die lands on Forge's actual winner; it never generates another result. The animation shows the winner and, for other seats, a named waiting message until the winner chooses who starts. Only the winner sees the actual starting-player controls after the animation. Ordinary snapshots do not replay it; reconnecting to a later turn skips the old toss, and session cleanup cancels it. Animation timing is local presentation, so device loading times can differ; Forge owns the result and the decision throughout.
- Online matches install `OnlineOpeningHands` through a bridge-local compatibility override of `forge.game.mulligan.MulliganService` (alongside the existing London override, ahead of the Forge JARs on the classpath). It installs each human's actual Forge Keep/Mulligan input before waiting. Answer waiters collect choices only; all keeps, bottom choices, shuffles and redraws remain on the single Forge game thread. A mulligan round redraws in turn order after everyone has chosen.
- Each seat gets `openingHandComplete` only after Forge accepts that player's Keep and any required London bottom cards. The opening overlay can close and show that player's final hand while other humans are still choosing, even if the seat has no priority until a later turn. Unconfirmed hands remain gated from the battlefield.

### Exposure

Only `BridgeServer.exposed` listens beyond loopback. It serves no files, refuses browser origins and limits message size. The library service, deck library and host seat stay on loopback.

- **Lobby:** anyone who can reach the port can take an open seat. There is no password; the host can remove players. Unintroduced connections are dropped after 15 s, with at most 16 waiting.
- **Match:** nothing is sent before a valid token (256 random bits, constant-time compare), and a connection without one is dropped after 10 s. A seat's messages only reach its own controller.

Deck names and player names from joined players are displayed; deck files are parsed by Forge and stored in a temporary directory removed with the session.

### Disconnects

- A dropped player reconnects automatically with their token; everyone is told who they are waiting for. A newer connection replaces an older one.
- The game waits for an absent player's decisions. After 5 minutes absent (`ABSENT_LIMIT_NANOS`), or at once when they choose Leave game, the seat concedes. Forge's concede does not release a waiting prompt unless the game ends, so `releaseAbandonedInput` clears them, and `BridgeProtocol.fallbackAnswer` answers decisions.
- The host's End Game or quit asks its owned child over loopback to send the session-scoped `sessionEnded` event before exiting. This is necessary on Windows, where force-terminating Java skips shutdown hooks. Only the host's local seat can request shutdown; remote seats are refused. If the child is unresponsive, the service still stops its owned process.
- The child briefly waits for notified clients to close their sockets before teardown; Godot can discard unread payloads when a close handshake finishes. Clients drain available frames before deciding to reconnect and flush their own close after accepting the terminal notice.
- A joined client treats `sessionEnded` as terminal: stops retries, clears outstanding submissions and the seat token, closes dialogs, and follows the normal return-home/session-disk wipe automatically, including when parked or still loading. It does not remain at the table or in a stale lobby. A joined player's own End Game still leaves only their seat.
- A lost connection without an explicit ending retries for up to 180 seconds, including initial match connection. If the host never returns, the client closes the session rather than retrying indefinitely. Short interruptions still reconnect to the same seat.

## Known limits

- A physical Mac-to-Windows game with lobby protocol version 4, and a connection from another internet connection, have not been verified after this update. Automated checks exercise native Apple Silicon and the bundled Intel runtime under Rosetta, including connecting to this Mac’s own LAN address; this does not test a remote machine’s firewall or the router from outside.
- `OnlineLobby.NET_VERSION` only catches protocol changes when it is bumped. Different builds with the same number, or different card data, are not detected. Bump it when lobby or seat messages change.
- There is no spectating, chat, or rejoining the lobby after the host stops hosting. A session is one match.
- If the match process fails to start after the lobby has closed, joined players wait until their boot times out, and everyone must reconnect to a new session.
- A host who sets their game aside still holds up the table when a decision is theirs.

## Checks

- `node bridge/tools/online-check.mjs`: real service, lobby, kicking/cancelling, full-roster rejection, Windows CRLF/UTF-8 deck changes, accepted-deck preservation, four-player seats, tokens, hidden hands, reconnect and leaving, including mid-decision. Runs with discovery off, so it contacts no router or address service.
- `node bridge/tools/online-turn-check.mjs`: real host/friend/bot combat, inactive-seat button rejection and turn/phase agreement through later turns. Add `--four` for three humans and a bot, or `--response` to verify affordable combat tricks retain priority after attackers and blockers. Uses temporary fixtures and stops only its own JVM.
- `node client-godot/tools/app-check.mjs --render`: `online_join_check` runs the joining path through the real application; the settings section is captured as `app-settings-online-*.png`.

For the Mac payload, run `node bridge/tools/online-check.mjs --mac-app dist/ForgeUI-mac-optimized/ForgeUI.app --arch arm64`; repeat with `--arch x86_64` on an Intel Mac or with Rosetta. Add `--host-address <this-Mac-LAN-IPv4>` to exercise the non-loopback listener. The runtime, service classes and Forge assets come from that app; test libraries and logs are isolated. The source-mode runner now uses the platform classpath separator on Windows and macOS.

`node client-godot/tools/online-app-check.mjs` tests the exported Mac application's real online joining, seat token, disk/table reveal and Leave cleanup with its bundled Java payload. Set `FORGE_EXPORTED_EXE` to check a different exported Mac app; `--intel` runs both the game and Java as x86_64. It reuses `ApplicationIntegration.online_join_check` for both hosting and joining, including physical PLAY readiness and automatic host launch, and does not contact a router. `--source` checks the local Mac sources before packaging. `--peer <Windows-LAN-IP>` runs the live joining check against a host running the matching lobby protocol version 4 build.

Rejected lobby configuration is validated before replacing the accepted roster. Received deck changes are validated in a separate temporary file; a rejected replacement cannot overwrite the accepted deck. Successful changes remove the previous copy, and session cleanup removes all received decks. These fixes are shared by Windows and macOS builds and do not change the wire protocol.

## Joining-player restart recovery

A joining app saves its seat before loading and updates the match identity and
public session-disk metadata from authoritative snapshots. After an app crash or
restart, its ONLINE SESSION disk offers CLICK TO REJOIN. Click it to insert the
disk and connect a fresh adapter to the same engine seat. PLAY and a second table
remain blocked until that disk is resumed or forgotten. No queued action or
answer is restored or replayed, and a different match identity is rejected.

The host engine must still be running. Disconnected remote seats are held for up
to five minutes before concession; client retries stop after 180 seconds. This
does not recover solo games, host crashes, exited engines or expired seats.

Only the endpoint, seat credential, match UUID, deck ID/name and public disk
metadata are stored in `user://online-session.cfg`, using a temporary file and
atomic rename. Never share that credential file. No hands, full snapshots,
pending actions, answers or revision/request counters are saved. Leave, confirmed
Quit from a connected/parked remote game, game over, host shutdown and terminal
reconnect failure remove it. Closing the app with an idle recovery disk preserves
it. Forget session removes only local recovery data; the host may continue to
wait until the seat expires.

`RemoteSessionChecks` verifies replacement saves on the current platform.
`ApplicationIntegration.online_join_check` loses the joining scene and memory
without Leave, restores the file/disk and rejoins the original seat through
insertion, then verifies terminal host cleanup and reverse-role readiness.
Run `node client-godot/tools/online-app-check.mjs --source` for this focused Mac
flow, or the rendered full application suite. This simulated scene loss does not
kill the Godot process. Manual acceptance: force-quit only the joining app, keep
the host running, reopen and rejoin before five minutes; check the same hand,
board, seat and decision, then check Leave, Forget session and an unavailable
host. `node bridge/tools/solo-phase-check.mjs` separately checks real bot phase
waits at M1/M2 on two turns each and DA/DB when observed.
