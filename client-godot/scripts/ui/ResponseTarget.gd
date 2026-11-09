extends Control
## Picking what your spell answers ("Counterspell -> Wrath of God"): the spell you are casting sits
## large on the table, a terminal menu branches off it with the spells it can target (the
## highlighted one shown large), and a second branch runs from that card to its entry on the stack.
## Nothing reaches Forge until the [Y] button; [N] cancels the cast like Forge's own Cancel.
signal answered(id: int, value: Variant)

const Card = preload("res://scripts/ui/CardView.gd")
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const P = preload("res://scripts/ui/Palette.gd")
const GAP := 44.0
const TARGET_LINE := Color("ffb978")

var ask: Dictionary = {}
var table_rect := Rect2()
## Main supplies the stack entry rectangle for a stack id (global), or an empty Rect2.
var stack_rect: Callable
var spell_card: Control
var box: PanelContainer
var title: Label
var line: Label
var rows: VBoxContainer
var target_view: Control
var confirm: Button
var cancel: Button
var focus := 0
var sent := false
var question := ""
var cursor_on := true
var blink := 0.0
var started := 0
var ready_now := true

## A target choice for a spell this seat is casting, where every option is something on the stack.
static func accepts(value: Dictionary) -> bool:
	var options: Array = value.get("options", [])
	return value.get("kind", "") == "choose" and value.get("casting", false) and not value.get("sourceCard", {}).is_empty() and int(value.get("max", 0)) == 1 and not options.is_empty() and options.all(func(option): return option.has("stackId") and option.has("card"))

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 76
	spell_card = Card.new()
	spell_card.inspection = true
	spell_card.table_angle = false
	spell_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spell_card)
	box = PanelContainer.new()
	Terminal.panel(box, 12)
	var frame := box.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	frame.border_color = Terminal.ACCENT
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 10
	box.add_theme_stylebox_override("panel", frame)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	box.add_child(column)
	title = _label(12, Terminal.MUTED)
	column.add_child(title)
	line = _label(16, Terminal.INK)
	column.add_child(line)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	column.add_child(rows)
	var center := CenterContainer.new()
	column.add_child(center)
	target_view = Card.new()
	target_view.inspection = true
	target_view.table_angle = false
	target_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(target_view)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	confirm = Button.new()
	Terminal.button(confirm, true)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.pressed.connect(_confirm)
	buttons.add_child(confirm)
	cancel = Button.new()
	Terminal.button(cancel)
	cancel.text = "[N] Cancel"
	cancel.tooltip_text = "Don't cast it."
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(_cancel)
	buttons.add_child(cancel)
	hide()

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", Terminal.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size.x = 300
	return label

## Shows the ask (or hides on {}). A new ask id starts fresh; a repeat keeps the highlighted row.
func present(value: Dictionary, ready: bool = true) -> void:
	if value.is_empty():
		ask = {}
		hide()
		return
	if int(value.get("id", -1)) != int(ask.get("id", -2)):
		focus = 0
		sent = false
		started = Time.get_ticks_msec()
		for child in rows.get_children(): child.queue_free()
		var options: Array = value.get("options", [])
		for i in range(options.size()):
			var row := Button.new()
			Terminal.button(row)
			row.icon = null
			row.focus_mode = Control.FOCUS_NONE
			row.custom_minimum_size.x = 300
			var data: Dictionary = options[i].card
			row.text = "%s  ·  %s" % [str(data.get("name", "Spell")).to_upper(), str(data.get("typeLine", "")).to_lower()]
			row.pressed.connect(_pick.bind(i))
			row.mouse_entered.connect(_pick.bind(i))
			rows.add_child(row)
		spell_card.update_card(value.sourceCard)
		title.text = "[ %s ]" % str(value.sourceCard.get("name", "Spell")).to_upper()
		question = "> " + str(value.get("message", "select target")).strip_edges().to_lower()
		_show_line()
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	ask = value
	rows.visible = ask.options.size() > 1
	cancel.visible = int(ask.get("min", 1)) == 0
	ready_now = ready
	_refresh()
	show()
	_layout()

func _pick(index: int) -> void:
	if sent or ask.is_empty(): return
	focus = clampi(index, 0, ask.options.size() - 1)
	_refresh()

