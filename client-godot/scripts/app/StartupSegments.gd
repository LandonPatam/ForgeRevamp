extends Control
var value := 0.0
const INK := Color("70d6bc")
const SEGMENTS := 48

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var width := size.x / SEGMENTS
	var filled := floori(value * SEGMENTS)
	for index in range(SEGMENTS):
		var rect := Rect2(Vector2(index * width + 2, 0), Vector2(width - 4, size.y))
		var ink := Color("12362f")
		if index < filled: ink = INK
		elif index == filled: ink = Color("20564b").lerp(INK, 0.12 + 0.10 * sin(Time.get_ticks_msec() * 0.005))
		draw_rect(rect, ink)
