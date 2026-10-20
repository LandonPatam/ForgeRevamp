# ForgeUI

Personal modern UI for MTG Forge (Commander vs AI, Commander online with friends on stock Forge).

## Layout
- `forge/`: upstream Card-Forge/forge, **unmodified**, checked out at the commit in `FORGE_COMMIT` (not tracked here).
- `bridge/`: (coming) Java module implementing `IGuiGame`, which serves game state and prompts as JSON over WebSocket.
- `ui/`: (coming) Electron + React/TS frontend.

## Setup
```sh
git init forge && cd forge
git remote add origin https://github.com/Card-Forge/forge.git
git fetch --depth 1 origin $(cat ../FORGE_COMMIT) && git checkout FETCH_HEAD
../.tools/apache-maven-3.9.9/bin/mvn -DskipTests -pl forge-gui-desktop -am install
```

## Updating to a new snapshot
Find the commit of the snapshot build (GitHub Actions run "Create Snapshot Desktop and Android", head_sha), put it in `FORGE_COMMIT`, re-fetch and rebuild. Friends must be on the same snapshot for online play.
