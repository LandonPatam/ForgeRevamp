extends Control
## Cached high-resolution face; CardView projects this texture onto an angled quad.
const P = preload("res://scripts/ui/Palette.gd")
const Art = preload("res://scripts/ui/CardArt.gd")
const Images = preload("res://scripts/ui/CardImages.gd")
## Combat traits in badge order: label and role (damage, evasion or defense).
const TRAITS := {
	"FLYING": ["Flying", "evasion"], "DEATHTOUCH": ["Deathtouch", "damage"], "TRAMPLE": ["Trample", "damage"],
	"FIRST_STRIKE": ["First strike", "damage"], "DOUBLE_STRIKE": ["Double strike", "damage"], "LIFELINK": ["Lifelink", "damage"],
	"INFECT": ["Infect", "damage"], "WITHER": ["Wither", "damage"], "MENACE": ["Menace", "evasion"], "HASTE": ["Haste", "evasion"],
	"SKULK": ["Skulk", "evasion"], "SHADOW": ["Shadow", "evasion"], "FEAR": ["Fear", "evasion"], "INTIMIDATE": ["Intimidate", "evasion"],
	"HORSEMANSHIP": ["Horsemanship", "evasion"], "REACH": ["Reach", "defense"], "VIGILANCE": ["Vigilance", "defense"],
	"INDESTRUCTIBLE": ["Indestructible", "defense"], "HEXPROOF": ["Hexproof", "defense"], "SHROUD": ["Shroud", "defense"],
	"WARD": ["Ward", "defense"], "PROTECTION": ["Protection", "defense"], "DEFENDER": ["Defender", "defense"],
}
const TRAIT_ICONS := {
	"FLYING": "Fl", "DEATHTOUCH": "Dt", "TRAMPLE": "Tr", "FIRST_STRIKE": "FS", "DOUBLE_STRIKE": "DS", "LIFELINK": "Ll",
	"INFECT": "In", "WITHER": "Wi", "MENACE": "Me", "HASTE": "Ha", "SKULK": "Sk", "SHADOW": "Sh", "FEAR": "Fe",
	"INTIMIDATE": "Im", "HORSEMANSHIP": "Ho", "REACH": "Re", "VIGILANCE": "Vi", "INDESTRUCTIBLE": "Ind",
	"HEXPROOF": "Hx", "SHROUD": "Sd", "WARD": "Wd", "PROTECTION": "Pr", "DEFENDER": "De",
}
const TRAIT_COLORS := {"damage": Color("ffb27a"), "evasion": Color("c7adff"), "defense": Color("8fd3ff")}
var full_image: Texture2D
var data: Dictionary = {}
var selected := false
var art: Control
## Status badges draw above the placeholder art child, so they show while artwork loads.
var overlay: Control
var badge_scale := 1.0
## Table cards hang power/toughness off the card instead, clear of the trait row.
var stats_on_face := true

static func counter_label(code: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("^([PM])(\\d+)([PM])(\\d+)$")
	var found := pattern.search(code)
	if found != null:
		return ("+" if found.get_string(1) == "P" else "-") + found.get_string(2) + "/" + ("+" if found.get_string(3) == "P" else "-") + found.get_string(4)
	return code.replace("_", " ").capitalize()

func _ready() -> void:
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	art = Art.new()
	add_child(art)
	art.position = Vector2(5, 32) * 4
	art.size = Vector2(134, 123) * 4
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.size = Vector2(144, 202) * 4
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)

func refresh(value: Dictionary, is_selected: bool) -> bool:
	# Rules metadata (including tapping) changes more often than the printed face.
	var painted: Dictionary = {}
	for key in ["name", "imageKey", "hidden", "faceDown", "color", "art", "weakSelection", "power", "toughness", "stats", "typeLine", "manaCost", "commander", "commanderTax", "stackCount", "zone", "sick", "damage", "counters", "keywords"]:
		if value.has(key):
			painted[key] = value[key]
	if data == painted and selected == is_selected:
		return false
	data = painted
	selected = is_selected
	full_image = Images.card_back() if data.get("faceDown", false) and not data.get("hidden", false) else Images.texture_for(data)
	set_process(not Images.exact_texture_ready(data) and not data.get("hidden", false) and not data.get("faceDown", false) and not str(data.get("imageKey", "")).is_empty())
	if art != null:
		art.visible = full_image == null and not data.get("hidden", false) and not data.get("faceDown", false)
		art.art_key = data.get("art", "grove")
		art.color_key = data.get("color", "G")
		art.seed_key = data.get("name", "")
		art.queue_redraw()
	queue_redraw()
	if overlay != null:
		overlay.queue_redraw()
	return true

## Returns true when the trait badges need repainting at the new display size.
func set_badge_scale(value: float) -> bool:
	value = snappedf(value, 0.1)
	if is_equal_approx(value, badge_scale):
		return false
	badge_scale = value
	if overlay != null:
		overlay.queue_redraw()
	return false

