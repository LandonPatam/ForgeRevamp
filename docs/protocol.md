# Local bridge protocol v2

The Godot client should use `ws://127.0.0.1:7777/ws`. This is one local player's trusted UI connection: every loopback socket shares that player's state and controller. Online seats use this same protocol on a separate token-gated port; see `online-play.md`. Browser Origin headers are accepted only from the local test page's `127.0.0.1`/`localhost` HTTP origin and actual port. Native clients can omit Origin. This check is not authentication against other local programs.

## Connection and state

The handshake supplies the latest snapshot when available. Send `{ "type": "hello" }` to request another snapshot at any time. Initialization can return `loading: true`; disable gameplay until a non-loading state arrives.

All server messages carry `protocolVersion: 2`, `sessionId` (a UUID for this bridge process), and `revision` (a monotonic change counter). The current implementation has one match per process, so a session also identifies that match. State revisions can skip numbers. The counter is not a count of frames or an atomic engine transaction ID.

Full `state` snapshots retain the original fields documented in `archive/HANDOFF.md`: `me`, `game`, `players`, `stack`, `combat`, `prompt`, `log`, and `asks`. New fields:

- `targetedEffects`: up to 32 retained public opposing cast/ability notices targeting this local player or their cards. Each has a monotonic `id`, `stackId`, `controller`, `controllerName`, `ability`, a source card descriptor, and `targets` (`kind`, `id`, `name`). Source/target data is frozen at the cast event so quick resolution cannot erase it. Hidden sources remain id-only and face-down targets use a generic name. Clients deduplicate by notice ID within the session; on first connection skip resolved historical notices and show ongoing ones. These are informational notifications, not blocking asks or proof of successful damage/destruction.

- `autoPassStackId`: stack-instance ID of the actual stack top when `StackInteractionPolicy` lets this seat pass it automatically, or `-1`. Godot's automatic-priority preference uses this only while the current input is enabled `InputPassPriority`, there are no asks/pending draws, and the connection is synchronized. Damage/targeting, subabilities and non-routine effects do not qualify. It is not a direct-resolution action: the client sends the normal revision-checked `ok`, then Forge handles other players and resolution. Empty-stack play windows remain under player control.

- `game.phaseKey`: stable Forge enum name (for example `MAIN1` or `COMBAT_DECLARE_ATTACKERS`), independent of the localized `game.phase` display text.
- `phaseStops`: objects keyed by engine player ID, containing phase enum keys and boolean stop-enabled values. These are the local human's priority-stop settings for each turn owner, read from Forge's active controller; they do not disable rules phases.
- `pendingDraws`: local card IDs already drawn by Forge during the draw step, awaiting the UI's manual draw gesture. The bridge observes original engine events; it does not execute another draw or replay events into Forge. Hide these cards from the displayed hand until acknowledged. Other controller actions are blocked while the set is nonempty; generic blocking decisions can still be answered. Empty means no draw is due, including skipped/replaced draws.
- `undoPending`: the bridge is completing an authorized land return through Forge undo checkpoints. Disable gameplay until false, even if the initial request has been acknowledged. Reconnect/hello requests remain available; do not resubmit the return.
- `prompt.inputKind`: current Forge input class name, used to distinguish a settled priority prompt from payment/selection while rendering a pending card play.
- Visible cards include `availableActions.returnToHand`. It is true only for the most recent direct local land play, while the card is on the battlefield and Forge's `canUndoLastAction()` allows reversal. Review clicks and rejected plays preserve the candidate. A selected local spell's provisional Hand/Command-to-Stack move and rollback do not consume this permission; a completed cast does. Actual mana changes, tapping, combat declarations, life/counter/damage changes, other zone changes, information barriers, undo restoration, and turn/phase changes invalidate it. A land selection becomes a candidate only after Forge puts it on the battlefield and permits undo. Hidden stubs gain no fields.
- Visible cards also include `availableActions.undoTap`. True authorizes undo of that card's latest unused mana activation, including its mana/costs, at the exact recorded priority checkpoint. This is not permission to set its tapped state. Missing means false; hidden stubs gain no fields.

- `revealed`: card objects explicitly shown for the current prompt by Forge's reveal callback. Clear them when the array becomes empty.
- Visible zone cards include `weakSelection`: 0 for none, 1 for actionable, potentially higher for Forge's suggested mana selections. Hidden cards remain exactly `{id, hidden:true}`.
- Combat entries retain the display string `defender` and add `defenderId` and `defenderKind` (`player` or `card`) when present.
- Card options in generic asks include a nested `card` object, visibility-filtered through the local GUI's permission check, for inspection outside ordinary zones. A hidden option card remains an ID-only stub. This does not replace temporary reveal callbacks.

