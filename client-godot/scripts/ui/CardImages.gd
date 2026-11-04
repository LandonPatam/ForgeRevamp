extends RefCounted
## Shared complete card faces. Hidden/face-down descriptors never resolve images.
static var manifest: Dictionary = {}
static var initialized := false
static var textures: Dictionary = {}
static var downloaded: Dictionary = {}
static var name_textures: Dictionary = {}
static var mtg_back: Texture2D

## The standard Magic card back (first tile of Forge's sleeve atlas), shown on
## face-down permanents. It reveals nothing about the hidden card.
static func card_back() -> Texture2D:
	if mtg_back == null:
		var atlas: Texture2D = preload("res://assets/forge-sleeves.png")
		var image := atlas.get_image().get_region(Rect2i(0, 0, 360, 500))
		image.generate_mipmaps()
		mtg_back = ImageTexture.create_from_image(image)
	return mtg_back

static func register_texture(image_key: String, texture: Texture2D) -> void:
	if image_key.is_empty() or texture == null: return
	downloaded[image_key] = texture
	var identity := _face_identity(image_key)
	if not identity.is_empty(): name_textures[identity] = texture

static func _face_identity(key: String) -> String:
	if not key.begins_with("c:"): return ""
	return key.trim_prefix("c:").get_slice("|", 0) + ("$" + key.get_slice("$", 1) if key.contains("$") else "")

static func exact_texture_ready(card: Dictionary) -> bool:
	var key: String = card.get("imageKey", "")
	return downloaded.has(key) or not str(manifest.get("byKey", {}).get(key, "")).is_empty()

static func texture_for(card: Dictionary) -> Texture2D:
	if card.get("hidden", false) or card.get("faceDown", false):
		return null
	if downloaded.has(card.get("imageKey", "")): return downloaded[card.imageKey]
	if not initialized:
		initialized = true
		var path := "res://assets/cards/manifest.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				manifest = parsed
	var path: String = manifest.get("byKey", {}).get(card.get("imageKey", ""), "")
	if path.is_empty():
		var fallback: Texture2D = name_textures.get(_face_identity(str(card.get("imageKey", ""))))
		if fallback != null: return fallback
		# A front face is never a fallback for a transformed/specialized back.
		if str(card.get("imageKey", "")).contains("$"): return null
	# A token's name is not an ordinary card-printing identity.
	if path.is_empty() and str(card.get("imageKey", "")).begins_with("t:"): return null
	if path.is_empty():
		path = manifest.get("byName", {}).get(card.get("name", ""), "")
	if path.is_empty():
		# Reskins can expose a flavor name while imageKey retains the rules name.
		var key: String = card.get("imageKey", "")
		if key.begins_with("c:") and not key.contains("$"):
			path = manifest.get("byName", {}).get(key.trim_prefix("c:").get_slice("|", 0), "")
	if path.is_empty():
		return null
	if not textures.has(path):
		textures[path] = load(path) if ResourceLoader.exists(path) else null
	return textures[path]
