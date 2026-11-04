extends Control
## Original vector landscapes, drawn locally. No downloaded or proprietary card artwork.
const P = preload("res://scripts/ui/Palette.gd")
var art_key := "grove"
var color_key := "G"
var seed_key := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key + art_key)
	var base: Color = P.accent(color_key)
	var top := base.darkened(0.66)
	var bottom := base.darkened(0.13)
	for y in range(64):
		var t := float(y) / 64.0
		draw_rect(Rect2(0, size.y * t, size.x, size.y / 64.0 + 1), top.lerp(bottom, t))
	var sun := Vector2(size.x * 0.7, size.y * 0.28)
	for i in range(12, 0, -1):
		draw_circle(sun, size.x * (0.11 + float(i) * 0.012), Color(base.r, base.g, base.b, 0.025))
	draw_circle(sun, size.x * 0.105, base.lightened(0.45))
	for i in range(24):
		var star := Vector2(rng.randf() * size.x, rng.randf() * size.y * 0.6)
		draw_circle(star, rng.randf_range(0.35, 0.95), Color(0.95, 0.98, 0.9, rng.randf_range(0.1, 0.45)))
	for layer in range(4):
		var points := PackedVector2Array([Vector2(0, size.y)])
		for i in range(10):
			var x := float(i) / 9.0 * size.x
			var y := size.y * (0.47 + float(layer) * 0.13 + rng.randf_range(-0.13, 0.09))
			points.append(Vector2(x, y))
		points.append(Vector2(size.x, size.y))
		draw_colored_polygon(points, base.darkened(0.38 + float(layer) * 0.14))
	if art_key == "grove":
		for i in range(7):
			var x := rng.randf_range(-0.1, 1.1) * size.x
			_tree(Vector2(x, size.y * rng.randf_range(0.9, 1.1)), size.y * rng.randf_range(0.45, 0.8), base.darkened(0.75), 3)
	elif art_key == "island":
		var water := Rect2(0, size.y * 0.71, size.x, size.y * 0.29)
		draw_rect(water, base.darkened(0.32))
		for i in range(20):
			var y := size.y * rng.randf_range(0.72, 0.99)
			var x := rng.randf_range(0.1, 0.9) * size.x
			draw_line(Vector2(x, y), Vector2(x + rng.randf_range(8, 30), y), Color(base.r, base.g, base.b, 0.28), 1)
		_tower(Vector2(size.x * 0.34, size.y * 0.72), size.y * 0.46, base.darkened(0.8))
	elif art_key == "ember":
		var peak := Vector2(size.x * 0.52, size.y * 0.37)
		draw_colored_polygon(PackedVector2Array([Vector2(-12, size.y), peak, Vector2(size.x, size.y)]), Color("25272c"))
		var lava := PackedVector2Array([peak, peak + Vector2(4, 22), peak + Vector2(-8, 35), Vector2(size.x * 0.6, size.y)])
		draw_polyline(lava, Color("edb07c"), 2.4, true)
		for i in range(12):
			draw_circle(Vector2(rng.randf() * size.x, rng.randf() * size.y), 1, Color("d69b67"))
	else:
		for i in range(4):
			_tower(Vector2(size.x * (0.18 + float(i) * 0.22), size.y * 0.92), size.y * rng.randf_range(0.3, 0.64), base.darkened(0.76))
	# Ground mist and a fine vignette give the small art a sense of distance.
	for i in range(5):
		draw_line(Vector2(0, size.y * (0.8 + float(i) * 0.035)), Vector2(size.x, size.y * (0.8 + float(i) * 0.035)), Color(base.r, base.g, base.b, 0.045), 4)

func _tower(foot: Vector2, height: float, ink: Color) -> void:
	var width := height * 0.22
	draw_rect(Rect2(foot.x - width * 0.5, foot.y - height, width, height), ink)
	draw_colored_polygon(PackedVector2Array([foot + Vector2(-width, -height), foot + Vector2(0, -height * 1.25), foot + Vector2(width, -height)]), ink)
	for i in range(3):
		draw_rect(Rect2(foot.x - 1, foot.y - height * (0.35 + float(i) * 0.19), 2, height * 0.08), P.GOLD)

func _tree(foot: Vector2, height: float, ink: Color, depth: int) -> void:
	var tip := foot + Vector2(height * 0.04, -height)
	draw_line(foot, tip, ink, maxf(1.0, height * 0.055), true)
	if depth == 0:
		return
	for side in [-1.0, 1.0]:
		var start := foot.lerp(tip, 0.62)
		var end := start + Vector2(side * height * 0.35, -height * 0.32)
		draw_line(start, end, ink, maxf(1.0, height * 0.03), true)
		draw_circle(end, height * 0.26, ink)
		draw_circle(tip, height * 0.24, ink)
