# Table animations

The table used to change only between snapshots: cards appeared, vanished or moved with no hint of what happened. `ui/TableFx.gd` adds a presentation layer that plays public happenings over the already-updated board.

## Rules

- **Presentation only.** An effect never answers Forge, never delays or hides a decision and never replays anything. The snapshot stays authoritative: every effect runs over the board as it already is.
- **No replay.** The first snapshot of a session only primes what was seen. Reconnecting, parking and resuming never replay old beats. `reset()` runs with the session reset.
- **Beats.** The new happenings from one snapshot form one beat, in this order: charges and blocks, strikes, impacts, then departures. Beats queue for at most 0.9 s. After that, later beats overlap at half length rather than fall behind fast bot turns.
- **Ghosts.** A battlefield card that leaves is reparented into the effects layer as an unclickable ghost. It reuses the card's cached face, plays its exit, then frees itself. Main has already forgotten it.
- **`CardView.fx_offset`** moves only the drawn card, its traits and its stats, in global pixels. It never moves the layout position or the hit area.
- **Motion language.** Strikes travel along shallow arcs: ease-in out, ease-out back. Entrances ease out and exits ease in. Effects confirm with one pulse ring. The look stays in the terminal/CRT palette: red hits, teal blocks, glyph fragments. Everything is canvas drawing and tweens, so it works with GL Compatibility.
- **Setting.** Table settings → Animations: Off / Fast / Normal / Cinematic, a duration factor of 0 / 0.6 / 1 / 1.35, saved in `table-layout.cfg`. Off also covers reduced motion. Checks (`verification_mode`) run with animations off; animation checks turn them on themselves.

## Sources

