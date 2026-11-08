# Asset credits

## Mana icons

`fonts/mana/mana.ttf` is the unmodified Mana v1.18.0 icon font by Andrew Gioia, downloaded from [the author's repository](https://github.com/andrewgioia/mana), used for W/U/B/R/G/C in the local mana pool. Glyph mappings and circle colors follow [Mana's icon documentation](https://mana.andrewgioia.com/icons.html) and stylesheet. The font is licensed under SIL Open Font License 1.1; `fonts/mana/OFL.txt` includes the license, and `README.upstream.md` preserves the author's attribution/license statement. Magic mana symbols belong to Wizards of the Coast. The font is bundled locally with no runtime network dependency.

## Library sleeve

`forge-sleeves.png` is an unedited copy of Forge's bundled `forge/forge-gui/res/skins/default/sprite_sleeves.png`. `black-lotus-back.tres` selects its dark Black Lotus flower sleeve (column 2, row 4, 360x500 pixels) at runtime for the library and dragged face-down cards. Existing artwork belongs to its respective artists and Wizards of the Coast/licensors; no artwork was generated or repainted.

## Complete card faces (test fixtures)

`cards/` contains complete card images for the user's Atraxa, AtraxaV2, and Doom Commander decks, used by the mock UI checks. They are excluded from exported builds (`export_presets.cfg`); the game downloads and caches artwork at runtime. Artwork, frames, text, logos and related properties belong to Wizards of the Coast and their respective artists/licensors, including Marvel and other crossover properties. These are existing card images, not generated artwork.

210 images were copied without edits from the user's local Forge image cache. 22 additional faces were downloaded through [Scryfall's API](https://scryfall.com/docs/api). `cards/downloads.json` records each downloaded image URL, printing page and artist; `cards/manifest.json` records Forge image keys and deck coverage.
