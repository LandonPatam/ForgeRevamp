extends PanelContainer
## A yes/no Forge confirmation attached to the card it asks about ("Sacrifice Evolving Wilds?"):
## a small terminal box beside the card, joined to it by a leader line drawn by InteractionPanel.
## It also lists a card's modes ("choose one or more —"): number keys or clicks toggle them and
## Confirm sends every picked mode as one answer.
signal answered(action: String)
signal modes_answered(id: int, picks: Array)
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const BLINK_SECONDS := 0.55
var title: Label
var line: Label
var yes_button: Button
var no_button: Button
var question := ""
var cursor_on := true
var blink := 0.0
var mode_list: VBoxContainer
var mode_buttons: Array[Button] = []
var mode_ask: Dictionary = {}
var mode_picks: Array = []
var mode_sent := false
var mode_ready := false

func _ready() -> void:
	Terminal.panel(self, 12)
	var frame := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	frame.border_color = Terminal.ACCENT
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 8
	add_theme_stylebox_override("panel", frame)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	title = _label(12, Terminal.MUTED)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	line = _label(16, Terminal.INK)
	column.add_child(line)
	mode_list = VBoxContainer.new()
	mode_list.add_theme_constant_override("separation", 6)
	mode_list.hide()
	column.add_child(mode_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	yes_button = _button(func():
		if mode_ask.is_empty(): answered.emit("ok")
		else: _send_modes())
	Terminal.button(yes_button, true)
	row.add_child(yes_button)
	no_button = _button(func(): answered.emit("cancel"))
	row.add_child(no_button)
	hide()

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_font_override("font", Terminal.font())
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size.x = 250
	return label

func _button(callback: Callable) -> Button:
	var button := Button.new()
	Terminal.button(button)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button

## `card_name` labels the box; labels come from Forge's own Yes/No (or custom) button text.
func present(card_name: String, message: String, ok_label: String, cancel_label: String, ok_enabled: bool, cancel_enabled: bool) -> void:
	mode_ask = {}
	mode_list.hide()
	line.custom_minimum_size.x = 250
	title.text = "[ %s ]" % card_name.to_upper()
	question = "> " + message.strip_edges().to_lower()
	_show_line()
	yes_button.text = "[Y] " + ok_label
	no_button.text = "[N] " + cancel_label
	yes_button.disabled = not ok_enabled
	no_button.disabled = not cancel_enabled
	no_button.visible = cancel_enabled or not cancel_label.is_empty()

func _show_line() -> void:
	line.text = question + ("_" if cursor_on else " ")

func _process(delta: float) -> void:
	if not visible: return
	blink += delta
	if blink >= BLINK_SECONDS:
		blink = 0.0
		cursor_on = not cursor_on
		_show_line()

## A card's modes as toggles. Picks stay local until Confirm; a new ask id starts fresh.
func present_modes(card_name: String, ask: Dictionary, ready: bool) -> void:
	if int(ask.get("id", -1)) != int(mode_ask.get("id", -2)):
		mode_picks = []
		mode_sent = false
		for button in mode_buttons: button.queue_free()
		mode_buttons.clear()
		var options: Array = ask.get("options", [])
		for i in range(options.size()):
			var button := _button(_toggle_mode.bind(i))
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size.x = 400
			button.set_meta("text", preload("res://scripts/ui/OrderStack.gd").ability_text(options[i]))
			mode_list.add_child(button)
			mode_buttons.append(button)
	mode_ask = ask
	mode_list.show()
	line.custom_minimum_size.x = 400
	title.text = "[ %s ]" % card_name.to_upper()
	var low := int(ask.get("min", 1))
	var high := int(ask.get("max", 1))
	question = "> choose " + ("one" if high == 1 else ("one or more" if low <= 1 and high >= mode_buttons.size() else ("%d" % high if low == high else "%d to %d" % [low, high]))) + (" mode" if high == 1 else " modes")
	_show_line()
	no_button.visible = false
	mode_ready = ready
	_refresh_modes()

func _toggle_mode(index: int) -> void:
	if mode_sent or mode_ask.is_empty() or index >= mode_buttons.size(): return
	if mode_picks.has(index): mode_picks.erase(index)
	elif int(mode_ask.get("max", 1)) == 1: mode_picks = [index]
	elif mode_picks.size() < int(mode_ask.get("max", 1)): mode_picks.append(index)
	_refresh_modes()

func _picks_valid() -> bool:
	return mode_picks.size() >= maxi(1, int(mode_ask.get("min", 1))) and mode_picks.size() <= int(mode_ask.get("max", 1))

func _refresh_modes() -> void:
	var ready := mode_ready
	for i in range(mode_buttons.size()):
		var picked := mode_picks.has(i)
		mode_buttons[i].text = "%d [%s] %s" % [i + 1, "x" if picked else " ", mode_buttons[i].get_meta("text")]
		Terminal.button(mode_buttons[i], picked)
		mode_buttons[i].icon = null
		mode_buttons[i].disabled = mode_sent or not ready
	var count := mode_picks.size()
	yes_button.text = "[Y] Confirm" + ("" if int(mode_ask.get("max", 1)) == 1 else " %d" % count)
	yes_button.disabled = mode_sent or not ready or not _picks_valid()

func _send_modes() -> void:
	if mode_sent or not _picks_valid(): return
	mode_sent = true
	var picks: Array = mode_picks.duplicate()
	picks.sort()
	_refresh_modes()
	modes_answered.emit(int(mode_ask.id), picks)
