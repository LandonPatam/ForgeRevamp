# ForgeUI

Personal modern UI for MTG Forge (Commander vs AI, Commander online with friends on stock Forge).

## Layout
- `forge/`: upstream Card-Forge/forge, **unmodified**, checked out at the commit in `FORGE_COMMIT` (not tracked here).
- `bridge/`: Java module implementing `IGuiGame`. It runs Forge headless and serves game state and prompts as JSON over WebSocket, plus a bare test page.
- `ui/`: (coming) Electron + React/TS frontend.

## Setup
```sh
git init forge && cd forge
git remote add origin https://github.com/Card-Forge/forge.git
git fetch --depth 1 origin $(cat ../FORGE_COMMIT) && git checkout FETCH_HEAD
../.tools/apache-maven-3.9.9/bin/mvn -DskipTests -pl forge-gui-desktop -am flatten:flatten install
```

## Updating to a new snapshot
Find the commit of the snapshot build (GitHub Actions run "Create Snapshot Desktop and Android", head_sha), put it in `FORGE_COMMIT`, re-fetch and rebuild. Friends must be on the same snapshot for online play.

`flatten:flatten` matters: without it the installed poms keep `${revision}` and `bridge/` can't resolve Forge.

## Running the bridge (Phase 1 spike)
```sh
cd bridge
../.tools/apache-maven-3.9.9/bin/mvn -DskipTests package
sh run.sh --deck "Sauron" --opponents 3
```
Open http://127.0.0.1:7777/. Decks come from Forge's normal Commander deck folder (`%APPDATA%\Forge\decks\commander`); AI opponents use your other decks. `node tools/probe.mjs` prints a text summary of the live game (dev tool).
