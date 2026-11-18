extends Control
const Fx = preload("res://scripts/ui/TableFx.gd")
## How long a keyed arrow takes to draw itself on, at Normal animation speed.
const GROW_SECONDS := 0.3
var last_pointer := Vector2.INF
## Each line is [start, finish, color?, key?]. A keyed line (an attack or a block) draws itself
## on from its start the first time its key appears, then stays still.
var born: Dictionary = {}
var lines: Array = []:
	set(value):
		if lines == value: return
		lines = value
		last_pointer = Vector2.INF
		var now := Time.get_ticks_msec() / 1000.0
		var keys := {}
		for line in lines:
			if line.size() > 3:
				keys[line[3]] = true
				if not born.has(line[3]): born[line[3]] = now if Fx.enabled() else -INF
		for key in born.keys():
			if not keys.has(key): born.erase(key)
		# Fixed combat arrows use the retained drawing until their endpoints
		# change. A live targeting arrow still follows every pointer movement.
		set_process(_needs_process())
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(_needs_process())

func _growth(line: Array) -> float:
	if line.size() < 4 or not born.has(line[3]) or not Fx.enabled(): return 1.0
	var t: float = (Time.get_ticks_msec() / 1000.0 - born[line[3]]) / (GROW_SECONDS * Fx.speed)
	return clampf(t, 0.0, 1.0)

func _needs_process() -> bool:
	return lines.any(func(line): return line[1] == Vector2.INF or _growth(line) < 1.0)

func _process(_delta: float) -> void:
	var growing := lines.any(func(line): return _growth(line) < 1.0)
	var pointer := get_global_mouse_position()
	if pointer == last_pointer and not growing:
		set_process(_needs_process())
		return
	last_pointer = pointer
	queue_redraw()

func _draw() -> void:
	for line in lines:
		var color: Color = line[2] if line.size() > 2 else Color("d9b477")
		var start: Vector2 = line[0]
		var finish: Vector2 = get_global_mouse_position() if line[1] == Vector2.INF else line[1]
		var grown := 1.0 - pow(1.0 - _growth(line), 3)
		if grown <= 0.0: continue
		var middle := (start + finish) * 0.5 + Vector2(45, -55)
		var points := PackedVector2Array()
		var steps := maxi(2, int(ceil(32 * grown)))
		for i in range(steps + 1):
			var t := grown * float(i) / float(steps)
			points.append(start * pow(1 - t, 2) + middle * 2 * (1 - t) * t + finish * t * t)
		draw_polyline(points, Color(0.8, 0.64, 0.38, 0.12), 11, true)
		draw_polyline(points, color, 2, true)
		var tip: Vector2 = points[points.size() - 1]
		var direction := (tip - points[maxi(0, points.size() - 3)]).normalized()
		var normal := direction.orthogonal()
		draw_colored_polygon(PackedVector2Array([tip, tip - direction * 14 + normal * 6, tip - direction * 14 - normal * 6]), color)
		draw_circle(start, 5, color)
