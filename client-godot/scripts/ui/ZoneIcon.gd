extends Control
const P = preload("res://scripts/ui/Palette.gd")
var kind := "Command"
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var color := Color("eed394") if kind == "Command" else Color("a5c5bc") if kind == "Graveyard" else Color("b4a5df")
	if kind == "Command":
		# Pixel crown, like a strategy-game command badge.
		draw_polyline(PackedVector2Array([Vector2(3, 8), Vector2(7, 12), Vector2(13, 5), Vector2(19, 12), Vector2(23, 8), Vector2(21, 20), Vector2(5, 20), Vector2(3, 8)]), color, 2)
		draw_line(Vector2(6, 23), Vector2(20, 23), color, 2)
		draw_rect(Rect2(12, 14, 3, 3), color)
	elif kind == "Graveyard":
		# Stepped tombstone and inset rune.
		draw_polyline(PackedVector2Array([Vector2(5, 22), Vector2(5, 8), Vector2(8, 8), Vector2(8, 4), Vector2(18, 4), Vector2(18, 8), Vector2(21, 8), Vector2(21, 22)]), color, 2)
		draw_line(Vector2(2, 24), Vector2(24, 24), color, 2)
		draw_line(Vector2(13, 10), Vector2(13, 19), color, 2)
		draw_line(Vector2(9, 13), Vector2(17, 13), color, 2)
	else:
		# Broken portal with a departing pixel spark.
		draw_polyline(PackedVector2Array([Vector2(19, 5), Vector2(9, 5), Vector2(4, 10), Vector2(4, 19), Vector2(9, 24), Vector2(19, 24), Vector2(23, 20)]), color, 2)
		draw_line(Vector2(10, 18), Vector2(23, 5), color, 2)
		draw_line(Vector2(16, 5), Vector2(23, 5), color, 2)
		draw_line(Vector2(23, 5), Vector2(23, 12), color, 2)
