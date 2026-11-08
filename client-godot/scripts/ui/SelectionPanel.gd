extends PanelContainer
## Forge's synchronous card input as a terminal search: a list that stacks identical cards
## (FOREST ×3) beside a large preview of the highlighted one. Every click still goes straight to
## the active input with one exact instance, and option_buttons keeps one button per instance.
signal selected_card(id: int)
signal entity_selected(action: String, id: int)
signal board_requested
signal action_requested(action: String)
const P = preload("res://scripts/ui/Palette.gd")
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const Card = preload("res://scripts/ui/CardView.gd")
const PREVIEW_SIZE := Vector2(288, 404) # Exactly twice a 144×202 card.
const SOURCE_SIZE := Vector2(120, 168)
const LIST_WIDTH := 360.0
var title: Label
var command: Label
var hint: Label
var keys: Label
var preview: Control
var preview_portrait: Control
var preview_caption: Label
var confirm_button: Button
var none_button: Button
var cancel_button: Button
var board_button: Button
var options: Array = []
var option_buttons: Array[Button] = []
## Visible list rows; each holds the option indexes of identical instances.
var rows: Array[Button] = []
var groups: Array = []
var highlighted := 0
var last_ready := true
var chosen_refs: Array = []
var players: Array = []
var source_view: Control
var source_context: HBoxContainer
var source_rules: Control
var source_name: Label
var body: HBoxContainer
var source_column: VBoxContainer
var list_box: VBoxContainer
var instance_box: Control
var list_scroll: ScrollContainer

func _ready() -> void:
	Terminal.panel(self, 18)
	var frame := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	frame.border_color = Terminal.EDGE.lightened(0.25)
	add_theme_stylebox_override("panel", frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	command = _label(18, Terminal.INK)
	command.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	command.custom_minimum_size.x = LIST_WIDTH + PREVIEW_SIZE.x + 40
	column.add_child(command)
	title = _label(12, Terminal.MUTED) # Forge's full prompt text (kept for context and checks).
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = command.custom_minimum_size.x
	title.max_lines_visible = 2
	column.add_child(title)
	column.add_child(HSeparator.new())
	body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	column.add_child(body)
	# Left: results list, then the source card that asked.
	source_column = VBoxContainer.new()
	source_column.add_theme_constant_override("separation", 10)
	source_column.custom_minimum_size.x = LIST_WIDTH
	body.add_child(source_column)
	var results := _label(12, Terminal.MUTED)
	results.name = "ResultsCaption"
	source_column.add_child(results)
	list_scroll = ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.custom_minimum_size = Vector2(LIST_WIDTH, 230)
	source_column.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 3)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list_box)
	instance_box = Control.new() # One hidden button per instance; rows forward to them.
	instance_box.hide()
	source_column.add_child(instance_box)
	source_context = HBoxContainer.new()
	source_context.add_theme_constant_override("separation", 12)
	source_column.add_child(source_context)
	source_view = Card.new()
	source_view.inspection = true
	source_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_view.custom_minimum_size = SOURCE_SIZE
	source_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	source_context.add_child(source_view)
	var source_text := VBoxContainer.new()
	source_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_context.add_child(source_text)
	source_text.add_child(_label(12, Terminal.MUTED, "SOURCE"))
	source_name = _label(15, Terminal.INK)
	source_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source_text.add_child(source_name)
	source_rules = preload("res://scripts/ui/ReadableText.gd").new()
	source_text.add_child(source_rules)
	source_rules.hide()
	source_context.hide()
	# Right: the highlighted card, large.
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 8)
	body.add_child(preview_column)
	preview_column.add_child(_label(12, Terminal.MUTED, "PREVIEW"))
	preview = Card.new()
	preview.inspection = true
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.custom_minimum_size = PREVIEW_SIZE
	preview_column.add_child(preview)
	preview_portrait = preload("res://scripts/ui/PlayerAvatar.gd").new()
	preview_portrait.custom_minimum_size = Vector2(PREVIEW_SIZE.x, 200)
	preview_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_portrait.hide()
	preview_column.add_child(preview_portrait)
	preview_caption = _label(14, Terminal.INK)
	preview_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_caption.custom_minimum_size.x = PREVIEW_SIZE.x
	preview_caption.max_lines_visible = 3
	preview_column.add_child(preview_caption)
	column.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	var status := VBoxContainer.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(status)
	hint = _label(14, Terminal.INK)
	status.add_child(hint)
	keys = _label(12, Terminal.MUTED, "↑↓ move   ENTER pick")
	status.add_child(keys)
	none_button = _button("Choose none", func(): action_requested.emit(none_button.get_meta("action", "ok")))
	footer.add_child(none_button)
	cancel_button = _button("Cancel", func(): action_requested.emit("cancel"))
	footer.add_child(cancel_button)
	board_button = _button("View battlefield", func(): board_requested.emit())
	footer.add_child(board_button)
	confirm_button = _button("Confirm selection", func(): action_requested.emit("ok"))
	Terminal.button(confirm_button, true)
	footer.add_child(confirm_button)

