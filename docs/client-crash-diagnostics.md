# Client crash capture

The diagnostic renderer packages enable `application/config/client_diagnostics=true` in its exported project settings. Normal source defaults remain unchanged. `Main.gd` creates `ClientDiagnostics.gd` only for enabled, non-verification runs.

Files are local under `user://client-diagnostics`:

- `session.json`: engine, renderer, executable and initial layout.
- `snapshot-0.json` / `snapshot-1.json`: alternating last two normalized client states, written and flushed before `_apply_state`, with sequence, time and layout sizes.
- `layout-storm.json`: first observed sort/resize storm (128 events for a watched node/event in one process frame), containing event counts, node paths and layout.
- `previous-*`: the equivalent files from the preceding table session. A new session rotates the known files; it never deletes decks or artwork.

To investigate a recurrence, preserve this folder and the macOS IPS report before another table replaces the relevant session. The snapshot's `state` is suitable for a frontend-only `_apply_state` fixture; use `layout_before_apply.table_size` and the recorded scroll dimensions when replaying. Captures contain the same state available to the local client. They make no network requests and are not uploaded.

The current package is built with `artifacts/build-opengl-diagnostics.py`. This replaces only the verified OpenGL app after staging and checks. The capture is diagnostic evidence, not a fix for the reported queue overflow.

## Preventative layout guard

Both current renderer packages include `LayoutLoopGuard.gd`. It catches a scroller being sorted 64 times within one process frame, suspends automatic scroll sizing and table presentation, and shows a recovery prompt. Network polling continues through the same adapter; stale game actions are blocked while incoming state is retained. Retry restores normal sizing and displays the newest snapshot. If the condition persists, the guard pauses again. Returning to the main menu parks the existing match through the normal Application flow.

This guard is active independently of diagnostic capture. If capture is enabled, `layout-storm.json` identifies the triggering scroller with `guard_tripped=true`. The original card/state trigger remains unresolved. A successful guard recovery should be reported so the captured state can be investigated.

Build current protected renderer packages with `artifacts/build-layout-guard-variants.py`. Validation uses `--mock --layout-loop-check` and the regular gameplay smoke, including a real native container sizing oscillator and retry recovery.
