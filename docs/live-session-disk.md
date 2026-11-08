# Live session disk

Returning to Main menu no longer ends the Commander match or requires a destructive confirmation. The camera pulls out of the current table, the original deck floppy returns to the carousel, and a second labeled floppy ejects and moves to the right of the PC. Its printed label and caption show the deck name, turn, phase and local life total. Its tooltip describes the current decision. Metadata refreshes while the match is set aside.

The frozen board stays on the CRT while the original deck returns to the carousel. As the session disk emerges from the drive, a 0.70-second channel-change effect rolls the picture, adds horizontal tracking distortion and teal static, and tunes back to the Commander deck console. It starts 0.28 seconds into the session disk's ejection, overlapping its motion to suggest the drive connection is breaking. The controls remain locked until the disk lands. No loading-text screen replaces the board during ejection.

Every return explicitly hides the active deck's carousel face before fading the shelf in, including returns after resuming from a session disk. Its center slot stays empty during flight; the carousel face becomes visible only after the physical disk lands, so the return never overlaps a pre-existing copy.

Clicking the session disk inserts that disk and zooms back into the same Godot game scene, live adapter, Forge JVM and session. The game is reparented through the existing temporary render viewport for the transition. It is not reloaded. The existing pending decision remains available. Menu navigation and editor drafts work independently of the retained game.

The hidden game scene has processing/input disabled so its keyboard shortcuts and dialogs cannot intercept menu/editor controls. Application pumps the same adapter connection in the background, allowing state and callbacks to keep synchronizing. Forge may continue until it needs human input; this is not a rules-engine pause. Periodic owned-session status checks detect engine failure. Status replies are bound to the launch generation so delayed replies from an ended match cannot replace a newer game.

The application currently supports one live match. Play for other decks remains disabled until the parked match is resumed or explicitly ended. End Game is available beside the session disk and in the game rail; it asks for confirmation, stops the exact owned engine and removes the session disk. Cancel keeps the match. Quitting protects unsaved editor drafts and ends a parked match as well as a visible one.

This is retention within the open application session. The disk is not a persistent game file and does not survive closing the application.

Implementation: `Application.gd` owns parked state, background polling, launch-key response guards and retained-scene transitions. `SessionDisk.gd` prints live metadata onto the existing procedural floppy face and exposes Resume/End controls. `ComputerMenu.gd` coordinates the two ejections and session insertion; `ComputerWorld.gd` reuses the physical disk shell with the appropriate face/color.

Validation: `node client-godot/tools/app-check.mjs --render` checks two-disk ejection, unchanged engine PID/session/game object, retained pending decision, editor navigation, background refresh, resume at a smaller window size, cancel/end cleanup, fresh game ownership, stale-status rejection and quitting with a parked game. Captures include `app-menu-session-disk.png`, `app-menu-session-disk-1280.png`, `app-session-disk-ejection.png` and `app-resumed-game.png`.

## Confirmed FORMAT A: deletion

**Superseded (2026-10-30):** the wipe now plays on the CRT only. No floppy is ejected or inserted, so the label strike-through and drive-contact trigger below no longer run. After the zoom-out the monitor tunes to the console and `FormatLog` starts directly, with amber activity. The stop, cleanup gating and timeout behaviour below still apply.

Both End Game entry points keep their confirmation. On confirmation, Application freezes session name/turn/phase/life, disables the retained table, and issues one owned `match.stop`. Its response frees the game and clears session ownership immediately, independently of animation completion. Outstanding status replies cannot revive the cleared launch generation.

From the table, the existing pullback and saved-deck/session ejections run first. The now-parked session then follows the exact same format insertion as a deletion started from home. The saved deck returns intact to its carousel; it is never the formatted source.

The normal `ComputerWorld.insert_deck` motion takes the session disk to the drive. Four local shader strokes cross out TURN, phase, LIFE and CLICK TO RESUME, 130ms apart, without changing the shared 512px face. Drive contact starts `FormatLog.gd`, a small subclass sharing `MatchBootLog` typing, dots, delayed OKs, bounded text rendering and activity pulses. It uses the shared `TerminalMeter`; its final engine OK and 100% wait for the actual stop acknowledgment. After eight seconds without acknowledgment the visual warns and finishes; ownership cleanup still handles a late response and new PLAY remains blocked while stop is unresolved.

