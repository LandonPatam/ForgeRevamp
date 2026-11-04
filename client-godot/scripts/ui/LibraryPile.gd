extends Control
signal drag_started(pointer: Vector2)
signal drag_moved(pointer: Vector2)
signal drag_finished(pointer: Vector2, cancelled: bool)
const P = preload("res://scripts/ui/Palette.gd")
const BACK = preload("res://assets/black-lotus-back.tres")
var enabled := true
var ghost := false
var pressed := false
var dragging := false
var origin := Vector2.ZERO
var pointer := Vector2.ZERO
var cue_time := 0.0
var draw_cue := false:
	set(value):
		draw_cue = value
		set_process(value)
		queue_redraw()

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	set_process_input(false)
	set_process(draw_cue)

func _process(delta: float) -> void:
	cue_time += delta
	queue_redraw()

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(144, 202))
	if not ghost:
		for i in range(4, 0, -1):
			draw_style_box(P.box(Color("10151c"), Color("65553d"), 7, 0), Rect2(i * 2, -i * 3, 144, 202))
	draw_style_box(P.box(Color("111b2c"), P.GOLD.darkened(0.15), 7, 0), Rect2(0, 0, 144, 202))
	if draw_cue and not ghost:
		var pulse := (sin(cue_time * 4.5) + 1.0) * 0.5
		for i in range(8, 0, -1):
			var outline := P.box(Color.TRANSPARENT, Color(1, 1, 1, (0.05 + 0.12 * pulse) * (1.0 - i / 10.0)), 9 + i * 2, 0)
			outline.set_border_width_all(4)
			draw_style_box(outline, Rect2(0, 0, 144, 202).grow(i * 3))
		var rim := P.box(Color.TRANSPARENT, Color.WHITE, 8, 0)
		rim.set_border_width_all(4)
		draw_style_box(rim, Rect2(0, 0, 144, 202).grow(3))
	draw_texture_rect(BACK, Rect2(0, 0, 144, 202), false)
	draw_set_transform(Vector2.ZERO)

func _gui_input(event: InputEvent) -> void:
	if ghost or not enabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
		origin = event.global_position
		pointer = origin
		set_process_input(true)
		accept_event()

func _input(event: InputEvent) -> void:
	if not pressed:
		return
	if event is InputEventMouseMotion:
		pointer = event.global_position
		if not dragging and pointer.distance_to(origin) >= 8:
			dragging = true
			drag_started.emit(pointer)
		if dragging:
			drag_moved.emit(pointer)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		pointer = event.global_position
		finish_drag(false)
		get_viewport().set_input_as_handled()

func finish_drag(cancelled: bool) -> void:
	var was_dragging := dragging
	pressed = false
	dragging = false
	set_process_input(false)
	if was_dragging:
		drag_finished.emit(pointer, cancelled)

func cancel_drag() -> void:
	finish_drag(true)
