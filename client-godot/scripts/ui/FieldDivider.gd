extends Control
signal moved(pointer: Vector2)
signal finished
const P = preload("res://scripts/ui/Palette.gd")
var horizontal := false
var dragging := false
var over := false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_VSIZE if horizontal else Control.CURSOR_HSIZE
	mouse_entered.connect(func(): over = true; queue_redraw())
	mouse_exited.connect(func(): over = false; queue_redraw())
	resized.connect(queue_redraw)
	tooltip_text = "Drag to resize player fields. Double-click to reset."
	set_process_input(false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.double_click:
			moved.emit(Vector2.INF)
			finished.emit()
		else:
			dragging = true
			set_process_input(true)
		queue_redraw()
		accept_event()

func _input(event: InputEvent) -> void:
	if not dragging:
		return
	if event is InputEventMouseMotion:
		moved.emit(event.global_position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		cancel_drag()
		finished.emit()
		get_viewport().set_input_as_handled()

func cancel_drag() -> void:
	dragging = false
	set_process_input(false)
	queue_redraw()

func _draw() -> void:
	var color: Color = P.GOLD if dragging or over else P.MUTED
	var center := size * 0.5
	if horizontal:
		draw_line(Vector2(8, center.y), Vector2(size.x - 8, center.y), Color(color, 0.55), 1, true)
	else:
		draw_line(Vector2(center.x, 8), Vector2(center.x, size.y - 8), Color(color, 0.55), 1, true)
	for offset in [-5, 0, 5]:
		draw_circle(center + (Vector2(offset, 0) if horizontal else Vector2(0, offset)), 1.5, color)
