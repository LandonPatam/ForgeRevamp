extends Button
## A small cartridge slot for a public card zone. Native Button input/focus
## keeps browsing and keyboard activation identical to the other board actions.
const Icon = preload("res://scripts/ui/ZoneIcon.gd")
var kind := "Command"
var glyph: Control

func _ready() -> void:
	custom_minimum_size = Vector2(52, 66)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono"])
	add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_color", Color("b6ded1"))
	add_theme_color_override("font_hover_color", Color("e2fff0"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("243d3c") if state == "hover" else Color("102322")
		box.border_color = Color("8edbc3") if state in ["hover", "focus"] else Color("476d65")
		box.set_border_width_all(1)
		box.set_corner_radius_all(12)
		box.content_margin_top = 33
		box.content_margin_bottom = 3
		add_theme_stylebox_override(state, box)
	glyph = Icon.new()
	glyph.kind = kind
	glyph.position = Vector2(13, 5)
	glyph.size = Vector2(26, 26)
	add_child(glyph)
	tooltip_text = kind + " / click to browse"
	accessibility_name = "Browse " + kind
