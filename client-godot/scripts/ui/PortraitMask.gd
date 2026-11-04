extends Control

func _draw() -> void:
	draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, Color.WHITE)