func _label(font_size: int, color: Color, text: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_font_override("font", Terminal.font())
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	Terminal.button(button)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button

## "Evolving Wilds (70)\n - {T}, ...\nSelect a card from your library" → C:\EVOLVING_WILDS> select a card…
func _command_line(message: String, source: Dictionary) -> String:
	var lines := message.strip_edges().split("\n", false)
	var ask := str(lines[lines.size() - 1]).strip_edges() if not lines.is_empty() else "choose"
	var where := str(source.get("name", "FORGE")).to_upper().replace(" ", "_").replace(",", "").replace("'", "")
	return "C:\\%s> %s_" % [where, ask.to_lower()]

func _group_key(option: Dictionary) -> String:
	if option.kind != "card" or option.get("hidden", false) or option.get("faceDown", false): return "single:" + str(option.ref)
	return "%s|%s|%s" % [option.get("name", ""), option.get("typeLine", ""), option.get("eligible", true)]

func present(snapshot: Dictionary) -> void:
	var prompt: Dictionary = snapshot.prompt
	var ready: bool = snapshot.get("connectionReady", false)
	last_ready = ready
	players = snapshot.get("players", [])
	title.text = prompt.get("message", "Choose cards")
	var source: Dictionary = prompt.get("sourceCard", {})
	command.text = _command_line(title.text, source)
	source_context.visible = not source.is_empty()
	if source_context.visible:
		source_view.update_card(source)
		source_name.text = str(source.get("name", "Hidden card"))
		source_rules.hide()
	var cards: Array = prompt.get("cards", []).duplicate(true)
	for card in cards:
		card.kind = "card"
		card.eligible = true
		card.ref = "card:" + str(int(card.id))
	for revealed_card in prompt.get("revealedCards", []):
		if cards.any(func(card): return int(card.id) == int(revealed_card.id)): continue
		var viewed_card: Dictionary = revealed_card.duplicate(true)
		viewed_card.kind = "card"
		viewed_card.ref = "card:" + str(int(viewed_card.id))
		viewed_card.eligible = false
		cards.append(viewed_card)
	for entity in prompt.get("entities", []):
		var entry: Dictionary = entity.duplicate(true)
		entry.ref = str(entry.kind) + ":" + str(int(entry.get("engineId", entry.id)))
		if entry.kind == "stack": entry.name = entry.get("sourceName", entry.get("card", {}).get("name", "Spell or ability"))
		cards.append(entry)
	if cards != options: _rebuild(cards)
	var refs: Array = options.map(func(option): return str(option.ref))
	chosen_refs = prompt.get("chosen", []).filter(func(ref): return refs.has(str(ref)))
	for i in range(options.size()):
		option_buttons[i].disabled = not ready or not options[i].get("eligible", true)
		option_buttons[i].text = ("✓ " if chosen_refs.has(str(options[i].ref)) else "") + str(options[i].get("name", "Face-down card"))
	for r in range(rows.size()): _paint_row(r, ready)
	(source_column.get_node("ResultsCaption") as Label).text = "RESULTS (%d)" % options.size()
	hint.text = "%d selected" % chosen_refs.size() if prompt.get("inputKind", "") == "InputSelectStackItems" else "%d selected / %d–%d required" % [chosen_refs.size(), prompt.get("selMin", 0), prompt.get("selMax", 0)]
	confirm_button.disabled = not ready or not prompt.get("okEnabled", false) or chosen_refs.is_empty()
	# Forge represents an optional 1-card effect as Cancel rather than a 0 minimum.
	var decline: bool = prompt.get("inputKind", "") in ["InputSelectCardsFromList", "InputSelectEntitiesFromList"] and prompt.get("cancelEnabled", false) and not prompt.has("selectionShortcut")
	none_button.set_meta("action", "cancel" if decline else "ok")
	none_button.visible = int(prompt.get("selMin", 0)) == 0 or decline
	none_button.disabled = not ready or (not decline and not prompt.get("okEnabled", false)) or not chosen_refs.is_empty()
	cancel_button.text = prompt.get("cancelLabel", "Cancel")
	match prompt.get("selectionShortcut", ""):
		"MINE": cancel_button.text = "Select my permanents"
		"ALL": cancel_button.text = "Select all eligible"
		"NONE": cancel_button.text = "Clear selection"
	cancel_button.tooltip_text = "Change the selection, then review it before confirming." if prompt.has("selectionShortcut") else ""
	cancel_button.visible = prompt.get("cancelEnabled", false) and not decline
	cancel_button.disabled = not ready
	board_button.text = "Choose on board" if prompt.get("inputKind", "") == "InputSelectTargets" else "View battlefield"
	board_button.visible = true
	board_button.disabled = not ready
	keys.text = "↑↓ move   ENTER pick" + ("   ×N rows: click again for another copy" if groups.any(func(group): return group.size() > 1) else "")

func _rebuild(cards: Array) -> void:
	options = cards.duplicate(true)
	for child in list_box.get_children() + instance_box.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	option_buttons.clear()
	rows.clear()
	groups.clear()
	var by_key: Dictionary = {}
	for i in range(options.size()):
		var option: Dictionary = options[i]
		var instance := Button.new()
		instance.text = str(option.get("name", "Face-down card"))
		instance.pressed.connect(func():
			if option.kind == "card": selected_card.emit(int(option.id))
			else: entity_selected.emit(str(option.kind), int(option.id)))
		instance_box.add_child(instance)
		option_buttons.append(instance)
		var key := _group_key(option)
		if not by_key.has(key):
			by_key[key] = groups.size()
			groups.append([])
		groups[by_key[key]].append(i)
	for g in range(groups.size()):
		var row := Button.new()
		Terminal.button(row)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.clip_text = true
		row.custom_minimum_size = Vector2(LIST_WIDTH - 14, 34)
		row.add_theme_font_size_override("font_size", 15)
		row.pressed.connect(_pick_row.bind(g))
		row.mouse_entered.connect(func(): _highlight(g))
		list_box.add_child(row)
		rows.append(row)
	highlighted = clampi(highlighted, 0, maxi(0, rows.size() - 1))
	if not rows.is_empty(): _highlight(highlighted if highlighted < rows.size() else 0)

func _paint_row(r: int, ready: bool) -> void:
	var group: Array = groups[r]
	var first: Dictionary = options[group[0]]
	var picked := group.filter(func(i): return chosen_refs.has(str(options[i].ref))).size()
	var name := str(first.get("name", "Face-down card"))
	if not first.get("eligible", true): name = "viewed · " + name
	var count := ("×%d" % group.size()) if group.size() > 1 else ""
	var mark := ("[%d✓] " % picked if group.size() > 1 else "[✓] ") if picked > 0 else ""
	rows[r].text = "%s%s  %s" % [mark, name.to_upper(), count]
	rows[r].disabled = not ready or not first.get("eligible", true)
	var selected := picked > 0
	var box := P.box(Color("1b2032") if selected else (Color("0f2a2e") if r == highlighted else Color("07181b")), Terminal.ACCENT if selected else (Terminal.EDGE.lightened(0.3) if r == highlighted else Terminal.EDGE), 3, 0)
	box.set_content_margin_all(6)
	box.content_margin_left = 10
	for style in ["normal", "hover", "pressed", "disabled", "focus"]: rows[r].add_theme_stylebox_override(style, box)
	rows[r].add_theme_color_override("font_color", Terminal.ACCENT if selected else Terminal.INK)
	rows[r].add_theme_color_override("font_hover_color", Color.WHITE)

## A stacked row picks the next unpicked copy; once every copy is picked it unpicks one.
func _pick_row(r: int) -> void:
	_highlight(r)
	var group: Array = groups[r]
	var unpicked: Array = group.filter(func(i): return not chosen_refs.has(str(options[i].ref)))
	var index: int = unpicked[0] if not unpicked.is_empty() else group[group.size() - 1]
	if option_buttons[index].disabled: return
	option_buttons[index].pressed.emit()

func _highlight(r: int) -> void:
	if r < 0 or r >= rows.size(): return
	var previous := highlighted
	highlighted = r
	var option: Dictionary = options[groups[r][0]]
	var is_player: bool = option.get("kind", "") == "player"
	preview.visible = not is_player
	preview_portrait.visible = is_player
	if is_player:
		var id := int(option.get("id", -1))
		if id >= 0 and id < players.size(): preview_portrait.set_player(players[id], false)
		preview_caption.text = str(option.get("name", "Player"))
	else:
		var data: Dictionary = option.get("card", option)
		preview.update_card(data if not data.get("hidden", false) else {"id": -1, "hidden": true})
		preview_caption.text = str(option.get("text", "")) if option.get("kind", "") == "stack" else str(data.get("typeLine", ""))
	if previous != r and previous < rows.size(): _paint_row(previous, last_ready)
	_paint_row(r, last_ready)
	list_scroll.ensure_control_visible(rows[r])

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or rows.is_empty() or not event is InputEventKey or not event.pressed: return
	match event.keycode:
		KEY_DOWN: _highlight(mini(highlighted + 1, rows.size() - 1))
		KEY_UP: _highlight(maxi(highlighted - 1, 0))
		KEY_ENTER, KEY_KP_ENTER: if not rows[highlighted].disabled: _pick_row(highlighted)
		_: return
	get_viewport().set_input_as_handled()
