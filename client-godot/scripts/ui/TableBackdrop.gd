extends Control
var cinematic_tint := 0.0:
	set(value):
		cinematic_tint = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("242629").lerp(Color("061b18"), cinematic_tint))
	# The table is reduced to roughly a quarter of its size on the physical CRT.
	# Give the teal preview enough coverage to survive that reduction, easing
	# back to the normal one-pixel grid as the camera fills the window.
	var line_width := lerpf(1.0, 4.0, cinematic_tint)
	for x in range(0, int(size.x) + 1, 48):
		var color := Color("3b3d40").lerp(Color("419c8c"), cinematic_tint) if x % 192 == 0 else Color("303236").lerp(Color("205b53"), cinematic_tint)
		draw_line(Vector2(x, 0), Vector2(x, size.y), color, line_width, cinematic_tint > 0.0)
	for y in range(0, int(size.y) + 1, 48):
		var color := Color("3b3d40").lerp(Color("419c8c"), cinematic_tint) if y % 192 == 0 else Color("303236").lerp(Color("205b53"), cinematic_tint)
		draw_line(Vector2(0, y), Vector2(size.x, y), color, line_width, cinematic_tint > 0.0)
