# Verifying Forge decisions in ForgeUI

Use a real Forge scenario to check three points in the same game. Establish what
Forge should ask at a specific game event, drive the existing Godot control, then
verify which card or player Forge acted on and what changed on the board. Check
that the engine waits at the decision when the player needs to see it.

## Verified Windows scenarios

- **Citadel Siege and ward.** Choosing Dragons leads to a target tether even with
  one legal creature. The target stays pending until confirmation. Winged Boots
  then produces a ward payment with the targeted creature, source and consequence.
  Declining lets ward counter the ability. Paying lets Siege tap the target before
  attackers. Paying one mana shows three still due, and the player can still
  decline.
- **Same decision through both presentations.** Each pair runs the same board
  twice, once through the custom presentation and once through the generic
  control, with a test-only switch: `InteractionPanel.tethers_enabled` (target
  and mode tethers), `PromptPanel.stack_builder_enabled` and
  `SelectionPanel.carousel_enabled`. Each run first checks what Forge offered.
  The adapter's test-only `sent_requests` log must then show the same picks or
  answer, and Forge must produce the same result.
  - `siege-targets` / `siege-targets-rail`: the second of two Bears. Both send
    one `card` pick for that instance, and Siege taps only it.
  - `skate` / `skate-rail`: two targets, sent in order, and both counters double.
  - `gearhulk` / `gearhulk-rail`: the second opponent. Both send one `player`
    pick for that seat, and the trigger targets that player.
  - `concord-counters` / `concord-popup`: two modes. Both send one answer with
    those mode indices, and only those effects happen.
  - `triggers-token-first` / `triggers-plain`: the stack builder vs
    click-in-sequence. Both send the same order, and the token gets its counter.
  - `cultivate` / `cultivate-list`: carousel vs list. Both send the first Island
    and Swamp instances in turn, and those exact cards arrive.
- **A queued pick never reaches a replaced input.** `flagbearer-replaced`:
  AI 1's two Standard Bearers make Forge first offer only Flagbearers for Bane's
  Invoker. Staging both and confirming sends the first, and Forge then replaces
  the input with that Bearer already chosen. The queued second pick is never
  sent, the stale send ends and nothing stays staged. The player picks it again
  in the rail, and both Bearers resolve at 3/3. The Bearers start as one pile;
  real clicks on the pile stage one copy at a time, because a picked target leaves
  its pile.
- **A connection drop mid-discard.** `discard-interrupted`: Discard sends the
  first of two marked cards and the socket closes in the same frame. After the
  reconnect the second pick is never sent on its own and nothing stays marked.
  Forge holds the first pick, so the card window takes the question (it shows
  and can change what Forge holds). Finishing there discards exactly both
  cards. Forge has no natural replacement mid-discard or mid-search (both
  finish at their last pick), so a dropped connection is the real interruption.
- **Stack responses matrix.** Each `matrix-*` board puts one opponent item on
  the stack at your priority. `LiveAdapter.passes_automatically`, the rule the
  adapter itself uses, is applied to Forge's real snapshot for each level. The
  seat then really holds priority at every waiting level, and the first
  passing level passes it.

  | Board | Item | Everything | Smart | Only threats |
  |---|---|---|---|---|
  | `matrix-creature` | Grizzly Bears, no response | pass | pass | pass |
  | `matrix-counter` | Grizzly Bears, you hold Counterspell | wait | wait | pass |
  | `matrix-instant` | Opt, you hold Giant Growth | wait | wait | pass |
  | `matrix-draw` | Vision Skeins (instant, everyone draws) | wait | wait | pass |
  | `matrix-targeted` | Lightning Bolt at your Bears | wait | wait | wait |
  | `matrix-wipe` | Wrath of God reaching your Bears | wait | wait | wait |
  | `matrix-wipe-misses` | Wrath of God, nothing of yours | pass | pass | pass |

  Another player's instant or sorcery holds the window under Smart even when
  it is only a draw notice. Notice-and-pass applies to abilities and triggers.
- **Off-table targets fall back at once.** `ooze-graveyard-target`: Scavenging
  Ooze sits on the table but its legal targets are graveyard cards. The tether
  declines, the card window opens directly, and picking the second of two
  identical Bears sends that instance. Forge exiles it and leaves the other.
