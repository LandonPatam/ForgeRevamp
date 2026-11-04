# Commander Godot client

A standalone Godot desktop prototype of a three-player Commander table. Two opponents sit above the local player. The visual direction follows the handoff: restrained Arena-inspired presentation, dark teal surfaces, gold interaction cues, brief movement, and a clear stack/priority area.

The default launcher opens a shared main menu with Commander, Deck Editor and Quit. Commander selects a saved deck and loads the existing game against two AIs. **Live mode connects to the local Java bridge and lets Forge handle all rules and decisions.** `-Mock` opens the standalone visual table with scripted actions and fixed demo damage. Netplay and lobby integration are still pending. Card faces are flat. Atraxa, AtraxaV2, and Doom Commander have complete card images; other uncached game cards use procedural placeholders.

## Main menu

Run `.\client-godot\tools\run.ps1` (Bash: `bash ./client-godot/tools/run.sh`) after building the bridge. Commander validates the selected saved deck and starts a fresh three-player match. Deck Editor preserves its draft when returning to the menu. The game's Main menu button confirms before ending its owned match. See [navigation and verification](../docs/main-menu.md).

## Deck collection and editor

Run `.\client-godot\tools\run.ps1 -Decks` (Bash: `bash ./client-godot/tools/run.sh -Decks`) after packaging the bridge. The editor scrolls the home screen's floppy carousel to the top and shows the selected deck's cards below. It shares the room's light/dark theme and supports a full Forge catalog, hover previews, right-click copy/removal/artwork actions, native saves, and New / import. Opening it does not start a match. See [deck collection controls and verification](../docs/deck-collection.md).

## Contextual interactions

Proliferate offers **Select my permanents** to select all your eligible permanents at once. It includes lands, artifacts and planeswalkers when Forge offers them, excludes players and opponents, and leaves the selection editable before confirmation. Native Forge bulk selection also retains Select all eligible and Clear selection.

Pending effects have **Resolve** and **Respond** controls. Respond returns to the board without passing priority; **Review effect** reopens the source, targets and complete pending text. Resolve passes priority for that exact effect. Board-side controls handle targeting, attack/block confirmation, payment and other native decisions. **Browse targets** offers a card gallery, including cards in other zones; **Choose on board** returns to direct card selection. Counterspell choices show source cards and preserve distinct spell/ability instances. Card/player selections, mana, ordering, numeric choices and damage distribution keep their dedicated dialogs.

Routine local draws, life gain, counters, proliferate, tokens, scry, surveil, explore and safe combinations advance into Forge's actual decisions automatically. Opposing effects and unclassified or targeted effects retain response opportunities. Required choices and payments are never answered by automatic priority. The stack rail remains an inspection and fallback control. This covers interaction categories rather than guaranteeing every scripted card; unusual cases can still need the generic prompt.

Run `node client-godot/tools/live-check.mjs --interactions` for the isolated Respond/counterspell/gallery/Resolve regression, and `--decisions` for real search, cycling and land-return choices. Restart both bridge and client after rebuilding to load the new stack metadata.

## Play with Forge

From the repository root, package the bridge once, then launch a real match:

```powershell
.\bridge\tools\test.ps1
.\client-godot\tools\run.ps1 -Live
# Optional deck selection:
.\client-godot\tools\run.ps1 -Live -Deck "Sauron"
```

In Git Bash / Anaconda Bash:

```bash
bash ./client-godot/tools/run.sh -Live
```

The launcher starts its own JVM and a Godot window, then stops that JVM when the window closes. Engine/client logs are in `client-godot/artifacts/engine.*.log` and `play.*.log`. It does not stop existing Forge processes. An occupied port produces an error; select another with `-Port 17779`, or use `-Connect -Port 7777` to attach only the client to an already running bridge configured with `--opponents 2`. A new JVM starts a new game; reconnecting to the same JVM preserves the game and its pending decisions.

