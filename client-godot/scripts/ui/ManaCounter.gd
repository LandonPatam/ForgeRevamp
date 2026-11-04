extends Button
## Local Mana font glyph over a mana-colored circle, with a separate pool count.
const ICON_FONT = preload("res://assets/fonts/mana/mana.ttf")
const KEYS := ["W", "U", "B", "R", "G", "C"]
const GLYPHS := [0xe600, 0xe601, 0xe602, 0xe603, 0xe604, 0xe904]
const FILLS := [Color("fdfbce"), Color("bcdaf7"), Color("a7999e"), Color("f19b79"), Color("9fcba6"), Color("d0c6bb")]
const NAMES := ["White", "Blue", "Black", "Red", "Green", "Colorless"]
var index := 0
var amount := 0
var count_font_size := 26

func _ready() -> void:
	custom_minimum_size = Vector2(72, 36)
	alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clip_text = true
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_font_size_override("font_size", 26)
	for kind in ["normal", "disabled", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.04, 0.05, 0.065, 0.85) if kind in ["hover", "pressed"] else Color.TRANSPARENT
		style.set_corner_radius_all(18)
		style.content_margin_left = 40
		style.content_margin_right = 6
		add_theme_stylebox_override(kind, style)
	add_theme_color_override("font_color", Color("f0f1ed"))
	add_theme_color_override("font_disabled_color", Color("91a0a8"))
	add_theme_color_override("font_hover_color", Color.WHITE)
	resized.connect(_fit_count)
	set_amount(amount, false)

func set_amount(value: int, can_pay: bool) -> void:
	amount = value
	disabled = not can_pay or value <= 0
	tooltip_text = "%s mana: %d unspent. Click to pay when Forge requests mana." % [NAMES[index], value]
	accessibility_name = tooltip_text
	_fit_count()
	queue_redraw()

func _fit_count() -> void:
	# Keep larger normal counts, while fitting multi-digit pools beside the icon.
	var font := get_theme_font("font")
	var measured := font.get_string_size(str(amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	count_font_size = clampi(int(26 * minf(1, 26.0 / maxf(1, measured))), 4, 26)
	queue_redraw()

func _draw() -> void:
	# Center a fixed icon/count pair so narrower-height layouts do not leave
	# a widening blank gap between the symbol and its count.
	var left := (size.x - 70) * 0.5
	var center := Vector2(left + 18, size.y * 0.5)
	draw_circle(center + Vector2(0, 1), 18, Color(0, 0, 0, 0.65))
	draw_circle(center, 18, FILLS[index])
	draw_arc(center, 18, 0, TAU, 48, FILLS[index].lightened(0.3), 1, true)
	var glyph := String.chr(GLYPHS[index])
	var glyph_size := ICON_FONT.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
	var baseline := center + Vector2(-glyph_size.x * 0.5, (ICON_FONT.get_ascent(28) - ICON_FONT.get_descent(28)) * 0.5)
	draw_string(ICON_FONT, baseline, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("17191a"))
	var font := get_theme_font("font")
	var count_baseline := Vector2(left + 44, center.y + (font.get_ascent(count_font_size) - font.get_descent(count_font_size)) * 0.5)
	var ink := get_theme_color("font_disabled_color" if disabled else "font_hover_color" if is_hovered() else "font_color")
	draw_string(font, count_baseline, str(amount), HORIZONTAL_ALIGNMENT_CENTER, 26, count_font_size, ink)
