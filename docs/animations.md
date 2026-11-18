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

Next phases (planned):

1. **Targeted spells and abilities:**
   - Cast: the card flies from its source to the stack.
   - Lock-on: brackets on its targets.
   - Resolve: a projectile along an arc from the stack to each target, colored by the card's color, ending in an impact.
   - Countered or fizzled: the stack entry shatters.
   - Non-combat damage already shows impacts. The projectile is what's missing.
2. **Board life:**
   - Opponents' plays come out of their portrait.
   - Tokens print themselves in.
   - Counter badges pop, and power/toughness flashes on a pump.
   - Life gain rises in teal, and drain draws a line from its source.
   - Tapping for mana sends a symbol to the pool.
3. **Polish:**
   - Board-wipe sweeps with staggered deaths.
   - A turn banner.
   - Optional sound hooks.
   - A performance pass, then Mac and two-seat online checks.

## Checks

- `node client-godot/tools/check.mjs scenario combat-fx --render`. In this real-engine block, the bridge must send each hit, and the table must play the strike, the numbers and the Ogre's exit, then settle clean. Captures: `-impact`, `-leaving`, `-settled`.
- Sandbox: `node client-godot/tools/sandbox.mjs combat-fx`.