Follow Forge's prompt on the right. Click any visible card, player badge, or stack entry to submit a contextual selection. Click cards in the command/graveyard/exile browser to select them in Forge. Space presses the primary button; the secondary button keeps Forge's current label (for example, Undo, Mulligan, or Alpha Strike). Tap lands for mana before playing a spell. Godot asks Forge to spend only that floating pool; if the current cancellable cost cannot be covered, the play is canceled and the card returns to its original zone. Extra floating mana stays available. Mana ability choices and other engine decisions still appear normally. Right-click to read a card; Revealed cards shows temporary engine-authorized information. Drag a hand card onto the visible part of your own battlefield to request play; Forge validates timing and costs. Reordering within the hand and moving battlefield cards remain presentation-only. Escape or dropping outside your field cancels the play gesture. A dragged card keeps its release position while waiting for Forge, on the stack, and on the battlefield; rejected plays return from that same position.

Live actions carry protocol v2 session/revision/request IDs. Controls disable while disconnected, refreshing, or waiting for submission acknowledgment and newer authoritative state. Full snapshots replace open decisions, including missed closures; new sessions clear presentation caches. Requests are never replayed after a reconnect or stale-state error. Server validation errors remain visible in the decision dialog for correction. Hidden cards remain face down. Live mode has no arbitrary draw, tap setter, or free return-to-hand: automatic draws and legal undo belong to Forge. An immediately played unused land can be dragged back into the hand when Forge advertises permission; this requests card-specific undo and restores the land-play allowance. Review clicks and rejected plays preserve this permission. Actual game changes, phase advancement, and engine barriers disable that gesture. Broader spell rollback still uses Forge controls. A pending manual draw immediately shows a pulsing white library halo, an arrow, and a DRAW A CARD / Drag into hand prompt. Phase highlights come from Forge's stable phase key; each player's live phase buttons edit your priority stops during that player's turn. Bright blue means on; dim blue means off. The current step has a yellow marker. Changes survive reconnecting to the match.

Current limits: exactly three players, no lobby/netplay or next-game flow, and partial artwork coverage beyond the imported decks. Application-level headless bridge dialogs and complex card-manipulation decisions retain the bridge limitations documented in [protocol.md](../docs/protocol.md). A simple land/cast/mana/stack/attack slice is verified; broad targeting, blockers, combat allocation, complex Commander effects, and complete games need further coverage.

The bridge auto-selects and offers only abilities Forge marks playable. Repeated clicks on a tapped basic land cannot generate more mana; other abilities that remain legal while tapped still work according to Forge.

Click the most recently tapped mana source again to undo its activation while Forge advertises permission. This untaps the source and removes the mana it generated. T on the selected source does the same. Fully undoing an activation restores any unused-land return permission held before that activation. Canceling an unpaid mana activation also preserves that permission after Forge refunds its tap cost. Paying for a spell/ability or taking another game action closes this shortcut; it cannot untap a used source or a creature tapped for combat. Older activations are handled conservatively. This uses Forge's undo, with no direct tap-state setter.

Activating a card with a mana cost opens a payment popup showing the types and counts in your active mana pool. Choose a type to spend one mana; the remaining cost and pool refresh after each choice. For example, tap Swamp, activate Darkwater Catacombs, then choose Black. You can also return to the battlefield to generate more mana or cancel the activation. Spell casts retain their existing automatic floating-mana payment.

During Declare attackers, click your creature first to start an arrow, then click an opponent's avatar to choose who it attacks. Forge validates the declaration. Repeat for more creatures; reselect a declared creature to choose another defender. Escape, Cancel target, or clicking the selected creature again dismisses the arrow without changing combat. OK/Space is blocked until you choose a defender or cancel the arrow. After choosing your attackers, use Forge's OK to commit them; Forge controls tapping, vigilance, and attack costs.

Integration checks create an isolated legal fixture deck (99 Plains plus Isamaru) directly from the workspace; they do not modify installed decks:

```powershell
.\client-godot\tools\run.ps1 -Live -Check -Port 17779
node client-godot/tools/live-check.mjs --render
```

The first command tests the real launcher, keep-hand input, land play and second-land rejection, casting/payment/stack resolution, later-turn attacker/defender selection, duplicate submission gating, hidden hands, and reconnect without replay. The Node runner additionally captures the live table at both window sizes and always cleans up its owned processes. Generic startup choices vary; adapter fixtures and Java regressions cover decision recovery/validation when this simple match does not produce a blocking ask. `-Check` without `-Live` runs the mock smoke plus adapter privacy/session/revision/decision-recovery checks.

