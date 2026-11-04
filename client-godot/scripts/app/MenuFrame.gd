extends Control
var darkness := 0.0:
	set(value):
		darkness = value
		queue_redraw()

var top_edge := 26.0
var top_gaps: Array[Vector2] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func align_header(controls: Array, center_y: float) -> void:
	top_edge = center_y
	top_gaps.clear()
	for control in controls:
		var bounds: Rect2 = control.get_rect()
		if bounds.position.y <= top_edge and bounds.end.y >= top_edge:
			top_gaps.append(Vector2(bounds.position.x, bounds.end.x))
	top_gaps.sort_custom(func(a, b): return a.x < b.x)
	queue_redraw()

func _draw() -> void:
	var ink := Color("a9b8ba").lerp(Color("657477"), darkness)
	var left := 18.0
	var right := size.x - 18.0
	var bottom := size.y - 18.0
	var radius := 8.0
	# The top edge meets the header controls at their side midpoints.
	# Leave gaps for every control, including the transparent light switch.
	var cursor := left + radius
	for gap in top_gaps:
		var start := clampf(gap.x, left + radius, right - radius)
		if start > cursor: draw_line(Vector2(cursor, top_edge), Vector2(start, top_edge), ink, 1, true)
		cursor = maxf(cursor, gap.y)
	if cursor < right - radius: draw_line(Vector2(cursor, top_edge), Vector2(right - radius, top_edge), ink, 1, true)
	draw_line(Vector2(left, top_edge + radius), Vector2(left, bottom - radius), ink, 1, true)
	draw_line(Vector2(left + radius, bottom), Vector2(right - radius, bottom), ink, 1, true)
	draw_line(Vector2(right, bottom - radius), Vector2(right, top_edge + radius), ink, 1, true)
	draw_arc(Vector2(left + radius, top_edge + radius), radius, PI, PI * 1.5, 13, ink, 1, true)
	draw_arc(Vector2(right - radius, top_edge + radius), radius, -PI * 0.5, 0, 13, ink, 1, true)
	draw_arc(Vector2(left + radius, bottom - radius), radius, PI * 0.5, PI, 13, ink, 1, true)
	draw_arc(Vector2(right - radius, bottom - radius), radius, 0, PI * 0.5, 13, ink, 1, true)