| Happening | Source |
|---|---|
| Attack declared | `combat` diff, once Forge leaves that seat's attack input |
| Block declared | `combat` diff, once Forge leaves that seat's block input |
| Damage (who, whom, how much, combat, deathtouch, infect) | bridge `fx` stream (`TableFx.java`, from Forge's `GameEventCardDamaged`/`PlayerDamaged`, and loyalty/defense loss in combat damage steps) |
| Spell or ability cast | `stack` diff: a new stack item (from its source on the table, or the caster's portrait; your own spells already fly from your hand) |
| What the stack is aiming at | `stack` item `targets`, every snapshot |
| Resolved, fizzled or countered | bridge `fx` `resolve` / `fizzled` / `countered` with the stack item id (Forge fires a resolve event before removing a spell; a countered spell is removed with no resolve) |
| Card leaves the battlefield | layout diff plus the card's new zone in the snapshot (Graveyard, Exile, Hand, Library, Command, or gone) |

The bridge receives Forge events through `BridgeMain`'s subscription, which calls `BridgeGuiGame.trackDrawEvent`. `handleGameEvent` is not called for the bridge's GUI.

## Effects

Phase 1 (combat) is done:

- **Attack:** each attacker charges toward its defender, and the attack arrow draws itself on. Arrows are keyed lines in `TargetOverlay`.
- **Block:** the blocker steps out toward its attacker, with a teal pulse, and the block arrow draws on.
- **Combat damage:** each striker winds up, lunges along an arc toward its first target and springs back.
- **Impact:** the target shakes and flashes, and a red damage number rises off it. Infect numbers are green; deathtouch is labeled. A hit player's portrait jolts, and its HP flashes as before.
- **Leaving:**
  - Dying: the card glitches, breaks into glyphs drifting to its owner's graveyard icon, and the card arcs there shrinking.
  - Exile: the card washes out white and fades.
  - Bounce, tuck or command zone: the card arcs to the hand, library, portrait or zone icon.
  - Token ceasing: the card dissolves in place.

Phase 2 (targeted spells and abilities) is done:

- **Cast:** a spark in the spell's color flies from the caster's portrait, or from the source permanent for an ability, into its stack entry.
- **Lock-on:** pulsing corner brackets on every card or portrait the stack is aiming at, in the spell's color, for as long as it is on the stack.
- **Resolve:** a comet arcs from the stack entry to each target (color from the mana cost, gold blends, gray for colorless; red throws sparks). Its impact times the damage numbers and the target's exit, so a Bolted creature dies when the bolt lands.
- **Fizzle:** a thin gray comet ends in FIZZLE. **Countered:** the stack entry is struck through and breaks into glyphs under COUNTERED. Words sit on an opaque plate so they never overlap other text.
- A card that both strikes and is hit plays both: hits shake through a separate `fx_shake` channel.

Phase 3 (board life) is done. It works only from snapshot diffs, so the bridge sends nothing new:

- **Opponents' plays:** a nonland permanent flies out of where it came from: its stack entry, its graveyard/exile/command icon, or the caster's portrait. It shows at 1.7× for a moment so you can read it, then settles into its slot. The card's own layers stay hidden (`CardView.fx_alpha`) while the copy is drawn.
- **Lands, and your own returns** from the graveyard, exile or command zone, slide in along an arc. Your plays from hand keep their existing motion.
- **Tokens** print in: an outline first, then the face line by line under a teal scanline, staggered 40 ms apart and capped at 0.6 s. When exactly one item resolved (and it isn't itself entering), a line runs from it and it pulses.
- **Counters** get a plated label in printed wording ("+1/+1", "-1/-1 ×2", "LOYALTY +2"). Gains are teal, losses red. Loyalty already shown as combat damage isn't repeated.
- **Power/toughness changes** get a "+3/+3" label. When three or more cards change alike (anthems, sweepers), each gets one quiet staggered pulse and no numbers.
- **Life:** the HP digits roll to the new total. Life that changed without damage gets a teal "+N" or violet "-N". A drain draws a line from each player who lost to each who gained.
- **Mana**, your seat only, Normal and Cinematic: a mana symbol flies from each land you tap to its pool slot. If the mana was spent at once, it flies into the spell you're casting, and spent pool mana flies there too.

Phase 4 (polish) is done, without sounds as decided:

- **Board wipes:** when three or more permanents leave in one beat, a red scan line crosses the table (the table area only, not the rail). It starts from the side of the player who resolved the wipe. Each permanent breaks apart as the line reaches it; both move at a steady pace so they stay in step.
- **No turn banner:** a sliding TURN strip was tried and removed at the user's request. The purple active-turn light already shows whose turn it is.
- **Performance:**
  - The director's own work is timed in `cost` (worst draw and snapshot diff, in µs). On the real-engine effect scenarios it peaks around 1.3 ms of drawing and 0.4 ms of diffing.
  - Past 360 drawn items, cosmetic particles are dropped (numbers and exits never are), and glyph bursts are capped at 220.
  - The flash style box is reused.
  - Once every effect ends, the director stops processing (asserted by `wipe-fx`).

**Endings:**
- A player who loses doesn't vanish. After the killing beat (the hit, its number, HP rolling to 0), their board breaks into glyphs card by card, from their portrait outward. That happens both when Forge removes their cards and when the game ends with the cards still down.
- Their OUT mark and ELIMINATED line appear only after that.
- YOU WIN (gold) and YOU LOSE (purple) wait for `TableFx.settled()`, then a short pause, at most 6 s.
- Checked by `lose-fx` and `win-fx`.

Remaining: the Mac run of the effect scenarios and sandbox boards, then two-seat online checks.

## Checks

- `node client-godot/tools/check.mjs scenario combat-fx --render`. In this real-engine block, the bridge must send each hit, and the table must play the strike, the numbers and the Ogre's exit, then settle clean. Captures: `-impact`, `-leaving`, `-settled`.
- `check.mjs scenario spell-fx --render`: AI 1's Bolt (at your Bears) and Shock (at you); the brackets lock on, Counterspell's target is reported `countered` and shatters, the other spell is reported `resolve` and flies to its target. Captures: `-lock`, `-projectile`, `-settled`.
- `check.mjs scenario board-fx --render`: AI 1 resolves a creature, tokens, a counter, a pump and a drain while you tap a Forest. Each effect must play: `played` and `shown_labels` on TableFx record them. Captures: `-mana`, `-showcase`, `-print`, `-labels`.
- `check.mjs scenario wipe-fx --render`: Wrath of God over five creatures plays one sweep with staggered exits. After a turn passes, the director goes idle. Capture: `-sweep`.
- `check.mjs scenario lose-fx --render` and `win-fx --render`: an AI's Bolt finishes you, and your Flame Rift finishes both opponents.
  - Each loser's board must break apart, and the OUT marks must appear, before the purple YOU LOSE or gold YOU WIN.
  - Without an app host the scenario shows no YOU WIN screen, so `win-fx` checks the table and the gold accent.
- Animation checks turn effects on themselves (`TableFx.speed = 1.0`). If the board's last snapshot came before that, they call `table_fx.present(ui.snapshot)` once.
  - Read `played`, `shown_labels` and `cost` rather than polling `items`: saving a capture can outlast a short effect.
- Sandbox: `node client-godot/tools/sandbox.mjs combat-fx`, `spell-fx`, `board-fx`, `wipe-fx`, `win-fx` or `lose-fx`.
