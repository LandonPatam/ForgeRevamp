extends Control
## Stack builder for a full ordering (simultaneous triggers): the abilities as a terminal pile in
## the stack feed's style, top row resolves first. It opens in Forge's supplied order; drag a row,
## or Shift+↑↓ the focused one, to move it. Rows glide to their slots, so a reorder reads as the pile
## being rearranged. Nothing reaches Forge here: the popup's Confirm sends `order`.
signal order_changed
signal focus_changed(option: int)
signal preview_changed(option: int) ## The row being dragged, else hovered, else focused.
signal submit_requested

const Card = preload("res://scripts/ui/CardView.gd")
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const ROW_H := 98.0
const GAP := 8.0
const WIDTH := 600.0
var width := WIDTH
const THUMB := Vector2(62, 87)

var options: Array = []
var order: Array[int] = []   ## Option indexes, first to resolve first.
var rows: Array = []         ## Row per option index.
var numbers: Array = []
var focus := 0               ## Focused option index.
var hover := -1
var dragging := -1
var drag_moved := false
var press_y := 0.0
var grab_offset := 0.0
var locked := false
var previewed := -1

func setup(value: Array, initial: Array[int], row_width: float = WIDTH) -> void:
	width = row_width
	options = value
	order = initial.duplicate()
	for child in get_children(): child.queue_free()
	rows.clear()
	numbers.clear()
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	custom_minimum_size = Vector2(width, options.size() * (ROW_H + GAP) - GAP)
	for i in range(options.size()):
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.size = Vector2(width, ROW_H)
		row.custom_minimum_size = row.size
		add_child(row)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 14)
		row.add_child(line)
		var number := _label(40, Terminal.INK)
		number.custom_minimum_size.x = 44
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number.size_flags_vertical = Control.SIZE_EXPAND_FILL
		line.add_child(number)
		var option: Dictionary = options[i]
		if option.has("card"):
			var thumb := Card.new()
			thumb.inspection = true
			thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			thumb.custom_minimum_size = THUMB
			thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(thumb)
			thumb.update_card(option.card)
		var words := VBoxContainer.new()
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		words.add_theme_constant_override("separation", 4)
		line.add_child(words)
		var card_name := str(option.get("card", {}).get("name", ""))
		var title := _label(17, Terminal.INK.lightened(0.15))
		title.text = card_name.to_upper() if not card_name.is_empty() else "ABILITY"
		words.add_child(title)
		var effect := _label(13, Terminal.INK.darkened(0.12))
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.max_lines_visible = 3
		effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		effect.text = ability_text(option)
		words.add_child(effect)
		var grip := _label(26, Terminal.MUTED)
		grip.text = "≡"
		grip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grip.size_flags_vertical = Control.SIZE_EXPAND_FILL
		line.add_child(grip)
		row.position = Vector2(0, _slot_y(order.find(i)))
		rows.append(row)
		numbers.append(number)
	focus = order[0] if not order.is_empty() else 0
	_restyle()

## The ability's own words, without a leading "Card Name - " the row already shows or Forge's trailing bookkeeping.
static func ability_text(option: Dictionary) -> String:
	var text := str(option.get("label", "")).strip_edges()
	# Forge appends trigger bookkeeping such as "[Zone Changer: Elvish Visionary (304)]".
	var bookkeeping := RegEx.create_from_string("\\s*\\[[^\\]]*\\]\\s*$")
	text = bookkeeping.sub(text, "").strip_edges()
	var card_name := str(option.get("card", {}).get("name", ""))
	for separator in [" - ", " — ", ": "]:
		if not card_name.is_empty() and text.begins_with(card_name + separator): return text.substr((card_name + separator).length()).strip_edges()
	return text

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", Terminal.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _slot_y(slot: int) -> float:
	return slot * (ROW_H + GAP)

func _slot_at(y: float) -> int:
	return clampi(int(floor(y / (ROW_H + GAP))), 0, order.size() - 1)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var blend := 1.0 - exp(-delta * 16.0)
	for slot in range(order.size()):
		var option: int = order[slot]
		var row: Control = rows[option]
		if option == dragging and drag_moved: continue
		row.position.y = lerpf(row.position.y, _slot_y(slot), blend)
		row.scale = row.scale.lerp(Vector2.ONE, blend)

