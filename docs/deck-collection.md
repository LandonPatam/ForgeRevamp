# Forge deck collection and editor

Clicking **Deck Editor** scrolls the home screen upward over 0.65 seconds, bringing its existing floppy carousel to the top and revealing the selected deck's cards underneath. Choose a floppy to edit that deck. **Main menu**, in the same header position, reverses the motion and preserves the current draft. Opening the editor does not start or attach to a match.

The editor carousel stops at both ends. Its final item is a blank floppy with a **+** symbol that opens deck creation/import. The home carousel continues to loop. Navigation remains active while deck data and artwork load: cached decks display immediately, newer selections supersede older requests, and card images fill in asynchronously.

The editor shares the home screen's gray/teal room, grain, monospace typography, floating disk carousel and light/dark preference. The old sidebar collection screen is removed. The card grid uses the full width beneath the carousel, with responsive card density, filtering and a compact editing toolbar.

## Open the screen

After packaging the bridge, run from the repository root:

```powershell
.\bridge\tools\test.ps1
.\client-godot\tools\run.ps1 -Decks
```

In Git Bash / Anaconda Bash:

```bash
bash ./client-godot/tools/run.sh -Decks
```

The application library uses port 7778 by default. `-Port` chooses another port. Use **Main menu** to move between the editor and Commander setup in the same window. Closing the application cleans up its library and any owned match; existing unrelated matches remain independent.

## Saved deck text encoding

The library and match loader read UTF-8 decks, UTF-8 with a BOM, older Windows-1252 decks and BOM-marked UTF-16 decks. UTF-8 decoding is strict before the Windows fallback, preserving names such as Troll of Khazad-dûm, Grishnákh and Lord of the Nazgûl instead of introducing replacement glyphs that break artwork lookup. Reading does not rewrite the saved file. Existing native saves still use Forge's serializer.

## Controls and supported operations

- Editor floppies keep the same size as the main-menu carousel at the same window size. Right-click a saved deck's floppy in either view to choose one of eight shell colors, enter a custom color, or reset its default. Colors are local cosmetic preferences saved per deck in `user://deck-floppy-colors.cfg`; they do not dirty or alter the Forge deck file. The blank new-deck floppy retains its neutral shell.
- Forge's bundled official Commander precons (180 in the pinned Forge, `forge-gui/res/quest/commanderprecons`) appear after your saved decks. **ALL / CUSTOM / PRECONS** in the header filters the shared home/editor carousel and is remembered between launches. Precons are read-only: edit freely, then **Save as copy** writes a new custom deck (the filter switches to CUSTOM to show it). Precons cannot be deleted. Off-screen floppies build their face and request cover art only when first shown.
- Choose a deck from the carousel to see its cards. Quantities are grouped; commanders sort first, followed by mana value and name. Hover magnifies cards; click opens details. Right-click offers View card, Add a copy, Remove one, Remove all copies, Change artwork, and moves to Commander/Main/Sideboard. Artwork opens a paginated printing gallery and preserves quantities and section when replaced.
- Lands, nonlands and average mana appear beside **+ Add Cards**. The grid uses the remaining page height without a footer or page buttons; every distinct deck entry is available by scrolling. Hover the deck count for its validation message.
- The **Cards per row** slider in the filter toolbar adjusts between 1 and 12 cards, with Auto at the far left. Cards resize immediately in both Deck and Add Cards views. The preference is saved after dragging stops and restored next time.
- **+ Add Cards** opens a compact search popup over the current deck. It starts empty; search a name or rules text, with exact names ranked first. Results appear six at a time with thumbnails/rules and individual Add buttons. Choose Main, Commander or Sideboard as the destination. Add several cards without leaving the popup, then use **Done — back to deck**, × or Escape. The page underneath always remains the deck's own cards.
- **Set as commander** (or moving a card into Commander) designates one copy and returns the previous commander to Main. **Add as second commander** preserves the first for partner/background builds. Commander cards have a visible badge and update the floppy cover. Beside average mana, a green light and **Legal** indicate a validated Commander deck. Unchecked or invalid drafts show a yellow **Validate** button, with a spinner while Forge checks. Successful checks switch directly to Legal; failed checks show the first outstanding problem and retain Validate. Edits require another check. Validation does not require saving; invalid drafts remain editable.
- Use **New / import** to create a blank deck, duplicate the current deck, paste a clipboard list, choose a native `.dck` or text file, or supply a supported deck URL. URL import delegates to Forge's `DeckUrlLoader` (Moxfield, Archidekt, TappedOut and MTGGoldfish). Network/provider access and private deck restrictions still apply.
- Imports can create a new draft, merge into the selected draft, or replace its cards. Preview shows recognized cards and rejected lines before applying. Forge's importer handles printing preferences, core/expansion filtering, smart art selection, banned/restricted inclusion and printing-date limits. Native `.dck` files preserve their explicit printings.
- Change the deck name, add/remove quantities, move entries between sections, choose a printing, and undo/redo edits. **Save deck** or **Ctrl+S** writes to the installed Forge Commander deck directory. Incomplete or illegal decks can be saved; Forge's conformance message explains the first outstanding issue.
- **Deck actions** offers clipboard/native export and **Delete deck**. Deletion names the selected deck and requires confirmation; cancellation retains the file and draft. Changed-on-disk versions and paths outside the library are rejected. Deleted native files leave the active carousel and are retained under the library's `.forgeui-trash/` directory with a `.deleted` suffix. New, unsaved decks have no saved file to delete.
- Changes remain in a draft until saved. Switching decks, importing into a new draft, and closing the screen protect unsaved edits. Existing deck saves check the file hash and reject overwriting a file changed elsewhere. Native standard metadata survives edits and duplication. New decks cannot overwrite a same-named file.

