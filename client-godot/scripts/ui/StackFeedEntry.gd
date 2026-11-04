extends Button
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
signal item_selected(value: Dictionary)
static var terminal_font: SystemFont
var item: Dictionary = {}
var heading: Label
var source_label: Label
var caster_label: Label
var rules_label: Label
var targets_label: Label
var column: VBoxContainer
var next_to_resolve := false
var clock := 0.0
var last_cursor := -1
var position_index := 0
var appearance := 0.0

func _ready() -> void:
	if terminal_font == null:
		terminal_font = SystemFont.new()
		terminal_font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono"])
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inset := MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]: inset.add_theme_constant_override("margin_" + edge, 12)
	add_child(inset)
	column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 5)
	inset.add_child(column)
	heading = _label(12, Terminal.MUTED.lightened(0.15))
	source_label = _label(15, Terminal.INK.lightened(0.1))
	caster_label = _label(11, Terminal.MUTED)
	rules_label = _label(13, Terminal.INK.darkened(0.15))
	targets_label = _label(11, Terminal.INK)
	column.minimum_size_changed.connect(_sync_height)
	pressed.connect(func(): item_selected.emit(item))
	modulate.a = 0.0

func _sync_height() -> void:
	custom_minimum_size.y = maxf(74, column.get_combined_minimum_size().y + 24)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 180
	label.add_theme_font_override("font", terminal_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	column.add_child(label)
	return label

func present(value: Dictionary, index: int) -> void:
	item = value.duplicate(true)
	position_index = index
	next_to_resolve = index == 0
	var edge := Terminal.ACCENT.darkened(0.3) if next_to_resolve else Terminal.EDGE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("14363d") if state == "hover" else Color("091d20")
		box.border_color = Terminal.INK if state == "focus" else edge
		box.set_border_width_all(1)
		box.border_width_left = 3 if next_to_resolve else 1
		box.set_corner_radius_all(3)
		add_theme_stylebox_override(state, box)
	source_label.text = item.get("sourceName", item.get("card", {}).get("name", "Stack item"))
	caster_label.text = "FROM  " + str(item.get("controllerName", ""))
	caster_label.visible = not str(item.get("controllerName", "")).is_empty()
	rules_label.text = str(item.get("text", ""))
	var names: Array = item.get("targets", []).map(func(target): return str(target.get("name", target.get("sourceName", "Target"))))
	targets_label.text = "-> " + ", ".join(names)
	targets_label.visible = not names.is_empty()
	heading.add_theme_color_override("font_color", Terminal.ACCENT if next_to_resolve else Terminal.MUTED.lightened(0.15))
	last_cursor = -1
	_update_heading()
	set_process(next_to_resolve or appearance < 1.0)
	custom_minimum_size.y = maxf(74, column.get_combined_minimum_size().y + 24)
	queue_redraw()

func _update_heading() -> void:
	var cursor := int(clock * 1.5) % 2 if next_to_resolve else 0
	if cursor == last_cursor: return
	last_cursor = cursor
	var kind := "TRIGGER" if item.get("trigger", false) else ("ACTIVATE" if item.has("trigger") else "ABILITY") if item.get("ability", false) else "CAST"
	heading.text = "%s %02d %-8s%s" % [">" if next_to_resolve and cursor == 0 else " ", position_index + 1, kind, " / NEXT" if next_to_resolve else " / QUEUED"]

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	clock += delta
	appearance = minf(1.0, appearance + delta / 0.18)
	modulate.a = smoothstep(0.0, 1.0, appearance)
	_update_heading()
	if not next_to_resolve and appearance >= 1.0: set_process(false)

func _draw() -> void:
	# Fine CRT rows tint the inset without obscuring the text or artwork.
	for y in range(5, int(size.y)-4, 4):
		draw_line(Vector2(5,y), Vector2(size.x-5,y), Color(0.10,0.25,0.28,0.07), 1)
