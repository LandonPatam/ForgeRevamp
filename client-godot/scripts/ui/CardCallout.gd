extends PanelContainer
## A TETHER: the project's name for a decision box tied to its card by a leader line, instead of a
## popup. A yes/no Forge confirmation attached to the card it asks about ("Sacrifice Evolving Wilds?"):
## a small terminal box beside the card, joined to it by a leader line drawn by InteractionPanel.
## It also lists a card's modes ("choose one or more —"): number keys or clicks toggle them and
## Confirm sends every picked mode as one answer.
signal answered(action: String)
signal modes_answered(id: int, picks: Array)
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const ManaOption = preload("res://scripts/ui/ManaOption.gd")
const BLINK_SECONDS := 0.55
var title: Label
var line: Label
var yes_button: Button
var no_button: Button
var question := ""
var cursor_on := true
var blink := 0.0
## The card itself, shown in the box when the tether hangs off a zone icon (its card isn't on the table).
var face: Control
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
	var face_center := CenterContainer.new()
	column.add_child(face_center)
	face = preload("res://scripts/ui/CardView.gd").new()
	face.inspection = true
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.custom_minimum_size = Vector2(230, 322)
	face_center.add_child(face)
	face.hide()
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
	no_button = _button(func():
		if mode_ask.is_empty(): answered.emit("cancel")
		elif not mode_sent:
			mode_sent = true
			_refresh_modes()
			modes_answered.emit(int(mode_ask.id), []))
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
func present(card_name: String, message: String, ok_label: String, cancel_label: String, ok_enabled: bool, cancel_enabled: bool, card: Dictionary = {}) -> void:
	face.visible = not card.is_empty()
	if face.visible: face.update_card(card)
	# With the card shown large, its name above it would only repeat it.
	title.visible = not face.visible
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
	face.hide()
	title.show()
	if int(ask.get("id", -1)) != int(mode_ask.get("id", -2)):
		mode_picks = []
		mode_sent = false
		for child in mode_list.get_children(): child.queue_free()
		mode_buttons.clear()
		var options: Array = ask.get("options", [])
		if _mana_tiles(ask):
			# Plain "add one color" choices: a row of mana symbols, one click each.
			var tiles := HBoxContainer.new()
			tiles.alignment = BoxContainer.ALIGNMENT_CENTER
			tiles.add_theme_constant_override("separation", 12)
			mode_list.add_child(tiles)
			for i in range(options.size()):
				var tile := ManaOption.new()
				tile.choice_tile = true
				tile.colors = ManaOption.colors_for(str(options[i].get("label", "")))
				tile.focus_mode = Control.FOCUS_NONE
				tile.tooltip_text = "%d  ·  %s" % [i + 1, str(options[i].get("label", ""))]
				tile.pressed.connect(_toggle_mode.bind(i))
				tiles.add_child(tile)
				tile.custom_minimum_size = Vector2(76, 76)
				mode_buttons.append(tile)
		for i in range(options.size() if mode_buttons.is_empty() else 0):
			var button := _button(_toggle_mode.bind(i))
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.custom_minimum_size.x = 400
			button.set_meta("text", preload("res://scripts/ui/OrderStack.gd").ability_text(options[i]))
			mode_list.add_child(button)
			mode_buttons.append(button)
	mode_ask = ask
	mode_list.show()
	line.custom_minimum_size.x = 250 if mode_buttons.any(func(button): return button is ManaOption) else 400
	title.text = "[ %s ]" % card_name.to_upper()
	var low := int(ask.get("min", 1))
	var high := int(ask.get("max", 1))
	question = "> choose " + ("one" if high == 1 else ("one or more" if low <= 1 and high >= mode_buttons.size() else ("%d" % high if low == high else "%d to %d" % [low, high]))) + (" mode" if high == 1 else " modes")
	if _instant(): question = "> choose mana to add" if ask.get("manaChoice", false) else "> choose ability"
	_show_line()
	# Abilities and mana act on click, like Forge's own menu; [N] backs out when Forge allows it.
	yes_button.visible = not _instant()
	no_button.text = "[N] Cancel"
	no_button.visible = low == 0
	mode_ready = ready
	_refresh_modes()

## Mana symbols instead of text when every option just adds one color, with no other cost or effect
## (a pain land's damage keeps the text rows, so that is never hidden).
static func _mana_tiles(ask: Dictionary) -> bool:
	if not ask.get("manaChoice", false) or int(ask.get("max", 1)) != 1: return false
	for option in ask.get("options", []):
		var details := ManaOption.choice_details(str(option.get("label", "")))
		if details.is_empty() or details.colors.size() != 1 or not str(details.cost).is_empty() or not str(details.extra).is_empty(): return false
	return true

## Ability and mana choices answer on click; card modes toggle and wait for Confirm.
func _instant() -> bool:
	return mode_ask.get("abilityChoice", false) and int(mode_ask.get("max", 1)) == 1

func _toggle_mode(index: int) -> void:
	if mode_sent or mode_ask.is_empty() or index >= mode_buttons.size(): return
	if _instant():
		if not mode_ready: return
		mode_picks = [index]
		_send_modes()
		return
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
		if mode_buttons[i] is ManaOption:
			mode_buttons[i].disabled = mode_sent or not ready
			continue
		mode_buttons[i].text = ("%d  %s" % [i + 1, mode_buttons[i].get_meta("text")]) if _instant() else "%d [%s] %s" % [i + 1, "x" if picked else " ", mode_buttons[i].get_meta("text")]
		Terminal.button(mode_buttons[i], picked)
		mode_buttons[i].icon = null
		mode_buttons[i].disabled = mode_sent or not ready
	var count := mode_picks.size()
	yes_button.text = "[Y] Confirm" + ("" if int(mode_ask.get("max", 1)) == 1 else " %d" % count)
	yes_button.disabled = mode_sent or not ready or not _picks_valid()
	no_button.disabled = mode_sent or not ready

func _send_modes() -> void:
	if mode_sent or not _picks_valid(): return
	mode_sent = true
	var picks: Array = mode_picks.duplicate()
	picks.sort()
	_refresh_modes()
	modes_answered.emit(int(mode_ask.id), picks)
