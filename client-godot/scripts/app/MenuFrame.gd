extends Control
var darkness := 0.0:
	set(value):
		darkness = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var border := StyleBoxFlat.new()
	border.bg_color = Color.TRANSPARENT
	border.border_color = Color("a9b8ba").lerp(Color("657477"), darkness)
	border.set_border_width_all(1)
	border.set_corner_radius_all(8)
	border.corner_detail = 12
	draw_style_box(border, Rect2(18, 26, size.x - 36, size.y - 44))
