extends Button
## A small cartridge slot for a public card zone. Native Button input/focus
## keeps browsing and keyboard activation identical to the other board actions.
const Icon = preload("res://scripts/ui/ZoneIcon.gd")
var kind := "Command"
var glyph: Control
## Something in this zone can be cast right now (your commander, flashback, escape): purple rim.
var playable := false:
	set(value):
		if playable == value: return
		playable = value
		_restyle()
## Your tapped mana already pays for one of them: teal rim instead of purple.
var castable_now := false:
	set(value):
		if castable_now == value: return
		castable_now = value
		_restyle()

func _ready() -> void:
	custom_minimum_size = Vector2(52, 66)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono"])
	add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_color", Color("b6ded1"))
	add_theme_color_override("font_hover_color", Color("e2fff0"))
	_restyle()
	glyph = Icon.new()
	glyph.kind = kind
	glyph.position = Vector2(13, 5)
	glyph.size = Vector2(26, 26)
	add_child(glyph)
	tooltip_text = kind + " / click to browse"
	accessibility_name = "Browse " + kind

func _restyle() -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("243d3c") if state == "hover" else Color("102322")
		box.border_color = (Color("3fe6d4") if castable_now else Color("b48cff")) if playable else (Color("8edbc3") if state in ["hover", "focus"] else Color("476d65"))
		box.set_border_width_all(3 if playable else 1)
		box.set_corner_radius_all(12)
		box.content_margin_top = 33
		box.content_margin_bottom = 3
		if playable:
			box.shadow_color = Color(0.25, 0.9, 0.83, 0.45) if castable_now else Color(0.71, 0.55, 1.0, 0.45)
			box.shadow_size = 6
		add_theme_stylebox_override(state, box)
	tooltip_text = kind + (" / something here can be cast now" if playable else "") + " / click to browse"
