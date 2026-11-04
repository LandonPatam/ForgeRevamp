extends RefCounted
## The same phosphor block meter on the deck console and match boot screen.
static func paint(canvas: CanvasItem, bounds: Rect2, value: float, ink: Color = Color("84e3ce")) -> void:
	var width := bounds.size.x / 50.0
	for index in range(50):
		var segment := Rect2(bounds.position + Vector2(index * width, 0), Vector2(width - 4, bounds.size.y))
		canvas.draw_rect(segment, ink if float(index) / 50 < clampf(value, 0, 1) else Color("174a42"))