func _process(_delta: float) -> void:
	var ready: Texture2D = Images.texture_for(data)
	if ready == null: return
	if full_image != ready:
		full_image = ready
		art.hide()
		queue_redraw()
		get_viewport().render_target_update_mode = SubViewport.UPDATE_ONCE
	if Images.exact_texture_ready(data): set_process(false)

func _draw() -> void:
	if data.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0, Vector2(4, 4))
	var accent: Color = P.accent(data.get("color", "G"))
	var border: Color = P.GOLD if selected else (Color("56c4ee") if data.get("weakSelection", 0) > 0 else accent.darkened(0.24))
	# Offset layers are the exposed edge and contact shadow of the card.
	draw_style_box(P.box(Color(0, 0, 0, 0.42), Color.TRANSPARENT, 7, 0), Rect2(2, 6, 144, 202))
	draw_style_box(P.box(Color("070909"), Color("352e24"), 7, 0), Rect2(0, 3, 144, 202))
	draw_style_box(P.box(Color("151b1b"), border, 7, 0), Rect2(0, 0, 144, 202))
	if full_image != null:
		_draw_rounded_image()
		if selected or data.get("weakSelection", 0) > 0:
			draw_style_box(P.box(Color.TRANSPARENT, P.GOLD if selected else Color("56c4ee"), 7, 0), Rect2(-2, -2, 148, 206))
		draw_set_transform(Vector2.ZERO)
		return
	draw_line(Vector2(8, 2), Vector2(136, 2), accent.lightened(0.25), 0.7, true)
	if selected:
		draw_style_box(P.box(Color.TRANSPARENT, Color("bdf7db"), 8, 0), Rect2(-2, -2, 148, 206))
	if data.get("hidden", false) or data.get("faceDown", false):
		draw_style_box(P.box(Color("202a3c"), P.GOLD.darkened(0.3), 6, 0), Rect2(8, 8, 128, 186))
		draw_circle(Vector2(72, 101), 27, P.GOLD.darkened(0.3), false, 2, true)
		draw_set_transform(Vector2.ZERO)
		return
	var font := get_theme_default_font()
	var title: String = data.get("name", "Unknown")
	var font_size := 12
	while font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 130 and font_size > 9:
		font_size -= 1
	draw_string(font, Vector2(7, 21), title, HORIZONTAL_ALIGNMENT_LEFT, 131, font_size, P.TEXT)
	draw_rect(Rect2(5, 159, 134, 38), Color("172421"))
	draw_line(Vector2(5, 159), Vector2(139, 159), accent.darkened(0.3), 1)
	var type_line: String = data.get("typeLine", "")
	if type_line.length() > 23:
		type_line = type_line.substr(0, 22) + "…"
	draw_string(font, Vector2(9, 175), type_line, HORIZONTAL_ALIGNMENT_LEFT, 126, 10, P.MUTED)
	draw_string(font, Vector2(9, 189), data.get("manaCost", ""), HORIZONTAL_ALIGNMENT_LEFT, 80, 12, accent.lightened(0.2))
	var stats: String = data.get("stats", "")
	if not stats.is_empty():
		draw_style_box(P.box(Color("0b171d"), accent.darkened(0.4), 4, 0), Rect2(93, 177, 44, 20))
		draw_string(font, Vector2(99, 191), stats, HORIZONTAL_ALIGNMENT_LEFT, 40, 12, P.TEXT)
	if data.get("commander", false):
		draw_string(font, Vector2(116, 149), "◆", HORIZONTAL_ALIGNMENT_LEFT, 20, 17, P.GOLD)
	draw_set_transform(Vector2.ZERO)

func _draw_overlay() -> void:
	if data.is_empty():
		return
	# Current power/toughness can differ from the printed card after game effects.
	overlay.draw_set_transform(Vector2.ZERO, 0, Vector2(4, 4))
	_draw_stack_count()
	_draw_status()
	overlay.draw_set_transform(Vector2.ZERO)

func _badge(text: String, rect: Rect2, color: Color, border: bool = true, font_size: int = 40, fill: Color = Color("11171e")) -> void:
	# Render glyphs at the viewport's actual resolution, including enlarged previews.
	overlay.draw_set_transform(Vector2.ZERO)
	var bounds := Rect2(rect.position * 4, rect.size * 4)
	overlay.draw_style_box(P.box(fill, color if border else Color.TRANSPARENT, 10, 0), bounds)
	overlay.draw_string(get_theme_default_font(), (rect.position + Vector2(3, rect.size.y - 3)) * 4, text, HORIZONTAL_ALIGNMENT_CENTER, (rect.size.x - 6) * 4, font_size, color)
	overlay.draw_set_transform(Vector2.ZERO, 0, Vector2(4, 4))

