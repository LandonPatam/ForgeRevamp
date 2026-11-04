extends Button
const Mana = preload("res://scripts/ui/ManaCounter.gd")
var colors: Array[int] = []
var glow := 0.0
var choice_tile := false

static func choice_details(label: String) -> Dictionary:
	var colors := colors_for(label)
	if colors.is_empty(): return {}
	for name in Mana.NAMES:
		if label.to_lower() == name.to_lower(): return {"colors": colors, "cost": "", "extra": ""}
	var details := preload("res://scripts/ui/AbilityOption.gd").parts(label)
	var effect: String = details.effect
	effect = effect.replace("Add {C} (one colorless mana).", "Add {C}.")
	var pattern := RegEx.new()
	pattern.compile("(?s)^Add\\s+(\\{[WUBRGC]\\})\\.(.*)$")
	var matched := pattern.search(effect)
	if matched == null: return {}
	var extra := matched.get_string(2).strip_edges()
	if extra == "(one colorless mana).": extra = ""
	var cost: String = details.cost
	if cost == "{T}": cost = ""
	return {"colors": colors, "cost": cost, "extra": extra}

static func colors_for(label: String) -> Array[int]:
	var result: Array[int] = []
	for i in range(Mana.KEYS.size()):
		if label.to_lower() == Mana.NAMES[i].to_lower() or label.begins_with(Mana.NAMES[i] + " —"):
			return [i]
	var add := label.find("Add ")
	if add >= 0:
		var production := label.substr(add).split(".")[0]
		for i in range(Mana.KEYS.size()):
			if production.contains("{" + Mana.KEYS[i] + "}"):
				result.append(i)
	return result

func _ready() -> void:
	if choice_tile:
		text = ""
		custom_minimum_size = Vector2(112, 112)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := get_theme_stylebox(kind).duplicate() as StyleBoxFlat
			style.set_corner_radius_all(30)
			add_theme_stylebox_override(kind, style)
		return
	custom_minimum_size.y = 64
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_constant_override("outline_size", 0)
	for kind in ["normal", "hover", "pressed", "disabled"]:
		var base := get_theme_stylebox(kind).duplicate() as StyleBox
		base.content_margin_left = 16 + colors.size() * 48
		add_theme_stylebox_override(kind, base)

func _process(delta: float) -> void:
	glow = move_toward(glow, 1.0 if is_hovered() and not disabled else 0.0, delta * 5)
	queue_redraw()

func _draw() -> void:
	for n in range(colors.size()):
		var i := colors[n]
		var center := Vector2((size.x - (colors.size() - 1) * 48) * 0.5 + n * 48 if choice_tile else 30 + n * 48, size.y * 0.5)
		for ring in range(10, 0, -1):
			draw_circle(center, 20 + ring, Color(Mana.FILLS[i], glow * 0.025))
		draw_circle(center, 19, Mana.FILLS[i])
		var glyph := String.chr(Mana.GLYPHS[i])
		var font: Font = Mana.ICON_FONT
		var offset := Vector2(-font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x * 0.5, (font.get_ascent(27) - font.get_descent(27)) * 0.5)
		draw_string(font, center + offset, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 27, Color("17191a"))
