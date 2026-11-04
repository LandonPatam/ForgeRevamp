extends RefCounted
const Images = preload("res://scripts/ui/CardImages.gd")

func run(ui: Control) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cards/manifest.json"))
	var count := 0
	for deck in manifest.decks:
		for entry in manifest.decks[deck]:
			var texture: Texture2D = Images.texture_for({"name": entry.name})
			assert(texture != null and texture.get_width() >= 400 and texture.get_height() >= 550, "Missing complete face: " + entry.name)
			count += 1
	var atraxa := {"name": "Atraxa, Praetors' Voice", "imageKey": "c:Atraxa, Praetors' Voice|PF26|1"}
	assert(Images.texture_for(atraxa) == load(manifest.byKey[atraxa.imageKey]), "The exact Forge printing key must take precedence")
	assert(Images.texture_for({"name": "Erebor Heirloom", "imageKey": "c:Fellwar Stone|SLD|3"}) != null, "Flavor-name printings must resolve their complete face")
	assert(Images.texture_for({"name": "Unrecognized flavor name", "imageKey": "c:Fellwar Stone|SLD|999"}) == Images.texture_for({"name": "Fellwar Stone"}), "An uncached printing must fall back through the canonical image-key name")
	assert(Images.texture_for({"name": atraxa.name, "hidden": true}) == null)
	assert(Images.texture_for({"name": atraxa.name, "faceDown": true}) == null)
	assert(Images.texture_for({"name": "Uncached prototype card"}) == null)
	var card = preload("res://scripts/ui/CardView.gd").new()
	ui.add_child(card)
	card.update_card(atraxa)
	assert(card.face.full_image != null and not card.face.art.visible, "Complete faces must replace the placeholder art and text")
	card.update_card({"name": atraxa.name, "hidden": true})
	assert(card.face.full_image == null and not card.face.art.visible, "Reusing a node for a hidden card must discard the face")
	card.queue_free()
	var token_key := "t:godot_async_token_art|TEST|1"
	var token := {"id": 901, "name": "Runtime token", "token": true, "imageKey": token_key, "tokenImageUrls": []}
	var loader = preload("res://scripts/ui/RuntimeArtwork.gd").new()
	loader.network_enabled = false
	ui.add_child(loader)
	loader.request_card(token)
	loader.request_card(token)
	assert(loader.attempted.size() == 1, "Identical token faces must share one image request")
	loader.request_card({"token": true, "imageKey": "t:hidden_token", "hidden": true})
	assert(loader.attempted.size() == 1, "Private token faces must not be requested")
	var token_view = preload("res://scripts/ui/CardView.gd").new()
	ui.add_child(token_view)
	token_view.update_card(token)
	assert(token_view.face.full_image == null)
	var pixels := Image.create(16, 22, false, Image.FORMAT_RGBA8)
	pixels.fill(Color("448899"))
	assert(loader._accept(token_key, pixels.save_png_to_buffer()))
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	assert(token_view.face.full_image != null and not token_view.face.art.visible, "An existing token face must repaint when artwork arrives without a new engine snapshot")
	token_view.inspection = true
	token_view.size = Vector2(214, 600)
	token_view._arrange()
	assert(is_equal_approx(token_view.visual.size.x / token_view.visual.size.y, 160.0 / 218), "Inspection artwork must preserve its proportions in a tall container")
	token_view.queue_free()
	loader.queue_free()
	Images.downloaded.erase(token_key)
	var first_key := "c:Background face check|FIRST|1"
	var exact_key := "c:Background face check|EXACT|1"
	var cached_face := ImageTexture.create_from_image(pixels)
	Images.register_texture(first_key, cached_face)
	var warming = preload("res://scripts/ui/CardView.gd").new()
	ui.add_child(warming)
	warming.update_card({"id": 902, "name": "Background face check", "imageKey": exact_key})
	assert(warming.face.full_image == cached_face, "A cached printing of the same card must appear immediately while the exact printing warms")
	assert(Images.texture_for({"name": "Background face check", "imageKey": exact_key + "$alt"}) == null, "A cached front must never substitute for a missing back face")
	assert(Images.texture_for({"name": "Background face check", "imageKey": exact_key, "hidden": true}) == null)
	pixels.fill(Color("998844"))
	var exact_face := ImageTexture.create_from_image(pixels)
	Images.register_texture(exact_key, exact_face)
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	assert(warming.face.full_image == exact_face and not warming.face.is_processing(), "The correct printing must replace the temporary face without another engine snapshot or ongoing repainting")
	warming.queue_free()
	Images.downloaded.erase(first_key)
	Images.downloaded.erase(exact_key)
	Images.name_textures.erase("Background face check")
	await ui.get_tree().process_frame
	print("PASS: complete card images for %s deck entries, printing lookup, placeholder fallback and hidden-card guards" % count)