func _restyle() -> void:
	for slot in range(order.size()):
		var option: int = order[slot]
		var first := slot == 0
		var lifted := option == dragging and drag_moved
		var box := StyleBoxFlat.new()
		box.bg_color = Color("1b2032") if lifted else (Color("14363d") if option == hover or option == focus else Color("091d20"))
		box.border_color = Terminal.ACCENT if lifted or (option == focus and has_focus()) else (Terminal.INK if option == focus else (Terminal.ACCENT.darkened(0.3) if first else Terminal.EDGE))
		box.set_border_width_all(2 if lifted or option == focus else 1)
		box.border_width_left = 4 if first else box.border_width_left
		box.set_corner_radius_all(3)
		box.set_content_margin_all(5)
		box.content_margin_left = 8
		box.content_margin_right = 14
		if lifted:
			box.shadow_color = Color(0, 0, 0, 0.55)
			box.shadow_size = 14
			box.shadow_offset = Vector2(0, 6)
		rows[option].add_theme_stylebox_override("panel", box)
		rows[option].z_index = 5 if lifted else 0
		numbers[option].text = str(slot + 1)
		numbers[option].add_theme_color_override("font_color", Terminal.ACCENT if first else Terminal.INK)
	var shown := dragging if dragging >= 0 else (hover if hover >= 0 else focus)
	if shown != previewed and shown >= 0:
		previewed = shown
		preview_changed.emit(shown)

func set_focus(option: int) -> void:
	if option < 0 or option >= rows.size(): return
	focus = option
	_restyle()
	focus_changed.emit(option)

## Moves an option to a slot; the other rows glide to make room.
func move(option: int, slot: int) -> void:
	slot = clampi(slot, 0, order.size() - 1)
	var from := order.find(option)
	if from < 0 or from == slot: return
	order.remove_at(from)
	order.insert(slot, option)
	_restyle()
	order_changed.emit()

func set_order(value: Array[int]) -> void:
	order = value.duplicate()
	_restyle()
	order_changed.emit()

func _option_at(y: float) -> int:
	for slot in range(order.size()):
		if y >= _slot_y(slot) and y < _slot_y(slot) + ROW_H: return order[slot]
	return -1

func _gui_input(event: InputEvent) -> void:
	if locked or order.is_empty(): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var option := _option_at(event.position.y)
			if option < 0: return
			grab_focus()
			dragging = option
			drag_moved = false
			press_y = event.position.y
			grab_offset = event.position.y - rows[option].position.y
			set_focus(option)
		elif dragging >= 0:
			var was := dragging
			dragging = -1
			drag_moved = false
			if rows[was].position.y != _slot_y(order.find(was)): rows[was].scale = Vector2.ONE * 1.03
			_restyle()
		accept_event()
	elif event is InputEventMouseMotion:
		if dragging >= 0:
			if not drag_moved and absf(event.position.y - press_y) > 6:
				drag_moved = true
				_restyle()
			if drag_moved:
				var row: Control = rows[dragging]
				row.position.y = clampf(event.position.y - grab_offset, -ROW_H * 0.35, _slot_y(order.size() - 1) + ROW_H * 0.35)
				row.scale = Vector2.ONE * 1.03
				move(dragging, _slot_at(row.position.y + ROW_H * 0.5))
			accept_event()
		else:
			var under := _option_at(event.position.y)
			if under != hover:
				hover = under
				_restyle()
	elif event is InputEventKey and event.pressed:
		var step := -1 if event.keycode == KEY_UP else (1 if event.keycode == KEY_DOWN else 0)
		if step != 0:
			var slot := order.find(focus)
			if event.shift_pressed: move(focus, slot + step)
			else: set_focus(order[clampi(slot + step, 0, order.size() - 1)])
			accept_event()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			submit_requested.emit()
			accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover >= 0:
		hover = -1
		_restyle()
	elif what in [NOTIFICATION_FOCUS_ENTER, NOTIFICATION_FOCUS_EXIT] and not rows.is_empty():
		_restyle()
