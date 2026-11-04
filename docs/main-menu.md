# Main menu and Commander startup

Package the bridge once, then open the application from the repository root:

```powershell
.\bridge\tools\test.ps1
.\client-godot\tools\run.ps1
```

Git Bash / Anaconda Bash:

```bash
bash ./client-godot/tools/run.sh
```

The main menu presents a green-on-black Commander terminal on a 3D computer, with Home/Deck Editor/Quit in its header and saved decks in a floating floppy carousel below. Clicking or swiping a deck smoothly raises and enlarges it beneath the computer. The physical Play key on the lower-left front panel depresses and starts the disk-insertion/monitor-zoom transition. See [computer menu](computer-menu.md) for controls, implementation and the current visual scope. Initial startup uses a teal-on-black ForgeCheck diagnostic terminal with bordered configuration panels, real service status and a segmented bottom loading bar; completed system checks pull back seamlessly to reveal that same live terminal on the PC monitor, then tunes into the deck console. The editor/game retain their existing styling.

## Match settings terminal

The cog opens a teal-on-black roster terminal with numbered player slots, monochrome teal Forge portraits, underlined callsign fields and separate deck / remove columns. Click a portrait to change it, edit a callsign directly, or choose a deck source in that player's row. The empty slot adds a bot; matches still support one human and one to three bots. The footer offers Cancel and Save & return. Keyboard controls include F2 to add a bot, Delete to remove the selected bot when a name field is not being edited, arrow keys to select rows / cycle deck choices, and F10 to save.

Settings entry and exit move the camera toward fixed, depth-tested CRT glass. The screen mesh stays at its physical size throughout; it no longer grows over the monitor bezel. Near the fullscreen handoff, screen-space sampling blends in to match the full settings viewport without stretching the hardware. Exit reverses that mapping as the camera pulls back and the CRT retunes to the deck console. The key visibly rebounds and presents a fully raised frame before settings construction and camera movement. The settings viewport then renders while the CRT retune and zoom run together.

## Startup feedback

The launcher opens the Godot window before waiting for Java/Forge initialization. The diagnostic screen shows the actual stages: loading Forge/card rules, building the catalog, and opening saved decks. Its segmented percentage eases forward between real milestones, slowing toward a ceiling during long stages. Service labels still reflect actual readiness; only a successful deck-library connection authorizes the final smooth fill to 100%. The animated indicator, elapsed time and Quit remain available while waiting. The menu (or `-Decks` editor entry) opens after the first saved-deck response succeeds.

`LibraryMain --startup-status FILE` atomically publishes milestones before its WebSocket server exists. The launcher creates a unique status file in artifacts for each launch and passes it to both processes. Startup errors stay on screen until the user closes it. The launcher allows up to 180 seconds for library startup.

Commander Start immediately warms the selected deck's artwork in the background and begins disk insertion after the PLAY key rebounds. Forge publishes all actual opponent deck printings, including generated decks, into the same background queue. Artwork never opens a loading screen, delays match creation or produces a blocking retry popup. The deck console stays visible until the floppy reaches the drive and starts its FORGECHECK boot log using that disk's name, commander, card count and configured player names. Dots lead into delayed OK markers; the block meter matches the deck console and the drive LED flickers with the printed log. Engine and live-table readiness gate the final steps, so elapsed time cannot finish a boot. A blinking block cursor, quick teal flash and READY. ENTERING TABLE... beat precede the existing table materialization and camera zoom. Resuming a session uses live-engine/recovery wording and preserves the existing game and pending choices.

## Navigation

- **ALL / CUSTOM / PRECONS** beside the Forge badge filters the floppy carousel between your saved decks and Forge's official Commander precons. A legal precon can be played directly; the match receives an exact temporary copy of its deck file. The same filter applies in the deck editor.
- The **Commander terminal** shows the disk name, commander, color identity, average mana value, ASCII mana curve, card-type counts and Forge's validation result. Select a legal saved deck using the floppy carousel, then click the physical **Play** key on the front of the case. Brighter text, closer framing and a safe inset keep the information readable within the rounded CRT glass. A **FIND>** bar along the bottom of the screen searches decks: just start typing on the home screen (or click the bar). Matching is by deck name or commander, every word must match, and it combines with ALL/CUSTOM/PRECONS. The first match is selected; Backspace edits, Ctrl+Backspace or Escape clears, and Enter commits the search so the next Enter presses Play.
- The **cog beside Play** zooms into Commander match settings on the monitor. Add or remove bots for two to four total players. Each bot can use your selected deck, another legal saved deck, a **Commander precon**, a deck built around a chosen commander from Forge's **Random Commander decks** list, or a fully random Commander deck generated by Forge. The two Forge lists open searchable pickers; precons use their supplied deck lists, while a selected commander gets a freshly generated deck at match start. The selected source and deck persist with each bot. Precons that fail Forge's current Commander legality check remain listed but cannot be selected. Rename yourself and the bots, choose from Forge's 126 default avatars or import an image, then **Save & return**. These preferences persist between launches and apply to the next match; Cancel discards changes. A parked match keeps its existing players and decks.
- **Deck Editor** scrolls the room upward, bringing the same floppy carousel to the top and showing the selected deck's cards beneath it. Selecting another floppy changes the editor deck, with an unsaved-changes prompt when needed. Right-click cards for copy/removal, artwork and section actions. The header's **Main menu** button reverses the transition without discarding the current draft. Light/dark appearance follows the home room. Games use saved deck files; save edits before selecting them for play.
- The game rail has **Main menu**, which keeps the live match open. The deck floppy ejects into the carousel, then a labeled session disk ejects to the side. Click that disk to resume the same table and pending decision. The deck editor remains usable while the match is set aside. **End game**, available in the rail and beside the session disk, separately confirms ending the owned match. A new game can start after ending the current one.
- Closing the application asks before discarding unsaved editor edits or ending a game. Confirmed quit stops the owned game before closing.

