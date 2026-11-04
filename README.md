# ForgeUI

Native Godot Commander frontend using Forge for game rules, with local bots and host-authoritative online play between friends running ForgeUI. Stock Forge clients cannot join a ForgeUI match.

## Shared Windows and Mac development

Source lives in [LandonPatam/ForgeRevamp](https://github.com/LandonPatam/ForgeRevamp). Both platforms share one main branch; features and platform fixes use short-lived branches. See [the development workflow](docs/development-workflow.md), including the one-time Mac reconciliation instructions. The Windows baseline and Mac compatibility work are reconciled on `chore/mac-reconciliation`; merge after affected checks pass on both platforms.

## macOS app

`python3 client-godot/tools/package-macos.py` builds a universal app and DMG with separate Apple Silicon and Intel Java 17 runtimes. Drag ForgeUI.app to Applications. See [build setup and signing](docs/macos-build.md).

## Layout
- `forge/`: upstream Card-Forge/forge, checked out at `FORGE_COMMIT` (not tracked here), with tracked local patches described in [FORGE_PATCHES.md](FORGE_PATCHES.md).
- `bridge/`: Java module implementing `IGuiGame`. It runs Forge headless and serves game state and prompts as JSON over WebSocket, plus a bare test page.
- `client-godot/`: Godot 4.7.2 application and Commander table for up to four players, with mock and live Forge adapters.
- `docs/`: bridge audit and the current local JSON protocol contract.

## Godot prototype

Run `.\client-godot\tools\run.ps1` (Bash: `bash ./client-godot/tools/run.sh`) to open the shared main menu. Select a saved deck and use **Play** to start Commander, or open **Deck Editor**. The cog beside Play configures one to three bots, their saved decks, Forge Commander precons, decks generated around a selected commander, or fully random Forge-generated decks, and everyone's names and profile pictures. See [main menu and Commander startup](docs/main-menu.md).

Open the Forge-backed deck editor with `.\client-godot\tools\run.ps1 -Decks`, or `bash ./client-godot/tools/run.sh -Decks` in Bash. Deck Editor scrolls the home carousel to the top, with the selected deck's cards underneath. Right-click cards for copy, removal, artwork and section actions. New / import creates, duplicates and imports decks. See [deck collection](docs/deck-collection.md) for controls and tests.

Run `.\client-godot\tools\run.ps1 -Live` to start a real Commander match directly against two AIs, using your installed Commander decks. Add `-Deck "Sauron"` to select your deck. Closing the Godot window stops the engine started by this launcher. The bridge must be packaged first with `.\bridge\tools\test.ps1`. Use `-Mock` for the standalone mock table. See [client-godot/README.md](client-godot/README.md) for controls, setup, boundaries, and verification commands.

In Git Bash / Anaconda Bash, run `bash ./client-godot/tools/run.sh -Live` for a direct match. Omit `-Live` for the main menu, or use `-Mock` for the mock. To attach to an existing three-player bridge, use `-Connect` instead of `-Live`; `-Port` selects its port.

## Setup

Install Git, JDK 17, Maven and Godot 4.7.2 (plus its export templates for packaging). Windows scripts default to portable tools under `.tools/`; use the script-specific environment overrides for tools installed elsewhere. On macOS, `bash client-godot/tools/run.sh` starts the app and its owned Java service; `-Decks`, `-Mock`, `-Live`, `-Connect`, `-Editor`, `-Check` and `-Capture` select the corresponding source workflows. See [macOS prerequisites and packaging](docs/macos-build.md).

After cloning this repository, fetch the pinned Forge source and apply its local patches:

```sh
git init forge && cd forge
git remote add origin https://github.com/Card-Forge/forge.git
git fetch --depth 1 origin $(cat ../FORGE_COMMIT) && git checkout FETCH_HEAD
git apply --check ../forge-patches/netplay-fixes.patch
git apply ../forge-patches/netplay-fixes.patch
../.tools/apache-maven-3.9.9/bin/mvn -DskipTests -pl forge-gui-desktop -am flatten:flatten install
```

The Maven path above is the Windows portable installation; substitute your Maven executable on Mac. Apply the patch once to a fresh pinned checkout. Preserve existing Forge edits when working in an established checkout; see [FORGE_PATCHES.md](FORGE_PATCHES.md).

## Updating to a new snapshot
Record the new upstream revision in `FORGE_COMMIT`, re-apply and verify the local patches as described in `FORGE_PATCHES.md`, then rebuild. Online friends should use builds from the same ForgeUI commit and Forge revision.

`flatten:flatten` matters: without it the installed poms keep `${revision}` and `bridge/` can't resolve Forge.

## Running the bridge (Phase 1 spike)
```sh
cd bridge
../.tools/apache-maven-3.9.9/bin/mvn -DskipTests package
sh run.sh --deck "Sauron" --opponents 3
```
Open http://127.0.0.1:7777/. Decks come from Forge's normal Commander deck folder (`%APPDATA%\Forge\decks\commander`); AI opponents use your other decks. `node tools/probe.mjs` prints a text summary of the live game (dev tool).

For a three-player match in PowerShell, after packaging:

```powershell
cd D:\ForgeUI\bridge
java -Xmx4g -cp "target/classes;target/lib/*" forgeui.bridge.BridgeMain --assets ../forge/forge-gui --opponents 2
```

The bridge requires protocol v2 metadata for actions/answers; the bundled browser page and probe are updated. See [docs/protocol.md](docs/protocol.md) for Godot integration, reconnect behavior, validation, and remaining gaps. Forge remains authoritative; local upstream patches are recorded separately in `FORGE_PATCHES.md`.

Run checks from the repository root:

```powershell
.\bridge\tools\test.ps1
node bridge/tools/client-checks.mjs
node bridge/tools/smoke.mjs
```

`test.ps1` packages offline using the existing Maven cache, then explicitly runs the dependency-free Java regression harness (plain Maven test discovery does not run it). `client-checks.mjs` checks browser protocol/recovery logic without launching a browser. `smoke.mjs` starts its own JVM on an available local port, exercises a real three-player AI match's protocol, then stops that process. It requires the same Forge assets, installed dependencies, and Commander decks as normal startup. `FORGE_SMOKE_PORT` can select a specific port. Set `FORGE_SMOKE_SCREENSHOT` to an absolute PNG path to also capture the browser test page using headless Edge (`FORGE_EDGE_PATH` overrides the browser executable). These checks do not establish complete spellcasting or combat coverage.
