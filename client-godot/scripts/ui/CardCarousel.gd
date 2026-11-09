extends Control
## Library searches as a carousel that moves like the home floppy carousel (DeckCarousel.gd): one
## continuous closeness curve sets each card's size, tint, tilt and depth; a fractional cursor eases
## toward the focused card and can be dragged; wheel and arrows step. The focused card sits large in
## the middle with a gentle lift and bob, its neighbors smaller, darker and behind.
## Items are SelectionPanel's stacked groups (FOREST ×3). Clicking only focuses or marks a card;
## the panel's OK sends the marked cards to Forge, so a stray click never commits a search.
## A small pool of views is reused as the carousel turns, so a 99-card library never builds 99 faces.
signal focus_requested(index: int)
signal pick_requested(index: int)
signal unpick_requested(index: int)

const Card = preload("res://scripts/ui/CardView.gd")
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const CARD_SIZE := Vector2(288, 404)
const POOL := 7 # Cursor ±3.
const SPACING := 205.0
const LIFT := 14.0

var items: Array = []    ## Card data per group.
var counts: Array = []   ## Copies per group.
var marked: Array = []   ## Marked copies per group.
var mark_labels: Array = [] ## Badge text per group: which of your picks it is ("✓ 1 OF 2").
var focus := 0
var cursor := 0.0        ## Fractional position the cards are drawn at.
var target := 0.0
var elapsed := 0.0
var dragging := false
var moved := false
var press_position := Vector2.ZERO
var press_cursor := 0.0
var wheel_at := 0
var pan_at := 0
var views: Array = []
var badges: Array = []      ## Copies in a stacked group: a dark terminal tag off the top-right corner.
var mark_badges: Array = [] ## Your marks: a solid purple banner across the bottom edge.

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(SPACING * 4.0 + CARD_SIZE.x * 0.62 + 24.0, CARD_SIZE.y + 56.0)
	for i in range(POOL):
		var view := Card.new()
		view.inspection = true
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.size = CARD_SIZE
		view.custom_minimum_size = CARD_SIZE
		add_child(view)
		var badge := _badge(Color("0b1418"), Terminal.INK, Terminal.EDGE.lightened(0.35), 18)
		view.add_child(badge)
		var mark := _badge(Color("b48cff"), Color("0b0d12"), Color("e9ddff"), 20)
		view.add_child(mark)
		views.append(view)
		badges.append(badge)
		mark_badges.append(mark)

func _badge(fill: Color, ink: Color, edge: Color, font_size: int) -> Label:
	var badge := Label.new()
	badge.add_theme_font_override("font", Terminal.font())
	badge.add_theme_font_size_override("font_size", font_size)
	badge.add_theme_color_override("font_color", ink)
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	badge.add_theme_stylebox_override("normal", box)
	badge.hide()
	return badge

func set_items(value: Array, copies: Array, marks: Array, labels: Array = []) -> void:
	var rebuilt := value != items
	items = value
	counts = copies
	marked = marks
	mark_labels = labels
	if rebuilt:
		focus = clampi(focus, 0, maxi(0, items.size() - 1))
		cursor = focus
		target = focus
	_arrange()

## Queued steps keep moving in their direction even before the animation catches up.
func set_focus(index: int) -> void:
	if items.is_empty(): return
	var next := clampi(index, 0, items.size() - 1)
	if next == focus and not dragging: return
	focus = next
	if not dragging: target = focus

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	elapsed += delta
	if not dragging and Time.get_ticks_msec() - pan_at > 160:
		cursor = lerpf(cursor, target, 1.0 - exp(-delta * 10.0))
		if absf(cursor - target) < 0.0001: cursor = target
	_arrange()