The drive LED uses amber for format activity, then returns to idle. SESSION ERASED holds for 650ms; the monitor cuts back to the unchanged deck console. The disk is consumed, with no ejection or dust flourish. The entire format sequence is silent: no audio resources or audio players are created. PLAY, SETTINGS, carousel, editor, light switch and resume are blocked during formatting. Reset cancels the insertion and clears its disk, terminal, local face uniform and activity states; the stop response still cleans up the match.

`FormatLogChecks.gd` covers real cleanup gating and the warned timeout. `ApplicationIntegration.gd` verifies confirmation/cancel, exactly one stop response, cleanup before visual completion, saved faces, consumed disk, empty drive, restored inputs and absence of audio players. `FormatSequenceChecks.gd` covers interruption/resize and captures approach, entering, progress, erased and empty stages at 1280x800 and 1600x1000 in light and dark mode (`artifacts/format-WIDTHxHEIGHT-MODE-STAGE.png`). Run `node client-godot/tools/app-check.mjs --render` for this matrix and the real-engine end paths.

The headless fixture measures 3.20-3.21 seconds for the format sequence with cleanup ready, including the final hold. Saving native screenshots adds capture overhead. The existing table-to-home return runs before this sequence. `artifacts/format-review.png` contains the twenty-frame contact sheet.

Changed files:

| File | Change |
| --- | --- |
| `scripts/app/Application.gd` | Confirmation starts one owned stop alongside presentation; acknowledgment clears the game/session independently. Late stop/status replies cannot affect a newer launch. A slow acknowledgment reconciles through status without replaying Stop. |
| `scripts/app/ComputerMenu.gd` | Shared format sequence after normal home return; drive-contact terminal swap, input locks, final hold/console restoration and interruption cleanup. |
| `scripts/app/ComputerWorld.gd` | Existing insertion accepts a format presentation flag; local strike-through uniform and amber log-driven LED. Old erosion launch removed. |
| `scripts/app/SessionDisk.gd` | Separately positioned state lines provide stable presentation coordinates for the four strike-throughs. |
| `scripts/app/InsertionNightLighting.gdshader` | Four animated local strokes; zero-effect defaults preserve normal insertion. |
| `scripts/app/MatchBootLog.gd` | Extracted header/row drawing and configurable typing timings/caps; normal boot defaults stay identical. |
| `scripts/app/FormatLog.gd` | Small boot-terminal subclass for session erase metadata, shared block meter, cleanup gate and warned timeout. |
| `scripts/app/DiskDisintegration.gd` | Retired, including its procedural audio generator; old unit check retired too. |
| `scripts/ui/Main.gd` | Smoke suite invokes the replacement `FormatLogChecks.gd`. |
| `tests/ApplicationIntegration.gd` | Both confirmed end paths, exact stop count, stale stop guard, unchanged deck faces, silence and final state. |
| `tests/FormatLogChecks.gd`, `tests/FormatSequenceChecks.gd` | Gate/timeout regression plus light/dark capture matrix, resize and interruption. |
| `AGENTS.md`, this document | Current lifecycle and file-map documentation. |

Verification completed:

- `node client-godot/tools/app-check.mjs --render`: passed, including both real-engine end paths and all twenty capture frames.
- `node client-godot/tools/app-check.mjs`: passed; format fixtures measured 3.20-3.21 seconds without screenshot overhead.
- `node client-godot/tools/library-check.mjs --render`: passed.
- Extended 3600-frame headless `--smoke`: passed.
- `client-godot/tools/run.ps1 -Capture`: passed.
- The timeout unit check intentionally logs its warning. One concurrent full-render attempt encountered Forge's existing `Bot 2 needs a valid Commander deck` failure while generating Talrand, before formatting; the isolated full-render rerun passed. No Java changes were made.