## Launch on Windows

Tested with the standard [Godot 4.7.2 Windows build](https://godotengine.org/download/windows/), installed portably in the ignored `.tools/godot/` folder. No .NET SDK or export templates are needed to run the project.

From `D:\ForgeUI`:

```powershell
.\client-godot\tools\run.ps1
```

For Git Bash or the Anaconda Bash terminal, use forward slashes and the Bash launcher:

```bash
bash ./client-godot/tools/run.sh
```

The Bash launcher forwards to PowerShell. Options such as `-Editor`, `-Check`, and `-Capture` work with either launcher.

To open the editor:

```powershell
.\client-godot\tools\run.ps1 -Editor
```

Alternatively, import `client-godot/project.godot` in Godot and press F6/F5. Set `FORGE_GODOT_PATH` to your own Godot executable if you do not use the portable copy. The launcher starts a normal interactive game window; verification captures use a separate off-screen process.

## Explore

The controls below describe **mock mode**. Live controls are described above.

| Input | Behavior |
| --- | --- |
| Hover | Inspect a card. Hand cards slide up 22 px in 0.10 seconds and ease back in 0.14 seconds, with an immediate ease-out response, retaining their fan angle, size, and position behind cards in front. A separate 450-550 px tall preview is vertically centered on the opposite side of the screen from the card. The sidebar no longer has a card-inspection section. |
| Right-click | Open a larger card inspection, including at smaller window sizes. |
| Click your battlefield card | Tap/untap and select it. During your Declare attackers step, clicking an untapped creature starts choosing its defender; it taps when you choose an opponent. Opponent cards are only selected/inspected. |
| Hold and drag your card | Move a battlefield card without tapping it, or reorder a hand card by dropping it into an animated gap in the carousel. Drop a hand card onto your own battlefield to request play; dropping it into the hand reorders it. A hold of about 0.18 seconds or short movement starts dragging. Escape cancels and preserves the previous order. |
| Return to hand | For an authorized unused play, click the sidebar action or drag the permanent onto the visible hand. The adapter validates the return; other cards stay on the battlefield. |
| Hand arrows / mouse wheel | Browse a large hand without shrinking cards. The fan stays pinned to the bottom edge while the battlefield scrolls. |
| Click a hand card | Select it. |
| Double-click your hand | Move a mock land to the battlefield or put a mock spell on the stack. |
| T | Same tap/attack action for the selected permanent. |
| Play selected | Play the selected mock hand card. |
| Resolve demo spell / Space | Resolve the next mock stack entry; otherwise advance to the next enabled phase stop. |
| Phase buttons | Forge-style UP / DR / M1 / BC / DA / DB / FS / CD / EC / M2 / ET / CL toggles. All twelve compact buttons fit in one row with no step-name heading. Blue buttons stop at that step; dim blue buttons auto-pass it. The current step is yellow when enabled and has a yellow outline when disabled. Hover shows the full name and stop state. |
| Field dividers | Drag the vertical divider to redistribute opponent widths; drag the horizontal divider to resize the upper and local fields. Minimum sizes preserve full-size cards and controls; extending the upper field grows the scrollable table. Double-click a divider to restore its default. |
| Choose a defender | Click an opponent's player badge or HP. Opponent areas highlight, and passing is blocked until you choose or cancel with Escape. |
| Library pile | Drag a face-down card into any position in the visible hand to request one draw. Neighboring cards slide apart to show its insertion slot. Canceling or dropping elsewhere does nothing. The enlarged 128 x 180 pile sits halfway between the screen center and your HP, half below the bottom edge, with the library count above it. Empty or unavailable draws are disabled. |
| D / Draw card | Request a mock draw through the same adapter action. |
| C / Crowded board | Toggle fourteen Sapling tokens. Scroll the creature row horizontally to browse. Use the scrollbar, a horizontal trackpad gesture, or Shift + mouse wheel. |
| Decisions / 1–5 | Open choose, order, distribute, input, or message fallback dialogs. |
| Flag / headstone / X | Browse command zone / graveyard / exile. Each icon has a count and full-name tooltip. |
| Player badge/life, when not targeting | View player information and mock commander damage. |
| Journal | View recent mock interactions. |
| H | Open help. |
| R | Reset the table. |
| Escape | Cancel targeting or close an informational browser; cancel an input decision. Required decisions stay open until answered. |

Hand and battlefield cards share full 200×281 dimensions, including lands, opponent cards, and tapped cards. Playing or returning a card preserves that size throughout the drag and engine confirmation. Tapping rotates the card without shrinking it. Crowded rows scroll horizontally, and smaller windows scroll the table vertically to retain those dimensions. The background is a dark grey grid drawn by TableBackdrop.gd, with 48 px cells and slightly stronger lines every four cells. Initials/HP badges occupy each field's corner: upper left for Mira, upper right for Thorne, and lower right beside the local hand. Battlefield ownership labels and generated portraits are removed. Fields have grey borders; the active player has a thicker yellow border. Phase-stop buttons sit at the bottom left of each field. The local phase strip and HP stay pinned beside the hand when the table scrolls. Text uses at least 12 px UI labels, deliberately compact 11 px phase buttons, and 32 px life totals. The enlarged hand overlaps in a fan, partly outside the bottom edge; hover lifts it slightly within the fan and displays a larger, flat preview vertically centered on the opposite screen side. Hand-count text and the hand heading are omitted; only the library count is shown above its face-down pile. Larger hands page through a carousel. Divider sizes and per-player stop preferences persist in `user://table-layout.cfg`; resetting the mock game preserves these presentation settings. Stop toggles currently drive only the mock adapter; connecting live Forge phase preferences remains live-adapter work. The layout supports windows down to 1280×800. Manual placements survive state updates until reset or a zone change; they are presentation only and are not saved between launches. This slice has no audio, four-player layout, or settings screen yet.

## Structure

- `scenes/Main.tscn`: entry scene.
- `scripts/bridge/StateAdapter.gd`: snapshot/intent boundary for presentation.
- `scripts/bridge/MockAdapter.gd`: deterministic mock data and scripted state transitions; no rules implementation.
- `scripts/bridge/LiveAdapter.gd`: WebSocket transport, protocol v2 submission gating/reconnect, visibility-preserving normalization, and engine-to-display seat mapping.
- `scripts/ui/Main.gd`: responsive table, card reconciliation by instance ID, inspection, public-zone browsers, stack, actions, and journal.
- `scripts/ui/CardView.gd`, `CardFace.gd`, `card_perspective.gdshader`: cached flat card faces with edge/shadow details. The projection shader now uses zero tilt for every card; hand fan rotations and tapping remain.
- `scripts/ui/CardArt.gd`: original procedural placeholder card landscapes.
- `scripts/ui/PlayerAvatar.gd`: image-free initials/HP badges, animated active-player glow, and life-change feedback.
- `scripts/ui/FieldDivider.gd`: draggable field dividers and double-click reset.
- `scripts/ui/LibraryPile.gd`: native face-down stack artwork and a cancellable drag gesture; the dragged card stays hidden until the adapter publishes the draw.
- `scripts/ui/ZoneIcon.gd`: native flag, headstone, and X icons; no icon fonts or generated images required.
- `scripts/ui/TableBackdrop.gd`: native dark grey grid background. The previous `assets/capenna-court.jpg` is retained but unused, with its credits in [CREDITS.md](assets/CREDITS.md).
- `scripts/ui/PromptPanel.gd`: all five generic decision forms, count/total validation, ordering, input cancellation, and acknowledgments.
- `scripts/ui/TargetOverlay.gd`: curved target/attack arrows.

The user-selected battlefield artwork is credited to its artists and Wizards of the Coast in [CREDITS.md](assets/CREDITS.md). Placeholder card names and landscape drawings are original. System fonts are requested at runtime and are not copied into the repository. No sounds are bundled.

The library pile uses the snapshot-level `availableActions.draw` permission (missing means false) and submits the existing `draw` intent only on a valid drop. A live adapter must obtain this permission from Forge and let the engine select/reveal the drawn card. The mock rejects empty-library and pending-decision draws.

Hand ordering is local presentation keyed by instance ID. Reordering preserves engine zone order and survives snapshots; reset restores the original arrangement. A drawn card or eligible returned permanent enters the chosen insertion slot. Library draws reveal the new card at the pointer release position before it settles into the fan, preventing an entrance from the left edge. Dragged cards preview their destination size while held; successful board drops and hand reorders place immediately. Authorized returns preserve the held pose at release and settle smoothly into the chosen hand slot while Forge validates undo, with no trip back toward their former board location. Confirmation does not restart that animation; rejection restores authoritative placement. The insertion gap reserves a visible slot even in a full hand, keeping the same spacing when the card is released. Neighboring fan cards still slide into place over 0.16 seconds, excluding the held card from the layout. A stationary pointer does not immediately hover a dropped card. Hover timing remains 0.10 seconds in / 0.14 seconds out. Large hands retain their current carousel page during dragging, except when a full-hand insertion needs the adjacent slot to remain visible.

Return-to-hand is an explicit adapter capability, not a visual zone edit. Card snapshots carry `availableActions.returnToHand` (missing means false); the UI sends `return_to_hand` with the instance `id`. In live mode, repeated unpaid casts that Forge cancels preserve an unused land's return permission. The bridge skips canceled-cast undo checkpoints through Forge's undo controls, keeping gameplay disabled while `undoPending` is true. This requires Free undo mode and retained history; single-step mode and exhausted history remain conservative. Actual source use, successful casting, phase changes, and information/effect barriers still close the window. The mock permits only the most recent untouched play: a land, pending spell, or resolved permanent with no simulated effects. Tapping (even if later untapped), attacking, drawing, phase advancement, another play, or other gameplay events invalidate the mock window. Resolved sorceries cannot be returned. This is a prototype convenience, not a general Magic undo rule. The live adapter requests engine-authorized undo with the relevant revision/session context; it never moves cards between zones itself.

The live adapter uses [the bridge's v2 protocol](../docs/protocol.md), normalizes Forge's card/phase fields, reconciles full snapshots/open asks, and sends contextual controller intents with session/revision metadata. Complete card faces load from a local image manifest; broader gameplay coverage remains pending. A selected/highlighted card is not an independent proof of legality.

Live opening hands appear over a dimmed battlefield in a large overlapping fan. Hover brings a full card forward within the fan; Keep Hand and Mulligan answer Forge's current prompt. View Battlefield (or Escape) toggles the fan without taking a game action. When Forge requires bottoming cards, select them in the same fan and use Confirm Selection, or Auto Choose when offered. Buttons wait for Forge and disable while disconnected. The normal bottom-edge hand keeps its existing hover behavior. Full card faces use the same carousel and inspection rendering as other cards.

Opening-hand interaction checks run with `-Check`; `-Capture` adds fan, hover, and bottom-selection screenshots. The live integration runner takes two mulligans, selects the required bottom card, keeps the engine hand, then exercises the existing gameplay regression checks.

Zero-card bottom selections (including the first free Commander mulligan) are acknowledged automatically. The panel asks for selection and confirmation only when cards must actually be put back.

## Verification and completion test

Prepared difficult card combinations can be run with `node client-godot/tools/live-check.mjs --scenario=proliferate --render`. Available scenarios are `proliferate`, `tokens`, `reanimate`, `protection`, `blink`, and `combat`; omit `--render` for headless runs. Each uses an isolated match and checks the actual UI choices and exact resulting game state. See [the interaction test report](../docs/interaction-test-report.md) for card combinations, outcomes, limitations and a command to run all six.

`node client-godot/tools/live-check.mjs --colorless-payment` reproduces Sol Ring plus Plains and Forest paying Forgotten Ancient's `{3}{G}` with W/G/C/C. Colorless pool payments use the bridge's corrected wire-to-Forge mapping. Ordinary artifacts now resolve automatically like creatures, and clicked casts keep a pending board card while on the stack. `--takeback` checks automatic artifact commitment and rejects undo after resolution.

Card interaction feedback: targeted-effect notices show the source → exact target card(s) and rules text. Mana choices use colored symbols and matching animated hover glows, including two-color prompts and activation payment. Choose/order/reveal prompts display card faces. Command-zone cards support the normal enlarged hover preview. The stack wraps complete descriptions in a scrollable region.

Battlefield cards show summoning sickness (Zzz), typed counters, marked damage, and remaining toughness. Current power/toughness sits below the printed values and uses high-resolution text in inspection. Damage stays separate from actual toughness and disappears when Forge clears it. Rejected card actions flash red and shake. During blocking, click an attacker, then your blocker; repeat the blocker to remove that assignment, then OK to finish. Blue arrows show blocks and the currently selected attacker has a blue outline. Restart bridge and client to load these changes.

Incoming targeted spells/abilities show a card popup with the caster and the names of your targeted cards (for example Mortify → Atraxa). It stays visible while on the stack and for eight seconds afterward, pauses when hovered, and offers full inspection or dismissal. Fast-resolving spells are retained by the bridge so the notice survives even when the card is already gone. Required decisions take precedence. Restart the bridge and client to enable the new event history.

Routine untargeted creature/artifact/enchantment casts now pass local stack priority automatically; Forge's AIs handle their own priority. Choices, payment, targeting, damage and other non-routine effects still pause. Empty-stack main phases remain open for playing cards. Pending cast visuals can be moved while awaiting resolution, without activating their abilities early. Restart both bridge and client to enable this on a new match.

Library drops keep their card back and insertion gap while waiting for Forge, then reveal the card at the release position. Hover waits for pointer movement after the draw so it cannot interrupt the insertion animation. The two-mana artifact regression uses `node client-godot/tools/live-check.mjs --artifact`.

The stack pulses yellow when Forge needs a choice beyond an OK-only acknowledgment (targets, selection dialogs, yes/no, or unpaid mana). It stops once that choice is answered or the client is waiting/disconnected. The outline remains visible with a decision dialog open and does not intercept clicks. Check covers the decision categories and exclusions; Capture includes both pulse intensities and the dialog view.

```powershell
.\client-godot\tools\run.ps1 -Check
```

This imports the project headlessly, then checks independent phase toggles, skipped stops, all-stops-off progress, divider resizing, library drag-to-draw, canceled/outside/empty-library guards, unused-play returns through button/drag, used/untapped-card rejection, resolved-effect rejection, large-hand paging, and a smoke path through drawing, hand-to-stack play, resolution, release-to-tap versus hold-to-drag, placement persistence, drag cancellation, uniform card dimensions, phase-gated click-to-attack, required defender choice, multiple attackers, rejected tapped attackers, life changes, crowded-row data, each real dialog widget's validation/submission, and reset. It does not test Forge gameplay.

Rendered visual checks can be generated with an off-screen rendering-capable Godot process:

```powershell
.\client-godot\tools\run.ps1 -Capture
```

The process captures phase stops, resized fields, enlarged bottom-edge hand/hover and smooth return at both sizes, library drags/draws, unused/returned plays, a large hand, and the table at 1600×1000 and 1280×800, hover expansion of both central creatures plus hand/tapped cards, large inspection, crowded rows before/after horizontal scrolling, moved cards before/after tapping, defender selection, attack feedback, and a partially answered ordering prompt, then exits. It checks that hover rendering lives outside row clipping and matches the original card's transform, that the action controls fit the smaller viewport, and that the crowded row can scroll. Captures and import caches are ignored by Git.

The concrete done test for this slice is: launch without Forge; inspect a card; play and resolve a creature; tap it; select an opponent as its attack target; browse command/graveyard/exile; submit each fallback kind; browse a crowded row; reset. Confirm both window sizes from screenshots.

Manual live draws: Forge performs its normal draw, then the library gesture reveals that already-drawn card into your chosen hand slot. Trying another game action first lights the library with a white border. The client does not draw again. Pending draw acknowledgements survive reconnects; opening hands and skipped draws do not create this gate. Generic required decisions remain answerable. Run the separate wrong-color payment diagnostic with `node client-godot/tools/live-check.mjs --wrong-color`; its white/blue partner deck exercises blue floating mana against a white cost. Complex alternate costs and mandatory payment paths still need broader coverage.