func _arrange() -> void:
	var base := int(round(cursor))
	for slot in range(POOL):
		var index := base - 3 + slot
		# Each group keeps the same pooled view while it stays in range, so faces aren't repainted as it moves.
		var view: Control = views[posmod(index, POOL)]
		var badge: Label = badges[posmod(index, POOL)]
		var mark: Label = mark_badges[posmod(index, POOL)]
		if index < 0 or index >= items.size():
			view.hide()
			continue
		var distance := float(index) - cursor
		if absf(distance) > 2.9:
			view.hide()
			continue
		view.show()
		view.update_card(items[index])
		view.set_selected(int(marked[index]) > 0)
		_place(view, distance)
		var count := int(counts[index])
		var picks := int(marked[index])
		badge.visible = count > 1
		badge.text = "×%d" % count
		badge.reset_size()
		badge.position = Vector2(CARD_SIZE.x - badge.size.x + 10, -18)
		mark.visible = picks > 0
		mark.text = str(mark_labels[index]) if index < mark_labels.size() and not str(mark_labels[index]).is_empty() else "✓ SELECTED"
		mark.reset_size()
		mark.position = Vector2((CARD_SIZE.x - mark.size.x) * 0.5, CARD_SIZE.y - mark.size.y * 0.5).round()

## The home carousel's curve: everything follows one smooth closeness value, so there are no steps.
func _place(view: Control, distance: float) -> void:
	var area := size if size.x > 0 else custom_minimum_size
	var closeness := exp(-distance * distance * 2.1)
	var depth := lerpf(0.62, 1.0, closeness)
	var bob := sin(elapsed * 1.35 + 0.4) * 3.0 * closeness
	var center := Vector2(area.x * 0.5 + distance * SPACING, area.y * 0.5 + 10.0 - closeness * LIFT + bob)
	view.pivot_offset = CARD_SIZE * 0.5
	view.position = center - CARD_SIZE * 0.5
	view.scale = Vector2.ONE * depth
	view.rotation = clampf(distance, -2, 2) * -0.045 + sin(elapsed * 0.9) * 0.012 * closeness
	view.z_index = 10 + int(closeness * 20)
	var tint := Color.WHITE.lerp(Color(0.5, 0.54, 0.58), 1.0 - closeness)
	tint.a = clampf((2.9 - absf(distance)) / 0.7, 0.0, 1.0)
	view.modulate = tint

## The frontmost item under a point, or -1.
func item_at(point: Vector2) -> int:
	var found := -1
	var top := -1
	var base := int(round(cursor))
	for index in range(maxi(0, base - 3), mini(items.size(), base + 4)):
		var view: Control = views[posmod(index, POOL)]
		if not view.visible or view.z_index < top: continue
		if Rect2(Vector2.ZERO, CARD_SIZE).has_point(view.get_transform().affine_inverse() * point):
			found = index
			top = view.z_index
	return found

func _gui_input(event: InputEvent) -> void:
	if items.is_empty(): return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			if Time.get_ticks_msec() - wheel_at > 140:
				wheel_at = Time.get_ticks_msec()
				focus_requested.emit(clampi(focus + (1 if event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT] else -1), 0, items.size() - 1))
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click removes a mark from the card under the pointer (and turns to it).
			if event.pressed and not dragging:
				var index := item_at(event.position)
				if index >= 0:
					focus_requested.emit(index)
					target = focus
					unpick_requested.emit(index)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				moved = false
				press_position = event.position
				press_cursor = cursor
			elif dragging:
				dragging = false
				if moved:
					focus_requested.emit(clampi(roundi(cursor), 0, items.size() - 1))
					target = focus
				else:
					var index := item_at(event.position)
					if index == focus: pick_requested.emit(index)
					elif index >= 0: focus_requested.emit(index)
					target = focus
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		var shift: float = event.position.x - press_position.x
		moved = moved or absf(shift) > 8
		if moved:
			cursor = clampf(press_cursor - shift / SPACING, 0, items.size() - 1)
			if roundi(cursor) != focus: focus_requested.emit(roundi(cursor))
		accept_event()
	elif event is InputEventPanGesture:
		pan_at = Time.get_ticks_msec()
		cursor = clampf(cursor + (event.delta.x + event.delta.y) * 0.09, 0, items.size() - 1)
		focus_requested.emit(roundi(cursor))
		target = focus
		accept_event()