## Counter type on white beside its amount on black, drawn at the viewport's real resolution.
func _counter_badge(kind: String, amount: String, at: Vector2, height: float) -> void:
	overlay.draw_set_transform(Vector2.ZERO)
	var font := get_theme_default_font()
	var font_size := 40
	var padding := 16.0
	var amount_width: float = maxf(font.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + padding * 2, height * 4)
	# Long counter names shrink so the badge stays on the card.
	var kind_room: float = 138.0 * 4 - amount_width
	while font.get_string_size(kind, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + padding * 2 > kind_room and font_size > 20:
		font_size -= 2
	var kind_width: float = minf(font.get_string_size(kind, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + padding * 2, kind_room)
	var left := Rect2(at * 4, Vector2(kind_width, height * 4))
	var right := Rect2(left.position + Vector2(kind_width, 0), Vector2(amount_width, height * 4))
	var kind_box := P.box(Color.WHITE, Color.TRANSPARENT, 10, 0)
	kind_box.set_border_width_all(0)
	kind_box.corner_radius_top_right = 0
	kind_box.corner_radius_bottom_right = 0
	overlay.draw_style_box(kind_box, left)
	var amount_box := P.box(Color.BLACK, Color.TRANSPARENT, 10, 0)
	amount_box.set_border_width_all(0)
	amount_box.corner_radius_top_left = 0
	amount_box.corner_radius_bottom_left = 0
	overlay.draw_style_box(amount_box, right)
	var baseline: float = left.get_center().y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	overlay.draw_string(font, Vector2(left.position.x, baseline), kind, HORIZONTAL_ALIGNMENT_CENTER, left.size.x, font_size, Color.BLACK)
	overlay.draw_string(font, Vector2(right.position.x, baseline), amount, HORIZONTAL_ALIGNMENT_CENTER, right.size.x, font_size, Color.WHITE)
	overlay.draw_set_transform(Vector2.ZERO, 0, Vector2(4, 4))

func _draw_status() -> void:
	# A face-down permanent's 2/2, summoning sickness and counters are public.
	if data.get("hidden", false):
		return
	if data.get("zone", "") == "Command" and int(data.get("commanderTax", 0)) > 0:
		_white_badge("Tax +%d" % int(data.commanderTax), Vector2(3, 30), 16.0)
	if data.get("zone", "") != "Battlefield": return
	if data.has("power") and stats_on_face:
		_badge(str(data.get("stats", "")), Rect2(92, 196, 52, 14), Color.WHITE, false)
	var y := 30.0
	if data.get("sick", false) and data.get("typeLine", "").contains("Creature"):
		_badge("Zzz", Rect2(3, y, 30, 15), Color("b3b7ff"))
		y += 18
	for counter in data.get("counters", {}):
		var amount := int(data.counters[counter])
		if amount <= 0: continue
		_counter_badge(counter_label(str(counter)), str(amount), Vector2(3, y), 15.0)
		y += 18
	var damage := int(data.get("damage", 0))
	if damage > 0:
		_badge("%d damage" % damage, Rect2(3, 147, 75, 16), Color("ff9696"))
		if data.has("power"):
			_badge("%d left" % (int(data.get("toughness", 0)) - damage), Rect2(3, 165, 75, 14), Color("ff9696"))

static func trait_keys(keywords: Array) -> Array:
	return TRAITS.keys().filter(func(key): return keywords.has(key))

static func trait_icon(key: String) -> String:
	if TRAIT_ICONS.has(key): return TRAIT_ICONS[key]
	return String(TRAITS[key][0]).substr(0, 2)

static func trait_color(key: String) -> Color:
	return TRAIT_COLORS[TRAITS[key][1]]

func _draw_stack_count() -> void:
	if data.get("zone", "") != "Battlefield" or int(data.get("stackCount", 1)) <= 1 or data.get("hidden", false) or data.get("faceDown", false):
		return
	_white_badge("×" + str(data.stackCount), Vector2(3, 26), 18.0)

## White tile with black text, drawn at the viewport's real resolution (not scaled up).
func _white_badge(text: String, at: Vector2, height: float) -> void:
	var font := get_theme_default_font()
	var font_size := int(height * 4.0 * 0.66)
	var width := maxf(height * 1.5, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 4.0 + 10.0)
	_badge(text, Rect2(at, Vector2(width, height)), Color.BLACK, false, font_size, Color.WHITE)

func _draw_rounded_image() -> void:
	# JPEGs retain white/black pixels beyond the physical card's rounded corners.
	# Clip the image geometrically; do not crop or recolor any of its artwork.
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var centers := [Vector2(137, 7), Vector2(137, 195), Vector2(7, 195), Vector2(7, 7)]
	for corner in range(4):
		for step in range(9):
			var angle := -PI * 0.5 + corner * PI * 0.5 + step * PI / 16.0
			var point: Vector2 = centers[corner] + Vector2(cos(angle), sin(angle)) * 7
			points.append(point)
			uvs.append(point / Vector2(144, 202))
	draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, full_image)