Artwork resolves by the exact printing, first from bundled images, then Forge's image cache, then an on-demand download using Forge's image URL builder. Downloaded images are cached in Godot's `user://library-art/` directory. Cards remain searchable/editable using their rules metadata while artwork is missing or downloading. The match renderer's existing artwork behavior is unchanged.

Image URLs retain the exact set, collector number and face without forcing an English-language printing. Scryfall can therefore serve Japanese-only printings such as Secret Lair Plains 46 and Swamp 48. Library and runtime card artwork share this URL policy.

Match artwork warms without blocking startup. A shared queue prioritizes visible stack/decision cards and hands, then battlefield/command cards, ahead of background faces. Warmup starts with commanders and inexpensive cards, deferring repeated printings of the same name. A stalled background transfer can yield its slot to a visible card, then resume later. Failed visible images retry after a cooldown. Gameplay may use a cached printing of the same card and face until its exact printing arrives, updating the existing card without a new snapshot; editor printing choices remain exact. Hidden faces and front/back identities remain protected.

Card-name and rules-text searches ignore case, punctuation and spacing in both Add Cards and the current-deck filter. For example, `TChalla`, `T Challa` and `T’Challa` find `T'Challa`. Normalized exact names rank ahead of partial-name and rules-text matches; saved names and printings retain their original spelling.

This initial editor targets the Commander library. It exposes all installed common and variant cards and all Forge deck sections; it does not implement Quest inventory, drafting, deck generators, additional format editors or full desktop Forge UI parity. Alternate faces are included in rules text; an alternate-face image viewer is still future work. Updating the pinned Forge/assets determines which new cards and printings exist.

## Implementation

Match warmup cycles through mana values 0–3 after commanders, so a combined deck manifest does not exhaust all land artwork before starting cheap spells. Stack/decision faces and newly public battlefield faces have a separate urgent tier above existing hand artwork. If all download slots are occupied, an urgent face can replace the youngest nonurgent transfer without the normal 750ms age threshold; interrupted images remain queued. The four-download limit, global start interval, bounded lookups/decoding, hidden-face guards and nonblocking match creation remain in force.

Deck details arriving during a carousel move preserve its current animation position. Descriptive cover updates do not redraw unchanged floppy faces. First-time editor artwork decoding and cache writes run in background workers, with texture publication limited to one completion per frame.

Validation failure reasons appear inline beside the yellow Validate button and wrap within the toolbar. They clear when the draft changes or validation succeeds; no validation-result popup opens.

- `bridge/.../LibraryMain.java`: standalone loopback WebSocket service; serialized library worker; no match/controller operations.
- `bridge/.../DeckLibrary.java`: full common/variant catalog, printings, draft validation, Forge importer/URL loader, native serialization, safe library-relative IDs and conflicting-save protection.
- `client-godot/scenes/DeckCollection.tscn` and `scripts/library/`: native collection UI, reconnecting request client, exact-printing artwork cache and card/deck tiles.
- `client-godot/tools/library.ps1`: owns the library JVM and collection window. `run.ps1 -Decks` routes here.

## Verification

```powershell
node client-godot/tools/library-check.mjs
node client-godot/tools/library-check.mjs --render
node client-godot/tools/library-check.mjs --render --online-images
# Launcher aliases:
.\client-godot\tools\run.ps1 -Check -Decks
.\client-godot\tools\run.ps1 -Capture -Decks
```

The integration test creates isolated native decks under `client-godot/artifacts/library-fixture-*`, starts its own library service on a free port, and stops only its owned processes. It never saves into the installed deck library. Offline runs disable new artwork downloads; the optional online run additionally checks loading an Alpha Sol Ring image.

Verified on 2026-10-24: 34,088 unique Forge cards, selection of existing decks, responsive 1600×1000/1280×800 card grids, hover preview, import options/preview with unknown-card warnings, native import/save/export, quantities, undo/redo, printing replacement without quantity loss, metadata-preserving edits and duplication, unsupported URL errors, path rejection and externally changed file protection. Native rendered screenshots are saved as `client-godot/artifacts/library-*.png`. The optional artwork check passed. Successful public deck imports from each external provider have not been independently exercised here; those use the installed Forge loader. Bridge checks (172) and the existing game client smoke checks also pass.
