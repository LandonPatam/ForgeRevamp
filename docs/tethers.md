# Tethers: decisions that hang off their card

A **tether** (the user's word) is a decision shown as a small terminal box joined to the card that caused it by a leader line, with that card outlined, instead of a popup or the top banner. The user asks for new decisions "as a tether" / "stemming from the card". This document is how they are built, so a new one takes minutes, not a redesign.

## The look (keep it consistent)

- **Box:** `TerminalStyle.panel`, purple (`Terminal.ACCENT`) border, drop shadow. Title `[ CARD NAME ]` (muted, 12 px), then a blinking `> question_` line (16 px, lowercase, engine ids like `(304)` stripped), then rows, then `[Y] …` / `[N] …` buttons (Y/N keys work).
- **Link:** a purple leader line from the card's edge to the box, and a pulsing purple outline on the card (`InteractionPanel._draw_callout_link`).
- **Lines to other things:** orange (`ffb978`) for "this is what will be hit/picked" (wipes, the highlighted pick); purple for "what you have staged" (targets, discard picks in red `ff3b3b`). Lines grow in over ~0.35–0.45 s and can carry a small spark. Frames follow the target's own transform (tapped cards are rotated; never use `get_global_rect()` for a frame).
- **Cards inside the box:** shown large (230×322 for one card), not text, when the card is the point (a look, a commander that left the table). Drop the name heading when the card is shown.
- **Wording:** plain, short, about this game ("Move Gravecrawler to the command zone?", "Return Island"), never Forge's rules text or bookkeeping (`[Zone Changer: …]`).
- **Nothing reaches Forge until the box's button**, unless the row itself is the action (mana colors, abilities, like Forge's own menu).

## Where things live

| File | Role |
|---|---|
| `scripts/ui/CardCallout.gd` | The box. Modes: yes/no (`present`), card modes (`present_modes`, toggles + Confirm; ability/mana rows act on click, mana as `ManaOption` tiles, abilities as `AbilityOption` with symbol costs), card lists (`present_cards`: looks/reveals with OK, one-card picks with "Return X"), scry (`present_scry`), targets (`present_targets`). Each `present_*` first leaves the other modes (`_leave_*`, `leave_targets`) and must restore any button it can hide. |
| `scripts/ui/InteractionPanel.gd` | Decides which tether shows and where: `present()` routes asks/prompts to a mode, `_anchor_for(id)` (table card → your zone icon via `zone_view` → none), `floating` (centered, no line), `_place_callout` (beside the card, clear of the rail), `_draw*` for links, branches, target lines. Static `*_source(ask)` helpers tell Main which asks it takes. |
| `scripts/ui/Main.gd` | Routes `snapshot.asks` (tether vs popup vs board choice), owns **local staging** for picks Forge would finish on the first click (`hand_pick_*`, `target_staged` + `_commit_targets`), the library-search link (`search_link`, `_search_anchor`, `_slide_search_clear`). |
| `scripts/ui/ResponseTarget.gd` | Casting at a stack item (Counterspell → Wrath): the spell large mid-table, menu off it, branch to the stack entry. |
| `scripts/ui/IncomingEffect.gd` | Opponent effects: wipe/targeted table view (card mid-table, branches to every affected card), large popup, small notices (`notice`, `reveal`). |
| Bridge `BridgeGuiGame.java` / `GameStateJson.java` | Makes Forge's questions answerable as tethers: names the real source (`sourceCard`, `casting`, `commanderReplacement`), turns loops into one ask (`modeChoice`, `scry`), sends what the client needs (`affected`, `xValue`, improvise `selectable`). |

## Adding a tether: the recipe

1. **Probe first.** Write a board under `tests/scenarios/` and a driver that reaches the moment and prints it (see "Probe, then design" in `testing.md`). Read the real `prompt`/`asks` JSON: `inputKind` or ask `kind`, `sourceCard`/`cardId`, `options`, `min`/`max`, `okEnabled`, `entities`, `selectable`. Most surprises (wrong source, whole library sent, loop of one-at-a-time prompts, auto-finish at max) show up here.
2. **Fix the source in the bridge if needed.** If `sourceCard` is a rules object (e.g. "Commander Effect") or missing, name the real card in `GameStateJson`/`BridgeGuiGame` (reflection on Forge inputs is acceptable and already used; never edit `forge/` for presentation).
3. **Pick or add a CardCallout mode** and route it in `InteractionPanel.present()` (plus `Main` for asks). Anchor with `_anchor_for`; a card that already left the table anchors to its zone icon and shows the card inside the box; nothing on screen → `floating` or the old popup.
4. **Stage locally when Forge would finish early.** Forge completes a selection the moment it reaches its maximum (`InputSelectManyBase.refresh` → OK). If the user must confirm, keep picks in the client and send them on the button, one per snapshot, each confirmed by `prompt.chosen` (`_advance_hand_pick`, `_advance_targets`). The same for library carousels (`SelectionPanel.staged`).
5. **Test it** with a real-engine scenario (assert the engine result, capture a screenshot, look at it), run the existing tether scenarios (`wilds, concord, triland, commander-zone, animist, scope, gearhulk, constrictor, scry`), and give the user the sandbox command.

## Known shapes

- Yes/no about a card: `InputConfirm` + `sourceCard` (Evolving Wilds, Sword of the Animist, commander to command zone).
- Modes / abilities / mana colors: `choose` asks (`modeChoice`, `abilityChoice`, `manaChoice`).
- Look / reveal: `message` asks with card options. Another player's reveal is a small `reveal` notice, never a question.
- One-card pick among table cards by an effect: `InputSelectCards/EntitiesFromList`, min = max = 1 (Izzet Boilerworks). Picks among revealed/library cards keep the search window.
- Targets of a trigger/ability from a permanent: `InputSelectTargets` (Gearhulk, Constrictor, Hammer of Nazahn). Spells cast from hand keep the rail.
- Scry: bridge `scry` ask (`manipulateCardList`), only the looked-at cards.