Replace the entire outstanding-decision set with `state.asks`; do not merge it. Close dialogs absent from the new snapshot. Reconcile card nodes by card instance ID, not name or image key. Separate player, card, and stack namespaces. Clear all cached state when `sessionId` changes. Never automatically replay a click after reconnect or a stale-state error.

Incremental `ask`, `askClosed`, and `flash` messages remain supported. `askClosed.id` removes that decision. An `ask` blocks its engine caller until a valid answer arrives; disconnect leaves the decision pending for reconnection. There is no timeout that chooses for the user.

## Requests and responses

`hello` requires no metadata. Every action and answer requires:

```json
{
  "type": "action",
  "protocolVersion": 2,
  "sessionId": "UUID-from-state",
  "requestId": "client-generated-string",
  "revision": 42,
  "action": "card",
  "id": 123
}
```

`requestId` must be a nonblank string of at most 128 characters; clients should use a new ID per submission. IDs correlate replies but are not an idempotent replay cache.

Actions require the latest snapshot revision. The bridge checks it again on the EDT and consumes the revision before dispatch, so two queued clicks against the same snapshot cannot both run. Wait for a newer snapshot before sending the next action. Revision checks detect changes reported through the bridge; snapshot reads still occur outside the engine thread and are not fully atomic.

Supported actions are `ok`, `cancel`, `card`, `player`, `stack`, `mana`, `undo`, and `concede`. Card/player/stack IDs must exist in the currently published snapshot's lookup maps. Button actions must be enabled. Mana IDs are W=1, U=2, B=4, R=8, G=16, C=0. Player portraits remain clickable even with no advertised target, for Forge's coin toss input. Pending blocking asks must be answered before controller actions. Do not offer a free-standing tap-state setter: clicks go to Forge's contextual controller.

`phase_stop` adds the turn owner's engine player `id`, a stable phase enum `phase`, and boolean `enabled` to the action envelope. It updates Forge through `YieldUpdate.SkipPhase` for that player/phase. It is a session-scoped setting: the session is checked, but intervening gameplay revisions do not reject the edit. The player must still exist, the phase must be valid (excluding UNTAP), and enabled must be a boolean. Settings may change with a pending draw or blocking decision; an in-progress land return still blocks them. The response is acknowledged and a newer snapshot confirms the setting. UI controls use the authoritative per-player values after confirmation; reconnect preserves them without replay. These edits do not write global Forge preferences.

`attack` adds an attacker card `id` and defending player `target` (both engine IDs) to the normal action envelope. Godot stages the attacker and pointer arrow locally; choosing the avatar sends one request. The bridge requires the human's `InputAttack`, a controlled battlefield creature, a current combat defender, and Forge's `CombatUtil.canAttack` approval before consuming the revision. On the EDT it selects that defender and then the attacker through Forge's controller. Re-selecting the same attacker/defender pair preserves the declaration; selecting another defender retargets it. The gesture currently supports player avatars. Local arrow cancellation sends no action, particularly no `cancel` that could trigger Alpha Strike. Generic `player`/`card` actions remain contextual selections for other engine inputs.

`undo_card` with a card instance `id` is the card-specific drag-to-hand action. The bridge revalidates `availableActions.returnToHand` on the EDT, then invokes Forge's `tryUndoLastAction()`; it never moves the card directly. Forge records checkpoints for canceled casts too. The bridge remembers the land's checkpoint depth and, while `undoPending`, advances only after each prior restore lowers the depth and Forge permits another undo. It stops when that land reaches Hand, the target depth is reached, the phase changes, or a ten-second deadline expires. Other controller actions are blocked during this sequence. Preserving the older land across a spell attempt requires Forge's Free undo mode and retained history; single-step/capped history is handled conservatively. Invalid candidates return `invalid_action`, protecting against undoing a different action. General `undo` remains available separately. The current card-specific capability conservatively covers direct land plays; it does not infer an arbitrary spell rollback.

`draw_ack` with an ID from `pendingDraws` consumes the usual action envelope/revision and removes that presentation gate. It never calls an engine draw method. This set lives on the bridge and survives client reconnects. The Godot library gesture sends it and places the newly visible card at the selected hand slot. Attempted gameplay before acknowledgement cues the library in white without sending another engine action.

`pass_turn` uses the usual action envelope and requires this seat's current `InputPassPriority`. It enables Forge's own end-of-turn yield (`autoPassUntilEndOfTurn`) and passes priority. Required declarations, targets, payments and choices still prompt; the bridge sets the yield to stop when the seat is attacked, targeted or facing mass removal, not for every opposing spell. The Space key sends it; Q presses the primary button and D takes a pending draw.

