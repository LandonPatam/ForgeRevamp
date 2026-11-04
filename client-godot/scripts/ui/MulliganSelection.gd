extends Control
## Draw above the overlapping fan so every selected card keeps a clear marker.
const P = preload("res://scripts/ui/Palette.gd")
var opening: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50

func _process(_delta: float) -> void:
	if is_instance_valid(opening) and opening.active:
		queue_redraw()

func _draw() -> void:
	if not is_instance_valid(opening) or opening.input_kind != "InputLondonMulligan": return
	for card in opening.views:
		if not card.selected: continue
		draw_set_transform_matrix(card.get_transform())
		var frame := P.box(Color.TRANSPARENT, Color("ff6969"), 12, 0)
		frame.set_border_width_all(5)
		frame.shadow_color = Color(1.0, 0.12, 0.12, 0.6)
		frame.shadow_size = 12
		frame.shadow_offset = Vector2.ZERO
		draw_style_box(frame, Rect2(Vector2(-5, -5), card.size + Vector2(10, 10)))
		var badge := Rect2(12, 14, card.size.x - 24, 38)
		draw_style_box(P.box(Color("ff6969"), Color.WHITE, 7, 0), badge)
		draw_string(get_theme_default_font(), badge.position + Vector2(0, 26), "X DISCARD", HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, 20, Color("300909"))
	draw_set_transform_matrix(Transform2D.IDENTITY)
