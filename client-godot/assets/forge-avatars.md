`forge-avatars.png` is copied unchanged from the vendored Forge file
`forge/forge-gui/res/skins/default/sprite_avatars.png`.

`forge-avatars.json` preserves the default avatar order used by Forge desktop's
`FSkin.assembleAvatars`: scan 100×100 tiles left to right, top to bottom; skip
the top-left tile and any tile whose center pixel has zero alpha. This sheet
contains 126 selectable avatars. MatchSetup's avatar bound must match that count.

These are Forge's original avatar choices. The profile picker does not use the
previous generated `portraits-atlas.png` asset.
