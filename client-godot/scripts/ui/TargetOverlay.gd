extends Control
var last_pointer := Vector2.INF
var lines: Array = []:
	set(value):
		if lines == value: return
		lines = value
		last_pointer = Vector2.INF
		# Fixed combat arrows use the retained drawing until their endpoints
		# change. A live targeting arrow still follows every pointer movement.
		set_process(lines.any(func(line): return line[1] == Vector2.INF))
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(lines.any(func(line): return line[1] == Vector2.INF))

func _process(_delta: float) -> void:
	var pointer := get_global_mouse_position()
	if pointer == last_pointer: return
	last_pointer = pointer
	queue_redraw()

func _draw() -> void:
	for line in lines:
		var color: Color = line[2] if line.size() > 2 else Color("d9b477")
		var start: Vector2 = line[0]
		var finish: Vector2 = get_global_mouse_position() if line[1] == Vector2.INF else line[1]
		var middle := (start + finish) * 0.5 + Vector2(45, -55)
		var points := PackedVector2Array()
		for i in range(33):
			var t := float(i) / 32.0
			points.append(start * pow(1 - t, 2) + middle * 2 * (1 - t) * t + finish * t * t)
		draw_polyline(points, Color(0.8, 0.64, 0.38, 0.12), 11, true)
		draw_polyline(points, color, 2, true)
		var direction := (finish - points[30]).normalized()
		var normal := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([finish, finish - direction * 14 + normal * 6, finish - direction * 14 - normal * 6]), color)
		draw_circle(start, 5, color)
