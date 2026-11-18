# Session notes - 2026-11-18

## Current state

- **Branch:** Windows is on `feature/combat-animations`, pushed. It builds on the interaction-reliability work (`0ea856f`). Local `main` is still `cda06eb`, so the branch carries everything since then. Nothing is merged.
- **Table animations, all four phases done** (`ui/TableFx.gd`, bridge `TableFx.java` `fx` stream; see [animations](docs/animations.md)):
  - combat strikes, damage numbers and exits
  - cast sparks, lock-on brackets, resolve projectiles, counter marks
  - opponent plays shown large, tokens, counter and pump labels, rolling HP, your mana symbols
  - board-wipe sweep and turn banner
  - endings: the loser's board breaks apart, then OUT, then YOU WIN (gold) / YOU LOSE (purple)
  - Table settings → Animations: Off / Fast / Normal / Cinematic. Checks run with animations off.
- **Also on this branch:**
  - Eliminated opponents are marked (OUT, plus how they went out).
  - The loss screen says how you died.
  - The deck text export keeps printings (`1 Sol Ring (C21) 263`).
  - The editor's file dialogs no longer hide behind the carousel and freeze the app.
  - The stuck guard no longer crashes on a removed field.
- **Windows checks passed:**
  - UI suite (37)
  - animation scenarios `combat-fx`, `spell-fx`, `board-fx`, `wipe-fx`, `win-fx`, `lose-fx`, plus `blocking`, `combat`, `damage`, `guard`
  - library check, UI-scale check, bridge checks
  - Per the testing rule, `check.mjs all` was skipped: the animations are off in checks.

## Known issues

- `blink` is flaky: Lightning Bolt sometimes stays on the stack after OK. It failed the same way with and without these changes.
- `no-legal-blocks` needs the opt-in `forced-decisions.patch` in the Forge build.
- Mac validation and two-seat online play are pending for everything on this branch.
- Card art the bridge sends for a face-down permanent must stay a back. The animation copies reuse each card's cached face, so check this online.
- The shape sweep (`tools/shape-sweep.mjs`, `check.mjs shapes`) remains separate, unfinished work.

## Next steps

1. **Mac:** pull `feature/combat-animations`, rebuild the bridge and run the six animation scenarios with `--render`. Look at the captures and play the sandbox boards (`combat-fx`, `spell-fx`, `board-fx`, `wipe-fx`, `win-fx`, `lose-fx`). Push fixes to the same branch.
2. **Online:** run a two-seat game. Both seats see the same happenings, and nothing reveals hidden cards (face-down plays, hands).
3. **Merge:** merge into `main` after 1–2 pass, then fix the `blink` race.
4. **Earlier reliability items:** a notice-and-pass ability case for the stack matrix, and a decision-variant inventory for the playtester.
