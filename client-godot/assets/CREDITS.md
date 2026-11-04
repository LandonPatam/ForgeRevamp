# Battlefield background

## Mana icons

`fonts/mana/mana.ttf` is the unmodified Mana v1.18.0 icon font by Andrew Gioia, downloaded from [the author's repository](https://github.com/andrewgioia/mana), used for W/U/B/R/G/C in the local mana pool. Glyph mappings and circle colors follow [Mana's icon documentation](https://mana.andrewgioia.com/icons.html) and stylesheet. The font is licensed under SIL Open Font License 1.1; `fonts/mana/OFL.txt` includes the license, and `README.upstream.md` preserves the author's attribution/license statement. Magic mana symbols belong to Wizards of the Coast. The font is bundled locally with no runtime network dependency.

## Library sleeve

`forge-sleeves.png` is an unedited copy of Forge's bundled `forge/forge-gui/res/skins/default/sprite_sleeves.png`. `black-lotus-back.tres` selects its dark Black Lotus flower sleeve (column 2, row 4, 360x500 pixels) at runtime for the library and dragged face-down cards. Existing artwork belongs to its respective artists and Wizards of the Coast/licensors; no artwork was generated or repainted.

## Complete card faces

`cards/` contains complete card images for the user's Atraxa, AtraxaV2, and Doom Commander decks. Artwork, frames, text, logos and related properties belong to Wizards of the Coast and their respective artists/licensors, including Marvel and other crossover properties. These are existing card images, not generated artwork.

210 images were copied without edits from the user's local Forge image cache. 22 additional faces were downloaded through [Scryfall's API](https://scryfall.com/docs/api). `cards/downloads.json` records each downloaded image URL, printing page and artist; `cards/manifest.json` records Forge image keys and deck coverage. Cached images prefer the matching set/art index. When that printing is unavailable, another printing of the same card is used. Flavor-name printings also resolve through their rules names. Runtime rounded clipping removes opaque pixels beyond the physical card outline; selection cues and current creature stats are overlays.

Refresh with `node client-godot/tools/import-card-images.mjs`; add `--download-missing` to fetch uncached names. The importer reads Forge's cache/decks and writes only this project's assets. Images load locally during play, with no runtime network dependency.

`capenna-court.jpg` is the exact background selected and linked by the user, downloaded without image edits from:

https://cdna.artstation.com/p/assets/images/images/053/862/412/large/erin-loelius-snc-bf-concept.jpg?1663188105

Artist portfolio: [Erin Loelius - Magic: The Gathering Arena, Streets of New Capenna Battlefield](https://erin.artstation.com/projects/r9Nq6m?album_id=7116614).

The portfolio credits concept work to Erin Loelius, painting to Paul Chou and Erin Loelius, project lead / 3D work to Adam Chandler, and animation to Chip Carle. The artwork and related properties are copyright Wizards of the Coast. The supplied image retains its original Wizards mark. Runtime aspect fitting and a dark header fade keep UI text readable.

The generated `ruined-court.png` and `portraits-atlas.png` are earlier visual experiments, no longer referenced by the running client. Their generation history remains in [GENERATION.md](GENERATION.md). Current player badges are drawn in Godot and contain initials and HP, with no generated character portraits.