func _refresh() -> void:
	var ready := ready_now
	var options: Array = ask.get("options", [])
	if options.is_empty(): return
	var target: Dictionary = options[focus].card
	target_view.update_card(target)
	for i in range(rows.get_child_count()):
		Terminal.button(rows.get_child(i), i == focus)
		rows.get_child(i).icon = null
	confirm.text = "[Y] %s → %s" % [str(ask.sourceCard.get("name", "Cast")).to_upper(), str(target.get("name", "target")).to_upper()]
	confirm.disabled = sent or not ready
	cancel.disabled = sent or not ready

func _confirm() -> void:
	if sent or confirm.disabled or ask.is_empty(): return
	sent = true
	_refresh()
	answered.emit(int(ask.id), [focus])

func _cancel() -> void:
	if sent or not cancel.visible or ask.is_empty(): return
	sent = true
	_refresh()
	answered.emit(int(ask.id), [])

func _show_line() -> void:
	line.text = question + ("_" if cursor_on else " ")

## The spell large on the left of the table, the menu beside it, both centered as a pair.
func _layout() -> void:
	if not visible: return
	var area: Rect2 = table_rect if table_rect.has_area() else Rect2(Vector2.ZERO, size)
	var height := clampf(area.size.y * 0.6, 260, 480)
	var card_size := Vector2(height * 144.0 / 202.0, height).round()
	spell_card.custom_minimum_size = card_size
	spell_card.size = card_size
	var target_height := clampf(area.size.y * 0.38, 200, 330)
	target_view.custom_minimum_size = Vector2(target_height * 144.0 / 202.0, target_height).round()
	box.reset_size()
	var total := card_size.x + GAP + box.size.x
	var left := area.get_center().x - total * 0.5
	spell_card.position = Vector2(left, area.get_center().y - card_size.y * 0.5).round()
	box.position = Vector2(left + card_size.x + GAP, clampf(area.get_center().y - box.size.y * 0.5, 8, maxf(8, size.y - box.size.y - 8))).round()

func _process(delta: float) -> void:
	if not visible: return
	blink += delta
	if blink >= 0.55:
		blink = 0.0
		cursor_on = not cursor_on
		_show_line()
	_layout()
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_Y, KEY_ENTER, KEY_KP_ENTER: _confirm()
		KEY_N: _cancel()
		KEY_UP: _pick(focus - 1)
		KEY_DOWN: _pick(focus + 1)
		_: return
	get_viewport().set_input_as_handled()

## Card A to its menu (purple, like the card callouts); the target card in the menu to its spell on
## the stack (orange, like the wipe branches), with a pulsing frame on that stack entry.
func _draw() -> void:
	if ask.is_empty(): return
	var to_local := get_global_transform().affine_inverse()
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	var card := Rect2(to_local * spell_card.global_position, spell_card.size)
	var menu := Rect2(box.position, box.size)
	var from := Vector2(card.end.x, card.get_center().y)
	var to := Vector2(menu.position.x, clampf(from.y, menu.position.y + 16, menu.end.y - 16))
	draw_line(from, to, Color(Terminal.ACCENT, 0.3), 9.0, true)
	draw_line(from, to, Terminal.ACCENT, 3.0, true)
	draw_circle(to, 5.0, Terminal.ACCENT)
	var frame := P.box(Color.TRANSPARENT, Color(Terminal.ACCENT, pulse), 9, 0)
	frame.set_border_width_all(3)
	draw_style_box(frame, card.grow(5))
	if not stack_rect.is_valid(): return
	var entry: Rect2 = stack_rect.call(int(ask.options[focus].get("stackId", -1)))
	if not entry.has_area(): return
	entry = Rect2(to_local * entry.position, entry.size)
	var target := Rect2(to_local * target_view.global_position, target_view.size)
	var start := Vector2(target.end.x, target.get_center().y)
	var finish := Vector2(entry.position.x, entry.get_center().y)
	var bend := start.lerp(finish, 0.5) + Vector2(0, -0.15 * start.distance_to(finish))
	var grow := clampf((Time.get_ticks_msec() - started) / 450.0, 0.0, 1.0)
	var points := PackedVector2Array()
	for i in range(int(24 * grow) + 1):
		var t := i / 24.0
		points.append(start.lerp(bend, t).lerp(bend.lerp(finish, t), t))
	if points.size() >= 2:
		draw_polyline(points, Color(TARGET_LINE, 0.28), 12.0, true)
		draw_polyline(points, TARGET_LINE, 3.5, true)
	if grow >= 1.0:
		var hit := P.box(Color(TARGET_LINE, 0.08 * pulse), Color(TARGET_LINE, 0.4 + 0.6 * pulse), 6, 0)
		hit.set_border_width_all(3)
		draw_style_box(hit, entry.grow(3))
