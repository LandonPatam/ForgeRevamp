# Shared Windows and Mac development

Repository: https://github.com/LandonPatam/ForgeRevamp

Windows and Mac share source history, with platform launchers, build scripts and export presets together in this repository. Chats supply working context; commits record implementations. Historical handoffs do not override current source or AGENTS.md.

## Initial Mac consolidation

The first `main` baseline comes from Windows. It includes the client, bridge, tests, required assets and Forge patches, but is not yet a consolidated or Mac-validated release.

1. Preserve and back up the existing Mac project, including untracked source and local Forge edits. Do not reset, clean or overwrite it.
2. Clone into a NEW sibling directory, leaving the old project intact:

   ```sh
   git clone https://github.com/LandonPatam/ForgeRevamp.git ForgeRevamp-shared
   cd ForgeRevamp-shared
   git switch -c chore/mac-reconciliation
   ```

3. Compare the old Mac source against this clone. Read both sets of project instructions. Identify Mac-only launchers, packaging, export presets, runtime discovery and any newer gameplay/network fixes. Earlier handoffs are comparison clues; do not recreate features already implemented here.
4. Import unique changes in focused commits, resolving differences against the shared implementation. Keep Windows scripts working and retain shared fixes from both copies. Add Mac export presets alongside Windows presets. Do not copy the old tree wholesale or copy `.git`, `.godot`, builds, credentials, decks, caches or saved sessions. Preserve Godot `.uid` and resource `.import` descriptors with their resources.
5. Compare the old Mac Forge revision/modifications against `FORGE_COMMIT` and `forge-patches/`. Record unique upstream edits as tracked patches before changing the old checkout. Fresh dependency checkouts must use the pinned revision and documented patches, not unrecorded local edits.
6. Run affected Mac checks and a Mac export/launch check. Commit compatibility changes and push:

   ```sh
   git push -u origin chore/mac-reconciliation
   git rev-parse --short HEAD
   git status --short
   ```

7. Windows fetches the branch, reviews changes and runs affected Windows checks. Merge into `main` after both platforms pass. Both machines then update their clean main checkout with `git pull --ff-only`.

Keep the old Mac project until its unique changes are accounted for. The existing Windows checkout already contains the baseline and does not need replacing.

## Normal feature cycle

Start from a clean, updated main and create a short-lived branch:

```sh
git switch main
git pull --ff-only
git switch -c feature/pile-tap-offset
```

Implement and test on Windows, review the diff, stage the intended files, commit and push:

```sh
git add <specific-files>
git commit -m "Expose cards behind tapped pile members"
git push -u origin feature/pile-tap-offset
```

On Mac, preserve or commit existing work first. Fetch and check out that same branch: use `git switch --track origin/feature/pile-tap-offset` on first checkout, or switch to the existing local branch and `git pull --ff-only`. Test the implementation that was pulled. Commit and push required compatibility fixes on that branch; Windows pulls and rechecks affected behavior.

Coordinate one writer at a time on a shared feature branch. Concurrent independent tasks use separate branches. Never force-push a shared branch to resolve divergence; preserve and reconcile both histories.

After both platforms pass, merge into `main` through a pull request or a reviewed local merge, then update both machines. Independent platform fixes can use branches such as `fix/mac-export`, also merged into the shared main. Avoid permanent platform branches.

## Agent start and handoff

Read AGENTS.md and NOTES.md, inspect Git status and establish branch/commit at task start. Fetch before comparing against remote work. Do not automatically switch branches with uncommitted changes.

Handoffs report actual code and verification:

```text
Branch: feature/pile-tap-offset
Commit: <actual commit ID>
Implemented: tapped pile members shift down to expose the card behind.
Windows checks: <commands and results>
Mac verification: test ordinary and dragged piles, tap and untap.
Remaining issues: <specific issues or none>
```

Record the tested commit per platform. If source changes afterward, rerun affected checks. A Windows pass does not establish a Mac pass. Record the source commit, Forge revision and platform alongside each release artifact. Packaged builds are distributed separately from source synchronization.

## Tracked and local files

Track source, scenes, shaders, required assets, `.uid` files, resource `.import` descriptors, tests, build scripts, export presets, docs, `FORGE_COMMIT` and upstream patches. `.gitattributes` keeps source line endings consistent.

Leave `.godot/`, `.tools/`, the `forge/` dependency checkout, Maven targets, `dist/`, captures, backups, handoff archives and credentials local. User decks, artwork caches and saved sessions remain in their normal user-data locations. Do not synchronize them by overwriting projects.