`undo_tap {id}` uses the usual action envelope, current session/revision, and EDT validation. It requires `mayUndoTap` for that exact tapped battlefield card, the recorded phase/history depth, and Forge's `canUndoLastAction()`, then calls `tryUndoLastAction()`. The bridge tracks the actual chosen mana ability with a source tap cost, observed mana production, and completion at the next priority checkpoint. Other game mutations and mana spending close this window; non-mana ability/combat taps and older activations are not inferred as reversible. A successful undo restores the whole activation, so generated mana is removed too. Clicking an unauthorized tapped card retains normal contextual Forge selection, allowing legitimate abilities usable while tapped without granting a free untap. A forged/stale `undo_tap` is rejected before dispatch.

Godot's prepaid casting flow uses only existing contextual `card`, `mana`, and `cancel` actions, individually revision-gated. After selecting a hand/command spell at a priority prompt, it asks Forge to spend floating pool mana one unit at a time. Forge evaluates colors, restrictions, and the final cost. If the current cancellable payment cannot be completed from that pool, Godot sends Cancel; it never selects Auto or taps extra sources. Mana production choices and other generic engine decisions remain explicit. Alternate costs, complex mana restrictions, and mandatory payments need broader live coverage. Disconnect stops automation; no casting request is replayed.

Answers use the same envelope with `type: "answer"`, decision `id`, and `value`. A snapshot revision is not required for answers: the session and still-open decision ID are their context, so unrelated updates do not invalidate a dialog.

| Kind | Answer | Server checks |
| --- | --- | --- |
| `choose`, `order` | Array of option indices | Integer, unique, in range, count within min/max. Order is preserved. |
| `distribute` | Array of amounts, one per option | Nonnegative integers, exact recipient count and total; every amount >= 1 when `atLeastOne`. |
| `input` | String or JSON null to cancel | Correct type; numeric input must parse as a Java 32-bit integer. |
| `message` | Any explicit JSON value | A `value` field must be present. |

Combat distribution prompts additionally include `maySkip`, `sourceId`, `overrideOrder`, `divideDamage`, and `lethal` (threshold per blocker). If present, defender metadata identifies the final non-blocker recipient. Recipients and order constraints follow the pinned stock Forge damage dialog using Forge's card views. JSON null skips only when `maySkip` is true. These paths need broader real combat testing; they are not a new rules engine.

Responses go only to the requesting socket:

```json
{ "type": "ack", "requestId": "client-generated-string", "code": "dispatched", "message": "...", "protocolVersion": 2, "sessionId": "...", "revision": 43 }
```

`ack.code` is `answered` (decision accepted) or `dispatched` (action sent to Forge). Dispatch does not imply Magic legality or completion. Render subsequent authoritative state and `flash` feedback. Keep a submitted dialog until `askClosed` or a snapshot removes it.

Errors have `type: "error"` with `code` and `message`, and include `requestId` when it could be read. Codes include `invalid_request`, `stale_session`, `stale_state`, `invalid_action`, and `action_failed`. Invalid dialog answers leave the decision open for correction. Unknown/already-answered decisions produce an error. Request a snapshot after errors; stale session/state responses also arrange a refresh. Do not infer a renderable state from an error's revision alone.

## Contextual interaction descriptors

`equip {id, target}` uses the usual action envelope, latest revision and engine card IDs. Both cards must still be on the controlled battlefield, with an Equipment source and creature recipient, and Forge must offer a playable equip ability that can target that creature. The bridge filters the normal contextual ability chooser to those equip abilities; it does not attach cards directly. Godot then selects the dropped-on creature through the offered native target input and spends floating mana through normal `mana` actions. An incomplete payment retains the source and Cancel controls; choosing battlefield sources keeps that equip payment on the board while mana is added. Routine effects use the existing `autoPassStackId` policy, so actual response windows and Forge resolution remain intact. Disconnect, session changes and errors abandon the gesture without replay.

Unspent mana activation history survives Forge's pre-restore refund events during an authorized `undo_tap`. Earlier tap permissions are reinstated only at the completed restored priority checkpoint; spending mana or unrelated mutations still revoke them.

Remembered `PeekAndReveal` reveals followed immediately by a library `ChangeZone` choice over those remembered cards keep the authorized reveal context and proceed directly to the selectable gallery. Standalone reveals and optional reveal confirmations remain explicit. Card popups show large source faces without duplicating printed rules; decision instructions and distinct ability context remain available.

