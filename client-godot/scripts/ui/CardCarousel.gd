extends Control
## Library searches as a carousel: the focused card large in the middle, its neighbors smaller,
## darker and tucked behind on either side. Items are SelectionPanel's stacked groups (FOREST ×3);
## the panel still decides which exact instance a pick sends. A small pool of card views is reused
## as the carousel turns, so a 99-card library never builds 99 faces.
signal focus_requested(index: int)
signal pick_requested(index: int)

const Card = preload("res://scripts/ui/CardView.gd")
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const CARD_SIZE := Vector2(288, 404)
const POOL := 7 # Focus ±3.
const STEP := [0.0, 205.0, 335.0, 420.0] # Horizontal offset of each neighbor ring from the center.
const SCALE := [1.0, 0.76, 0.58, 0.46]
const SHADE := [1.0, 0.62, 0.42, 0.0]

var items: Array = []    ## Card data per group.
var counts: Array = []   ## Copies per group.
var picked: Array = []   ## Picked copies per group.
var focus := 0
var position_now := 0.0  ## Fractional focus the views are drawn at; glides toward focus.
var views: Array = []
var badges: Array = []

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(STEP[3] * 2.0 + CARD_SIZE.x * SCALE[3] + 40.0, CARD_SIZE.y + 48.0)
	for i in range(POOL):
		var view := Card.new()
		view.inspection = true
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.size = CARD_SIZE
		view.custom_minimum_size = CARD_SIZE
		view.pivot_offset = CARD_SIZE * 0.5
		add_child(view)
		var badge := Label.new()
		badge.add_theme_font_override("font", Terminal.font())
		badge.add_theme_font_size_override("font_size", 20)
		badge.add_theme_color_override("font_color", Color("0b0d12"))
		var box := StyleBoxFlat.new()
		box.bg_color = Color("b48cff")
		box.set_corner_radius_all(6)
		box.set_content_margin_all(6)
		badge.add_theme_stylebox_override("normal", box)
		badge.hide()
		view.add_child(badge)
		views.append(view)
		badges.append(badge)
	set_process(false)

func set_items(value: Array, copies: Array, chosen: Array) -> void:
	var rebuilt := value != items
	items = value
	counts = copies
	picked = chosen
	if rebuilt:
		focus = clampi(focus, 0, maxi(0, items.size() - 1))
		position_now = focus
	_layout()

func set_focus(index: int) -> void:
	if items.is_empty(): return
	focus = clampi(index, 0, items.size() - 1)
	set_process(true)

func _process(delta: float) -> void:
	position_now = lerpf(position_now, focus, 1.0 - exp(-14.0 * delta))
	if absf(position_now - focus) < 0.002:
		position_now = focus
		set_process(false)
	_layout()

func _ring(distance: float, table: Array) -> float:
	var low := mini(int(floor(distance)), table.size() - 1)
	var high := mini(low + 1, table.size() - 1)
	return lerpf(table[low], table[high], distance - floor(distance))

func _layout() -> void:
	var center := size * 0.5 if size.x > 0 else custom_minimum_size * 0.5
	var base := int(round(position_now))
	for slot in range(POOL):
		var index := base - 3 + slot
		# Each group keeps the same pooled view while it stays in range, so faces aren't repainted as it moves.
		var view: Control = views[posmod(index, POOL)]
		var badge: Label = badges[posmod(index, POOL)]
		if index < 0 or index >= items.size():
			view.hide()
			continue
		var offset := index - position_now
		var distance := absf(offset)
		if distance > 3.0:
			view.hide()
			continue
		view.show()
		view.update_card(items[index])
		view.set_selected(int(picked[index]) > 0)
		var scale_now := _ring(distance, SCALE)
		var shade := _ring(distance, SHADE)
		view.scale = Vector2.ONE * scale_now
		view.position = (center + Vector2(signf(offset) * _ring(distance, STEP), 0) - CARD_SIZE * 0.5).round()
		view.modulate = Color(shade, shade, shade, clampf((3.0 - distance) * 1.5, 0.0, 1.0))
		view.z_index = 10 - int(round(distance * 3.0)) # Nearer the middle draws in front.
		var count := int(counts[index])
		badge.visible = int(picked[index]) > 0 or count > 1
		badge.text = ("✓ " if int(picked[index]) > 0 else "") + ("%d/%d" % [int(picked[index]), count] if count > 1 and int(picked[index]) > 0 else ("×%d" % count if count > 1 else "PICKED"))
		# Hangs off the top-right corner so it never covers the card's name.
		badge.reset_size()
		badge.position = Vector2(CARD_SIZE.x - badge.size.x + 10, -18)

## The item drawn frontmost under a point, or -1.
func item_at(point: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for index in range(maxi(0, int(round(position_now)) - 3), mini(items.size(), int(round(position_now)) + 4)):
		var view: Control = views[posmod(index, POOL)]
		if not view.visible: continue
		var rect := Rect2(view.position + CARD_SIZE * 0.5 * (Vector2.ONE - view.scale), CARD_SIZE * view.scale)
		var distance := absf(index - position_now)
		if rect.has_point(point) and distance < best_distance:
			best = index
			best_distance = distance
	return best

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT: focus_requested.emit(maxi(focus - 1, 0))
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT: focus_requested.emit(mini(focus + 1, items.size() - 1))
			MOUSE_BUTTON_LEFT:
				var index := item_at(event.position)
				if index < 0: return
				if index == focus: pick_requested.emit(index)
				else: focus_requested.emit(index)
			_: return
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _layout()
