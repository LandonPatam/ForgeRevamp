extends Control
# Wrapped rules text with native-resolution inline mana and tap symbols.
const Mana = preload("res://scripts/ui/ManaCounter.gd")
var text := ""
var font_size := 18
var ink := Color.WHITE
var glow := 0.0
var runs: Array[Dictionary] = []

static func symbol(token: String) -> Dictionary:
	var key := token.to_upper()
	var index := Mana.KEYS.find(key)
	if index >= 0: return {"glyph": Mana.GLYPHS[index], "fill": Mana.FILLS[index]}
	if key == "T": return {"glyph": 0xe61a, "fill": Color("d0c6bb")}
	if key == "Q": return {"glyph": 0xe61b, "fill": Color("d0c6bb")}
	if key in ["X", "Y", "Z"]: return {"glyph": 0xe615 + ["X", "Y", "Z"].find(key), "fill": Color("d0c6bb")}
	if key.is_valid_int() and int(key) >= 0 and int(key) <= 16:
		return {"glyph": 0xe605 + int(key) if int(key) < 16 else 0xe62a, "fill": Color("d0c6bb")}
	return {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var font := get_theme_default_font()
	var pattern := RegEx.new()
	pattern.compile("\\{([^}]+)\\}|[^\\s{}]+|\\s+|[{}]")
	var x := 0.0
	var y := 0.0
	var height := float(font_size + 14)
	var available := maxf(size.x, 100)
	runs.clear()
	for match_text in pattern.search_all(text):
		var word := match_text.get_string()
		var icon := symbol(match_text.get_string(1)) if word.begins_with("{") else {}
		var width := float(font_size + 12) if not icon.is_empty() else font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if word.contains("\n") or (x + width > available and x > 0):
			x = 0
			y += height
		if word.strip_edges().is_empty() and x == 0: continue
		runs.append({"word": word, "icon": icon, "position": Vector2(x, y), "width": width})
		x += width
	custom_minimum_size.y = y + height
	queue_redraw()

func _draw() -> void:
	var font := get_theme_default_font()
	for run in runs:
		var origin: Vector2 = run.position
		if run.icon.is_empty():
			draw_string(font, origin + Vector2(0, font_size + 3), run.word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
		else:
			var radius := (font_size + 6) * 0.5
			var center := origin + Vector2(run.width * 0.5, (font_size + 14) * 0.5)
			for ring in range(6, 0, -1): draw_circle(center, radius + ring, Color(run.icon.fill, glow * 0.04))
			draw_circle(center, radius, run.icon.fill)
			var glyph := String.chr(run.icon.glyph)
			var icon_font: Font = Mana.ICON_FONT
			var offset := Vector2(-icon_font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5, (icon_font.get_ascent(font_size) - icon_font.get_descent(font_size)) * 0.5)
			draw_string(icon_font, center + offset, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("17191a"))
