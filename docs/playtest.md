# Automated playtest (human seat)

`node bridge/tools/playtest.mjs` launches an isolated bridge per Forge Commander precon (`forge/forge-gui/res/quest/commanderprecons`), plays the human seat over the real v2 WebSocket protocol, and writes `bridge/tools/playtest-reports/<timestamp>.md` and `.json`. It stops only the JVMs it started.

```
node bridge/tools/playtest.mjs --games 10 --turns 6 --timeout 260 --seed 11 --parallel 3
node bridge/tools/playtest.mjs --decks "Abzan Armor,Ahoy Mateys" --trace
```

Options: `--games` (random precons), `--decks` (name fragments), `--turns` (rounds before stopping), `--timeout` (seconds per game), `--seed`, `--parallel` (JVMs at once; each uses up to 3 GB), `--trace` (every action), `--out`.

## What it does

Keeps the opening hand, plays a land each turn, casts affordable spells (color-aware), pays with battlefield sources, answers asks and target prompts with the first legal choice, attacks with up to three creatures, never blocks, and passes otherwise. It also activates abilities on permanents already in play (at most three a turn), trying player-targeting ones first, picking the intended ability from Forge's chooser and the player the text implies (yourself for draw/gain, an opponent otherwise). Opponents are Forge AIs. A 6-round game takes roughly 1-4 minutes.

## What it checks

- Protocol health: rejected actions, no progress for 25 s, bridge exit, socket close, Java exceptions in the child log.
- Per card play: lands reach the battlefield (and arrive tapped when their text says so), permanents arrive, instants/sorceries finish in the graveyard or exile.
- Text claims for a spell's own effect or an "enters" trigger: a named `target` must produce a target decision, `draw N`, `gain N life`, `create N tokens`, "exile all cards from target player's graveyard".
- Activated abilities: a named target player must produce a target decision; {T} costs must tap the permanent; draw, gain life, lose life, damage, mill, discard and graveyard-exile effects are verified against the chosen player.
- Plays no check covers are listed as unverified, not passed.

## Limits

- Planeswalker loyalty abilities, combat tricks, blocking and most static effects are not exercised. The text checks are patterns, not an oracle.
- It plays one fixed strategy, so rarely cast cards are not reached. Use more games or `--decks` to widen coverage.
- Findings marked `info` (for example "could not pay") are driver limits, not game bugs.
- Bots make games differ run to run; the seed only fixes deck choice and the driver's own picks.