- **Serra Angel and Grizzly Bears.** Forge determines that the Bears cannot block.
  The combat rail offers Continue without blockers and Serra Angel deals four
  damage to Jace after the defender confirms.
- **Citadel Siege and two copies of Grizzly Bears.** A first opponent has only
  a creature with shroud, so combat proceeds without a target. On the next
  opponent's turn, a battlefield click identifies one of two legal Bears by
  instance. The tether, Forge's stack and the tap all agree on the same copy.
- **Foresee and Index.** The scry tether offers only the top four cards. After
  reordering both ends, Foresee draws the chosen top two in order. Index then
  sees the previously hidden card followed by the two cards sent to the bottom,
  in the chosen order. Bridge and Godot checks also exercise top-only and
  bottom-only decisions directly, since the bundled scry caller supplies both
  destinations.
- **Preordain with two cards left.** Sending both to the bottom preserves the
  requested order and reports two bottom placements. Forge receives the ends
  explicitly through the library-ends patch.
- **Duelist's Heritage.** Both branches put the chosen attacking creature on
  Forge's stack as Heritage's target. The resolution tether names it. Only the
  Yes branch gives it double strike. A separate replacement check gives two
  targeting inputs the same source and choices and verifies the old pick is
  discarded before sending.
- **Mode choices.** Concord with the Kami resolves Spirit plus draw and Spirit
  plus a counter in separate runs. Each test checks that the unselected effect
  stays absent. Fiery Confluence preserves two selections of the same damage
  mode and a separate artifact target. Call Damage Control resolves after one
  empty choice, with both cards still in the graveyard. Season of Weaving
  spends three pawprints on returning permanents, then one each on two draws.
  Forge offers only affordable modes at each step.
- **Simultaneous triggers.** Drag Wedding Announcement and Brokers Ascendancy
  into both orders in the stack builder. The builder sends the order on
  confirmation. Forge puts a counter on the Human token only when Wedding
  Announcement resolves first. The existing Bears get a counter in both runs.
- **Optional and refused targets.** Yawgmoth can choose no target and still
  pay the cost and draw. Auto-resolve waits for the choice. Deepglow Skate
  clears a refused staged pick and lets the player submit valid targets.
- **Two human seats and reconnect.** Each seat orders only its own triggers.
  The guest's order survives reconnect, and its triggers are above the
  active player's triggers. Guest scry cards stay private. An answer to the
  old order cannot answer the later scry. The UI separately checks that local
  staged picks are cleared when the connection drops. The ordinary targeting
  and selection controls can continue from picks Forge already accepted.

## Remaining work from the broader plan

1. **Verify both translations against Forge.** The current scenarios check
   representative outcomes, and the bridge tests can compare returned objects
   with Forge's original callback inputs. Extend that pattern to capture the
   actual choices offered by Forge and the objects or controller actions
   received back from Godot. Derive expected choices from the Forge input
   and the scripted player action. Compare visibility, identity, order,
   multiplicity, and decline or cancel where the input supports them.
2. **Compare the generic controls with the custom presentations.** Done for
   targets, players, modes, trigger order and library searches (see above).
   Add a pair whenever a new presentation takes over a Forge question.
3. **Interrupt an in-flight staged send.** Done for targets (a real Forge
   replacement), discards (a real connection drop) and the priority matrix
   (see above). Still open: a notice-and-pass ability for the matrix (an
   opponent's "each opponent loses 1 life" trigger) and the same checks on a
   two-seat online table.
4. **Report observed decision variants.** The shape inventory and a four-round
   Abzan Armor playtest served as discovery runs. The playtester still needs to
   report which decision variants it encountered and map those variants to
   named Godot checks. Record coverage by choices expressed and outcomes
   verified, such as declining a target, choosing the second identical
   permanent, or ordering three triggers. Use F8 reports and the
   [testing workflow](testing.md) to reproduce misses and add a regression test
   for the decision family.

Additional cases include simultaneous triggers with different target
restrictions, cancellation after costs other than mana, and pending decisions
on real Windows–Mac tables. The full suite and Mac validation remain pending
for the local changes. See [session notes](../NOTES.md) for the checkout and
isolated Windows build.

The [precon playtester](playtest.md) describes what its current reports cover.
