extends Button
## Small mechanical rocker. It snaps to its new position on click; only its
## colors follow the room's lighting transition.
var darkness := 0.0:
	set(value):
		darkness = value
		queue_redraw()
var dark := false:
	set(value):
		dark = value
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = Vector2(104, 34)
	# Flip on mouse-down, like a physical switch, instead of waiting for release.
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	tooltip_text = "Switch room lighting"
	accessibility_name = "Toggle dark mode"
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (size.y / 34.0))
	var ink := Color("455f6a").lerp(Color("b8cecb"), darkness)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color("ccd3d5").lerp(Color("41494b"), darkness)
	plate.border_color = ink.darkened(0.25)
	plate.set_border_width_all(1)
	plate.set_corner_radius_all(4)
	draw_style_box(plate, Rect2(65, 0, 31, 34))
	draw_style_box(_box(Color("222b2e")), Rect2(71, 5, 19, 24))
	var top := 9.5 if dark else 6.0
	var rocker := Rect2(72, top, 17, 18)
	draw_style_box(_box(Color("e0e3e2").lerp(Color("9ba7a6"), darkness)), rocker)
	draw_line(rocker.position + Vector2(1, 1), rocker.position + Vector2(16, 1), Color("f2f5f1"), 1)
	draw_line(Vector2(75, top + 12), Vector2(86, top + 12), Color("6b7a7c"), 1)
	draw_circle(Vector2(80.5, 3), 1, ink)
	draw_circle(Vector2(80.5, 31), 1, ink)
	draw_string(get_theme_default_font(), Vector2(4, 22), "DARK" if dark else "LIGHT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
	if has_focus() or is_hovered():
		draw_rect(Rect2(63, -2, 35, 38), Color("72dfcf"), false, 1)

func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(2)
	return box
