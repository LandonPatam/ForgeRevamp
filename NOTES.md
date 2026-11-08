# Session notes - 2026-11-08

## Current state

- `main` (`f5a2bb9`) includes the repo cleanup: dead scripts/assets removed, `assets/cards/` excluded from exports (game pack ~115 MB -> 5.1 MB; art downloads at runtime), old handoffs moved to `docs/archive/`, `check.mjs all` runs every scenario, live waits fail after 30 s of no progress. Merged at the user's request before Mac validation.

- `main` includes `fix/online-ready-and-phase-sync` (`94ba757`). A host who picked a disk (selected-deck "commander" view) before readying never auto-launched once everyone was ready; it now launches from that view too. Bots never needed readiness; this was the bot + friends "waiting for players" hang.
- Online phase stops: on another player's (or bot's) turn a seat no longer stops at every empty-stack step just because it holds an instant/ability. Other players' rows default unchecked; explicit stops, stack responses and required declarations remain. Own-turn defaults and solo bot games are unchanged.
- Windows checks passed: bridge regression (445), online-check (73), solo-phase-check, rendered app-check (now adds a bot through Settings, readies from the selected-disk view and verifies automatic launch; reproduced the hang without the fix).
- User reported the branch working in their own Mac testing on November 4 (exact commands not supplied); accepted for merge. UI-scale work (`e3cda90`) remains on `main` with prior acceptance.

## Known issues

- Scenarios `blocking` (bridge NullPointerException while building the snapshot; likely a real bug) and `insights` (stuck on a Forge message prompt during board setup) fail; pre-existing, not yet investigated.
- Not yet verified after the cleanup: Mac checks, and a full `package.ps1` / `package-macos.py` rebuild with app-check against the exported build.

- The phase desync was diagnosed from code and the unit rule, not reproduced live; confirm in further cross-platform play with real instant-holding decks.
- Mac builds are ad-hoc signed; friends must use Open Anyway. Distribute a DMG or a `ditto`-zipped packaged `.app`, never a dev export. Everyone online needs the same build.
- Run local lobby suites serially and launch the actual JVM rather than the Windows PATH shim. Preserve existing processes and the original Mac checkout/backup.

## Next steps

- Both machines update to current `main` (`git pull --ff-only`) and rebuild packages before sharing with friends.
- Continue live Windows/Mac play in both host/join directions; report any remaining online issue on a new fix branch.
