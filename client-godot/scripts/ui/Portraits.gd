extends RefCounted
const ATLAS = preload("res://assets/forge-avatars.png")
static var cached: Dictionary = {}
static var regions: Array = []

static func count() -> int:
	if regions.is_empty(): regions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/forge-avatars.json")).regions
	return regions.size()

static func texture(profile: Dictionary) -> Texture2D:
	var custom: String = profile.get("portrait", "")
	if not custom.is_empty():
		var key := custom.sha256_text()
		if not cached.has(key):
			var bytes := Marshalls.base64_to_raw(custom)
			var pixels := Image.new()
			if bytes.size() >= 8:
				var error := pixels.load_png_from_buffer(bytes) if bytes[0] == 137 else pixels.load_jpg_from_buffer(bytes)
				if error == OK: cached[key] = ImageTexture.create_from_image(pixels)
		return cached.get(key)
	if not profile.has("avatar"): return null
	var index := clampi(int(profile.avatar), 0, count() - 1)
	if not cached.has(index):
		var texture := AtlasTexture.new()
		texture.atlas = ATLAS
		texture.region = Rect2(regions[index][0], regions[index][1], 100, 100)
		texture.filter_clip = true
		cached[index] = texture
	return cached[index]