Decision asks may include visibility-filtered `sourceCard` and `effectText`; native `prompt` descriptors may include `sourceCard` too. `abilityChoice` marks formatted ability options, and `manaChoice` marks tap-only mana choices that can submit an original option index immediately. Forge still pays the activation costs. Explicit reveal callbacks include authorized card faces even for private zones. Combat entries carry `blocked` independently of their current `blockers` list, plus `trample`, so removing a blocker does not imply that the attacker became unblocked.

Delayed-reveal choices carry `revealedCards` separately from eligible `options`; native selections may carry the same context in `prompt.revealedCards`. Context is frozen from an authorized reveal and scoped to the same resolving spell ability. Viewed cards outside the eligible set cannot be selected. Hand reveals delivered through `showRevealedCards` plus `InputConfirm` display the authorized faces before sending native `ok`. Viewing the battlefield retains the unanswered decision and restores it on request.

Full ordering asks expose `autoOrder`; `abilityOrder` identifies simultaneous abilities. Auto appends remaining original option indices to the user's chosen prefix and submits the resulting permutation, matching Forge's desktop Auto button. A full `abilityOrder` ask opens as the stack builder (`OrderStack.gd`) already in Forge's order, so Confirm alone answers like Auto; other orderings use numbered card tiles in click sequence.

Incoming-effect previews use a bottom Resolve action; View battlefield hides the preview while retaining priority for a response. A player's own target choices do not automatically reopen the same effect as another preview. Own effects with no legal response can pass their priority window automatically; Forge's optional-use confirmations, payments and selections remain required.

Stack entries now also include `card` (visibility-filtered source), `ability`, `controllerName` and `targets`. Targets have typed `kind`/`id` references and visible card data or player names, including targeted stack instances. `text` is the actual pending ability description. A source card ID is not a stack instance ID; multiple abilities from one card remain distinct.

`prompt.entities` describes offered player or stack selections. Player IDs remain engine IDs on the wire; Godot translates them into seats and retains `engineId` for comparison with chosen references. Native selections still use `card`, `player`, `stack`, `ok` and `cancel`. Callback choice options for stack/ability views include permitted source `card` data and matching `stackId` when available, while answers remain original option indices. The client supports both forms rather than assuming one targeting path.

`autoPassStackId` authorizes only the current top item under `StackInteractionPolicy`: any item when Forge finds no legal local response; local routine effects; and opposing self-contained effects (permanent casts and effects whose every sub-ability only touches their controller's own things) unless they target the seat or one of its actionable cards can target that item. Board-wide, foreign-recipient, targeted and unknown effects retain a response window when a response exists. Client readiness, native input kind, payment and pending-decision guards are still mandatory. A Resolve click uses an ordinary revision-gated `ok` only when its acknowledged stack ID is on top at InputPassPriority. Respond sends no game action. Resolved notices and empty stacks cannot advance a phase through acknowledgment.

## Remaining boundaries

Battlefield pile counts are presentation-only and are recomputed from the actual packed instance IDs. The human board groups only after **Clean up board**; newly played cards retain their placements, and dragging a card out of a pile keeps it separate across snapshots. Hand cards always remain individual and never render a quantity badge. Cleanup and manual splits send no engine actions, and zone changes discard the corresponding presentation grouping state.

The client no longer opens a center menu for every priority stop or routine untargeted trigger. Direct targeted stack items and retained targeted/board-wide events still get visual notices; native target, payment and callback choices keep their required controls. Rail OK acknowledges its current stack ID and clears the matching notice, while an already-reviewed response notice stays dismissed when its spell resolves or is countered. The response button is labeled **Cast or activate a response** and keeps priority for instants (such as counterspells/protection) or activated abilities. It sends no game action itself. OK-only InputConfirm prompts use the rail instead of a second contextual panel. None of these presentation changes broaden automatic engine priority passing.

The Godot live adapter now consumes this protocol for exactly three players (start with `--opponents 2`). It preserves engine IDs for cards/stack and maps player IDs to table seats only at the adapter boundary. Live UI clicks use contextual actions; mock drawing/tap setters/free returns are disabled. `client-godot/tools/run.ps1 -Live` manages a fresh engine process; `-Connect` attaches to an existing bridge. The bridge also accepts `--deck-file PATH` to load a workspace Commander deck for all seats, useful for isolated integration fixtures without editing installed decks.

No lobby, attach-to-running-stock-game, restart/resume, card-image endpoint, remote seats, or next-game API is added here. Application-level headless GUI dialogs still have default/no-op behavior. Complex card manipulation still reduces to ordering, and direct stack targeting retains Forge's dialog fallback. Broader face-down/reveal/privacy coverage and complete gameplay verification remain vertical-slice work.

This protocol intentionally requires v2 metadata for mutating requests. The bundled browser test page and `probe.mjs` have been updated together; old external v1 action scripts need updating.
