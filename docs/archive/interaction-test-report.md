# Card interaction test results

Run date: 2026-10-24. All six prepared scenarios and three existing live suites passed against the pinned local Forge build and the actual Godot client.

## Prepared combinations

| Scenario | Cards and interaction | Verified result |
| --- | --- | --- |
| `proliferate` | Contentious Plan, Hardened Scales, Winding Constrictor, Walking Ballista, Fathom Mage, Dreadship Reef, Jace Beleren; player and opponent counters also offered | Select my permanents chooses exactly the four eligible local permanents. Ballista goes from 2 to 5 +1/+1 counters, Mage from 1 to 4, Reef from 2 to 3 storage, Jace from 3 to 4 loyalty. Player counters stay unchanged. Plan plus Mage draws exactly four cards. Replacement-order decisions complete. |
| `tokens` | Raise the Alarm, Doubling Season, Soul Warden, Impact Tremors | Four Soldiers enter. Four Warden triggers bring local life to 44; four Tremors triggers bring both opponents to 36. Simultaneous trigger ordering completes. |
| `reanimate` | Reanimate targeting Eternal Witness, with Soul Warden in play and another graveyard option | Witness enters with summoning sickness, and its ETB returns Reanimate from the graveyard to hand. Losing three life and gaining one leaves 38. Target choices and trigger ordering complete. |
| `protection` | Opposing Wrath of God; respond with Heroic Intervention, then Swords to Plowshares on Darksteel Gargoyle | The board-wide effect notice identifies Wrath. Respond preserves priority for mana and casting. Local creatures survive Intervention; the opposing Bear dies; Gargoyle and Sol Ring survive. Swords exiles the indestructible Gargoyle and grants its controller three life. Targets are selected on the board. |
| `blink` | Opposing Lightning Bolt targeting Elvish Visionary; respond with Ephemerate, with Soul Warden in play | The incoming popup identifies Bolt and its target. Visionary is blinked and survives the invalidated Bolt target, returning with sickness and no damage. Its ETB draws once and Warden gains one life. Ephemerate is exiled for rebound and Bolt reaches the graveyard. The later rebound upkeep is outside this scenario. |
| `combat` | Vampire Nighthawk enchanted with Rancor attacks into Darksteel Gargoyle | Attack declared through board controls; AI blocks. The visible damage allocator accepts one deathtouch damage to the blocker and three trample damage to the defender. Lifelink gains four. Gargoyle survives with one marked damage; Nighthawk dies; Rancor returns to hand. Final life totals are 44 and 37. |

## Additional validation

- `--interactions`: opposing Ponder remains in the rail, explicit review and response preserve priority without another center panel, board mana and Spell Pierce gallery select the exact stack instance, and rail OK resolves the counterspell and closes its notice. An already-reviewed countered spell stays closed even if a different opponent immediately casts another spell.
- `--colorless-payment`: Sol Ring stays visible while pending and resolves automatically; Plains, Forest and Sol Ring pay Forgotten Ancient's `{3}{G}` using W/G/C/C.
- `--decisions`: Evolving Wilds search, Ash Barrens ability selection/cycling, and Azorius Chancery's mandatory land return.
- `bridge/tools/test.ps1`: package succeeded; all 172 Java regression checks passed.
- `client-godot/tools/run.ps1 -Check`: import and all Godot smoke checks passed.

## Reproduction

Run from the repository root in PowerShell, after packaging the bridge:

```powershell
.\bridge\tools\test.ps1
.\client-godot\tools\run.ps1 -Check
foreach ($scenarioName in @('proliferate', 'tokens', 'reanimate', 'protection', 'blink', 'combat')) {
    node client-godot/tools/live-check.mjs "--scenario=$scenarioName" --render
    if ($LASTEXITCODE -ne 0) { throw "Scenario failed: $scenarioName" }
}
```

Omit `--render` for headless runs. Each scenario launches its own Forge JVM and Godot client on an available port, and stops only those owned processes. Existing matches are left untouched. Logs are written to `client-godot/artifacts/scenario-NAME*.log`; rendered captures use `scenario-NAME-1600-STAGE.png`.

Prepared states live in `client-godot/tests/scenarios/`. The bridge's optional `--test-state FILE` startup hook requires an explicit `--deck-file` and applies Forge's own GameState format. Protection and blink seed the opposing spell on the stack rather than relying on an AI casting decision. All subsequent responses, mana payments, target choices, ordering and damage assignments pass through the client and bridge.

## Scope and findings

These runs drive the client's table callbacks and visible decision controls, assert exact resulting life/counters/zones, and capture native screenshots. They do not simulate every physical mouse gesture or prove every Magic interaction. Several uncached card faces use the existing placeholder; artwork download coverage is outside these tests. Infinite loops, replacement-effect prevention, copy/control changes, alternate costs, multiplayer politics and complete games still need dedicated scenarios.

Initial failures were corrected in the test harness: prepared-turn view refresh, deterministic opposing spell setup, board-target selection, numeric ID normalization, stopping before advancing away from a completed interaction, and respecting Forge's stable physical card IDs across blink zone changes. No new gameplay failure remained in the completed cases. Gameplay rules and the normal launcher are unchanged by this test addition.