After **End game** succeeds, the session floppy disintegrates. From the table, the PC returns the deck safely, displays GAME OVER and ejects the save into a floating position. From the main menu, the side save lifts into that same position. A ragged erosion edge travels from top to bottom through both the label and the plastic shell. Hundreds of tiny fragments retain their original colors as they curl outward, shrink and fade, with a soft granular sound and a lingering dust trail. The carousel stays still during destruction and becomes available again after deck validation. Canceling or failing to stop the match preserves the save; quitting uses normal process cleanup without the destruction sequence.

`run.ps1 -Decks` still opens directly into the editor, now with navigation back to the menu. `-Live -Deck "Atraxa"` and `-Connect` remain direct match entry points. `-Mock` opens the standalone mock table. Existing smoke, screenshot and live integration arguments continue routing to the table scene.

## Battlefield presentation

The local mana and phase controls share a narrower 64 px visual width in the existing left lane, with 12 px outer margins, an 18 px gap between groups and at most 90% scale. Phase buttons keep their natural height instead of stretching to fill the remaining field.

Each Command, Graveyard and Exile bubble opens a terminal menu on that player's own board. The menu expands from the clicked icon, follows that board when scrolling or resizing, and fits its available width/height. Empty zones show a compact NO CARDS message. Local card dragging/casting, full-size hover inspection, close/toggle behavior and opponent read-only permissions remain in use.

During the opening-hand decision the battlefield fan stays absent, including when viewing the board or awaiting London bottom-card choices. It appears only after Forge accepts Keep and the final bottom selection. Reconnecting to an established match retains its normal hand.

## Process ownership

Entering match settings finishes the physical key release first; entering and leaving then play the CRT retuning effect during the zoom. Save & return and Cancel both retune to the deck console during the pullback. Menu input stays locked until the transition completes.

The launcher owns a library/application service on port 7778 by default. Each requested game runs as one separate child Forge JVM on a free port, with one to three AI seats. Saved deck files are validated and resolved relative to the library before launching. Forge generates bot decks and publishes a combined, deduplicated printing manifest without waiting for images. `match.status` includes that manifest until the owner/session-bound `match.artworkSeen` acknowledgment; this acknowledges delivery only and never gates play. The manifest contains no shuffled order or hidden-zone assignment. Duplicate launch retries return the same owned session. Stop requests require the application identity and exact session; during preparation only, the exact launch key can cancel a pending Start before its session acknowledgment arrives. Stop never accepts process IDs.

Leaving/quit stops only that child. Existing unrelated matches are unaffected. The child also watches its application-service parent so killing the launcher/service cannot leave an orphan engine. The launcher retains its existing cleanup of the owned library process when the Godot window exits. `-Port` changes the application service port; match ports are allocated automatically. Game logs are under `client-godot/artifacts/app-sessions/`.

## Verification

```powershell
node client-godot/tools/app-check.mjs --render
node client-godot/tools/app-check.mjs --render --startup-failure
.\bridge\tools\test.ps1
.\client-godot\tools\run.ps1 -Check
```

The application check uses an isolated deck directory and real library/game services. It launches the client first and starts Forge only after the loading screen is visible. It verifies progression into the menu, menu/editor navigation and retained unsaved edits, valid/unfinished deck handling, the game-loading indicator, actual opening-hand decisions and a three-player table with the selected commander, duplicate-start protection, mismatched-session rejection, cancel/leave, a fresh second game, quit cleanup with an unsaved draft, and that both owned game PIDs exited. The failure variant uses an invalid library location to produce a real initialization error and checks the visible error/quit flow. Main menu and Commander setup fit at 1600×1000 and 1280×800. Native screenshots are `artifacts/app-*.png`, including app-startup-loading, app-startup-error and app-game-loading.

Verified on 2026-10-24: application integration, existing standalone library integration, direct-game `--colorless-payment`, 172 bridge checks and Godot smoke checks all pass. The original confirmation test was adjusted by explicitly hiding canceled/confirmed dialogs during cleanup, preventing overlapping exclusive windows when actions occur in the same frame.
