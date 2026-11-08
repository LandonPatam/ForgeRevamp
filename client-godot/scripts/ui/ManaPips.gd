extends RefCounted
## Mana-cost pips for hand cards: one colored Mana-font pip per colored symbol and a single gray
## numbered circle for generic mana ("{4}{B}" → [4] (B)). Hybrid symbols split their circle.
const ManaCounter = preload("res://scripts/ui/ManaCounter.gd")
const GENERIC_FILL := Color("bdb6ad")
const INK := Color("17191a")

## Forge's ManaCost text ("{X}{2}{W/U}{B/P}", "no cost") as a list of symbol codes.
static func parse(cost: String) -> PackedStringArray:
	var symbols := PackedStringArray()
	if cost.is_empty() or cost == "no cost": return symbols
	var regex := RegEx.create_from_string("\\{([^}]+)\\}")
	for found in regex.search_all(cost):
		var code := found.get_string(1).to_upper()
		if code == "0": continue
		symbols.append(code)
	return symbols

static func _fill(code: String) -> Color:
	var index := ManaCounter.KEYS.find(code)
	return ManaCounter.FILLS[index] if index >= 0 else GENERIC_FILL

static func _glyph(code: String) -> String:
	var index := ManaCounter.KEYS.find(code)
	return String.chr(ManaCounter.GLYPHS[index]) if index >= 0 else ""

## Draws the pips in a row starting at `origin` (top-left), shrinking to fit `max_width`.
static func draw(canvas: CanvasItem, cost: String, origin: Vector2, radius: float, max_width: float) -> void:
	var symbols := parse(cost)
	if symbols.is_empty(): return
	var gap := radius * 0.25
	var needed := symbols.size() * radius * 2.0 + (symbols.size() - 1) * gap
	if needed > max_width:
		radius *= max_width / needed
		gap *= max_width / needed
	var font: Font = canvas.get_theme_default_font()
	for i in range(symbols.size()):
		var center := origin + Vector2(radius + i * (radius * 2.0 + gap), radius)
		_draw_pip(canvas, symbols[i], center, radius, font)

static func _draw_pip(canvas: CanvasItem, code: String, center: Vector2, radius: float, font: Font) -> void:
	canvas.draw_circle(center + Vector2(0, radius * 0.1), radius * 1.06, Color(0, 0, 0, 0.6))
	var parts := code.split("/")
	if parts.size() == 2 and parts[1] != "P":
		# Hybrid: left half first color (or the generic 2), right half second color.
		canvas.draw_circle(center, radius, _fill(parts[1]))
		var left := PackedVector2Array([center])
		for step in range(17):
			var angle := PI * 0.5 + PI * step / 16.0
			left.append(center + Vector2(cos(angle), sin(angle)) * radius)
		canvas.draw_colored_polygon(left, _fill(parts[0]))
		canvas.draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), Color(0, 0, 0, 0.35), maxf(1.0, radius * 0.08), true)
		_center_text(canvas, ManaCounter.ICON_FONT if not parts[0].is_valid_int() else font, _glyph(parts[0]) if not parts[0].is_valid_int() else parts[0], center + Vector2(-radius * 0.45, 0), radius * 0.95)
		_center_text(canvas, ManaCounter.ICON_FONT, _glyph(parts[1]), center + Vector2(radius * 0.45, 0), radius * 0.95)
		return
	var color_code: String = parts[0]
	canvas.draw_circle(center, radius, _fill(color_code))
	var glyph := _glyph(color_code)
	if not glyph.is_empty():
		_center_text(canvas, ManaCounter.ICON_FONT, glyph, center, radius * 1.3)
	else:
		# Generic number, X, snow and anything without a Mana-font glyph.
		_center_text(canvas, font, color_code, center, radius * (1.25 if color_code.length() == 1 else 1.0))
	if parts.size() == 2: # Phyrexian: a small P mark under the color.
		_center_text(canvas, font, "P", center + Vector2(radius * 0.62, radius * 0.62), radius * 0.6)

static func _center_text(canvas: CanvasItem, font: Font, text: String, center: Vector2, size_px: float) -> void:
	if text.is_empty(): return
	var font_size := maxi(6, int(size_px))
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center + Vector2(-width * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, INK)
