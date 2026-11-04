extends Control
var value := 0.0
const INK := Color("68cdb9")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK, false, 2.0)
	var cell := (size - Vector2(12, 12)) / 16.0
	var filled := floori(value * 256.0)
	for index in range(256):
		var row := index / 16
		var column := index % 16 if row % 2 == 0 else 15 - index % 16
		var rect := Rect2(Vector2(6, 6) + Vector2(column, row) * cell, cell - Vector2(2, 2))
		var ink := INK * Color(0.13, 0.20, 0.18, 1.0)
		if index < filled:
			ink = INK * (0.68 + 0.32 * clampf(float(index - filled + 9) / 8.0, 0, 1))
		elif index == filled:
			ink = INK * (0.28 + 0.18 * sin(Time.get_ticks_msec() * 0.004))
		ink.a = 1.0
		draw_rect(rect, ink)
