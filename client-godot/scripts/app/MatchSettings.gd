extends Control
signal saved(value: Dictionary)
signal canceled
const Preferences = preload("res://scripts/app/MatchPreferences.gd")
const Portraits = preload("res://scripts/ui/Portraits.gd")
const P = preload("res://scripts/ui/Palette.gd")
var value: Dictionary
var decks: Array = []
var selected_deck := ""
var grid: GridContainer
var error_label: Label
var add_button: Button
var save_button: Button
var names: Array[LineEdit] = []
var deck_choices: Array[OptionButton] = []
var portrait_buttons: Array[Button] = []
var remove_buttons: Array[Button] = []
var portrait_dialog: AcceptDialog
var avatar_choices: Array[Button] = []
var file_picker: FileDialog
var editing_profile: Dictionary
var editing_button: Button
var api: Node
var deck_catalog: Dictionary = {}
var catalog_request := -1
var catalog_error := ""
var deck_pick_buttons: Array[Button] = []
var deck_browser: AcceptDialog
var deck_search: LineEdit
var deck_list: ItemList
var browser_entries: Array = []
var browser_profile: Dictionary
var browser_index := -1
const INK := Color("65e0d5")
const DIM := Color("4b9898")
const DARK := Color("031013")
var roster: PanelContainer
var roster_scroll: ScrollContainer
var page_scroll: ScrollContainer
var roster_header: HBoxContainer
var rows: Array[PanelContainer] = []
var name_heading: Label
var heading: Label
var terminal_status: Label
var clock_label: Label
var shortcut_hint: Label
var selected_row := 0
var blink_time := 0.0
var row_name_width := 240.0
var net: Node
var game_running := false
var online_body: VBoxContainer
var server_field: LineEdit
var host_button: Button
var join_button: Button
var kick_buttons: Array[Button] = []
var net_signature := ""
var display_scale_choice: float = preload("res://scripts/app/DisplayPreferences.gd").read()
var display_scale_picker: OptionButton

func _ready() -> void:
	get_window().gui_embed_subwindows = true
	theme = preload("res://scripts/ui/TerminalStyle.gd").theme()
	theme.default_font_size = 17
	for kind in ["Label", "Button", "LineEdit", "OptionButton"]:
		theme.set_color("font_color", kind, INK)
	var underline := P.box(Color.TRANSPARENT, DIM, 0, 3)
	underline.set_border_width_all(0)
	underline.border_width_bottom = 1
	theme.set_stylebox("normal", "LineEdit", underline)
	var focused := underline.duplicate() as StyleBoxFlat
	focused.border_color = INK
	focused.border_width_bottom = 2
	theme.set_stylebox("focus", "LineEdit", focused)
	theme.set_color("caret_color", "LineEdit", INK)
	for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := Color("163c40") if kind in ["hover", "pressed"] else Color.TRANSPARENT
		theme.set_stylebox(kind, "Button", P.box(fill, DIM if kind in ["hover", "focus"] else Color.TRANSPARENT, 0, 8))
		theme.set_stylebox(kind, "OptionButton", P.box(fill, DIM if kind in ["hover", "focus"] else Color.TRANSPARENT, 0, 4))
		theme.set_color("font_" + kind + "_color", "Button", INK)
		theme.set_color("font_" + kind + "_color", "OptionButton", INK)
	theme.set_color("font_disabled_color", "Button", Color("295155"))
	theme.set_constant("outline_size", "Label", 0)
	var background := ColorRect.new()
	background.color = DARK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.name = "TerminalMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	page_scroll = ScrollContainer.new()
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(page_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	page_scroll.add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var system := _text(" FORGE/OS ", 15)
	system.add_theme_color_override("font_color", DARK)
	system.add_theme_stylebox_override("normal", P.box(INK, Color.TRANSPARENT, 0, 2))
	bar.add_child(system)
	var location := _text("COMMANDER.EXE  -  /MATCH/CONFIG", 15, DIM)
	location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(location)
	clock_label = _text("TTY01  |  " + Time.get_time_string_from_system(), 15, DIM)
	bar.add_child(clock_label)
	column.add_child(HSeparator.new())
	heading = _text("> MATCH_SETTINGS", 46)
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono"])
	title_font.font_weight = 700
	heading.add_theme_font_override("font", title_font)
	column.add_child(heading)
	column.add_child(_text("C:\\COMMANDER> configure players, portraits and decks for next match_", 16, DIM))
	roster = preload("res://scripts/app/MatchRoster.gd").new()
	roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(roster)
	var roster_body := VBoxContainer.new()
	roster_body.add_theme_constant_override("separation", 8)
	roster.add_child(roster_body)
	roster_header = HBoxContainer.new()
	roster_header.add_theme_constant_override("separation", 14)
	roster_body.add_child(roster_header)
	for title in ["SLOT", "PORTRAIT", "CALLSIGN", "DECK", "CMD"]:
		var label := _text(title, 13, DIM)
		if title == "DECK": label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if title == "CALLSIGN": name_heading = label
		roster_header.add_child(label)
	roster_scroll = ScrollContainer.new()
	roster_scroll.custom_minimum_size.y = 180
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_body.add_child(roster_scroll)
	grid = GridContainer.new()
	grid.columns = 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("v_separation", 0)
	roster_scroll.add_child(grid)
	error_label = _text("", 14, DIM)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(error_label)
	terminal_status = _text("> SYS: deck pool indexing ...", 13, DIM)
	column.add_child(terminal_status)
	column.add_child(HSeparator.new())
	online_body = VBoxContainer.new()
	online_body.name = "OnlineSection"
	online_body.add_theme_constant_override("separation", 4)
	column.add_child(online_body)
	column.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	var display_row := HBoxContainer.new()
	display_row.add_child(_text("UI SIZE", 15))
	display_scale_picker = OptionButton.new()
	var display_choices := [0.0, 1.0, 1.25, 1.5, 1.75, 2.0]
	for choice in display_choices:
		display_scale_picker.add_item("Automatic (200% on Mac, 100% on Windows)" if choice == 0 else "%d%%" % roundi(choice * 100))
		if is_equal_approx(choice, display_scale_choice): display_scale_picker.select(display_scale_picker.item_count - 1)
	display_scale_picker.item_selected.connect(func(index): display_scale_choice = display_choices[index])
	display_row.add_child(display_scale_picker)
	column.add_child(display_row)
	column.add_child(_text("Saved for this device. Applies after Save & Return.", 13, DIM))
	column.add_child(footer)
	shortcut_hint = _text("[UP/DN] SELECT  [F2] ADD  [DEL] REMOVE  [TAB] NAME", 12, DIM)
	shortcut_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(shortcut_hint)
	footer.add_child(_button("[ESC] CANCEL", func(): canceled.emit()))
	save_button = _button("[F10] SAVE & RETURN", func(): if _valid(): saved.emit(value.duplicate(true)))
	footer.add_child(save_button)
	var scan := ColorRect.new()
	scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var finish := ShaderMaterial.new()
	finish.shader = preload("res://shaders/match_scanlines.gdshader")
	scan.material = finish
	add_child(scan)
	resized.connect(_layout)
	if net != null: net.changed.connect(_net_changed)
	_render()
	_render_online()
	if api != null:
		api.response.connect(_catalog_response)
		api.failed.connect(_catalog_failed)
		if not deck_catalog.has("precon") or not deck_catalog.has("commander"):
			catalog_request = api.request("bot.decks")

func _text(text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.pressed.connect(action)
	return button

func _process(delta: float) -> void:
	blink_time += delta
	if blink_time >= 0.5:
		blink_time = 0.0
		clock_label.text = "TTY01  |  " + Time.get_time_string_from_system()

func _layout() -> void:
	if grid == null: return
	var compact := size.x < 1400
	row_name_width = clampf((size.x - 100) * 0.25, 180, 400)
	heading.add_theme_font_size_override("font_size", 40 if compact else 52)
	roster_header.get_child(0).custom_minimum_size.x = 66
	roster_header.get_child(1).custom_minimum_size.x = 84
	name_heading.custom_minimum_size.x = row_name_width
	roster_header.get_child(4).custom_minimum_size.x = 122
	for field in names: field.custom_minimum_size.x = row_name_width
	for portrait in portrait_buttons: portrait.custom_minimum_size = Vector2(84, 72 if compact else 84)
	for row in rows: row.custom_minimum_size.y = 90 if compact else 106
	# Online sections take height from the roster; compact rows keep four seats in view.
	if _hosting() or _joined():
		for portrait in portrait_buttons: portrait.custom_minimum_size = Vector2(84, 72)
		for row in rows: row.custom_minimum_size.y = 90
	if is_instance_valid(add_button): add_button.custom_minimum_size.x = row_name_width
	shortcut_hint.text = "[F2] ADD  [DEL] REMOVE  [TAB] NAME" if compact else "[UP/DN] SELECT  [LEFT/RIGHT] DECK  [F2] ADD  [DEL] REMOVE  [TAB] NAME"

func _render() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	names.clear()
	deck_choices.clear()
	deck_pick_buttons.clear()
	portrait_buttons.clear()
	remove_buttons.clear()
	kick_buttons.clear()
	rows.clear()
	if _joined():
		_render_joined_roster()
		return
	_player(value.human, -1)
	for index in range(value.bots.size()): _player(value.bots[index], index)
	var joined_players := _net_players()
	for index in range(joined_players.size()): _net_row(joined_players[index], value.bots.size() + index + 2)
	var seated: int = value.bots.size() + joined_players.size()
	if seated < 3:
		_empty_slot(seated + 2, true)
		# A host's every free seat is open to players, so show each of them.
		if _hosting():
			for extra in range(seated + 1, 3): _empty_slot(extra + 2, false)
	else:
		add_button = _button("[ + ] ADD BOT", func(): _add_bot())
		add_button.disabled = true
		grid.add_child(add_button)
		add_button.hide()
	roster.caption = "[ ROSTER // %d OF 4 SLOTS ]" % (seated + 1)
	roster.queue_redraw()
	if _hosting(): net.configure(value)
	_select_row(selected_row)
	_layout()
	_valid()

func _player(profile: Dictionary, index: int) -> void:
	var panel := _roster_row(index + 1)
	var row := panel.get_child(0) as HBoxContainer
	var slot := VBoxContainer.new()
	slot.custom_minimum_size.x = 66
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(_text("[%02d]" % (index + 2), 20))
	slot.add_child(_text("YOU" if index < 0 else "BOT", 13, DIM))
	row.add_child(slot)
	var portrait := _button("", func(): _choose_portrait(profile, portrait_buttons[0 if index < 0 else index + 1]))
	portrait.icon = Portraits.texture(profile)
	portrait.expand_icon = true
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.tooltip_text = "Change profile picture"
	var phosphor := ShaderMaterial.new()
	phosphor.shader = preload("res://shaders/match_portrait.gdshader")
	portrait.material = phosphor
	portrait_buttons.append(portrait)
	row.add_child(portrait)
	var name := LineEdit.new()
	name.text = profile.get("name", "")
	name.max_length = 32
	name.placeholder_text = "Player name"
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name.add_theme_font_size_override("font_size", 21)
	name.text_changed.connect(func(text): profile.name = text; _valid())
	name.focus_entered.connect(func(): _select_row(index + 1))
	names.append(name)
	row.add_child(name)
	var deck_column := VBoxContainer.new()
	deck_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	deck_column.add_theme_constant_override("separation", 2)
	row.add_child(deck_column)
	if index >= 0:
		var choice := OptionButton.new()
		choice.add_item("Same as your selected deck")
		choice.set_item_metadata(0, {"mode": "saved", "deckId": ""})
		choice.add_item("Random — Forge generated Commander deck")
		choice.set_item_metadata(1, {"mode": "generated", "deckId": ""})
		choice.add_item("Random — Forge Commander precon")
		choice.set_item_metadata(2, {"mode": "randomPrecon", "deckId": ""})
		for deck in decks:
			# Bundled precons are offered through the searchable "Commander precons" picker below.
			if deck.get("source", "custom") == "precon": continue
			choice.add_item(deck.name)
			choice.set_item_metadata(choice.item_count - 1, {"mode": "saved", "deckId": deck.id})
			choice.set_item_disabled(choice.item_count - 1, not deck.get("legal", true))
		for source in ["precon", "commander"]:
			choice.add_item("Commander precons" if source == "precon" else "Random Commander decks")
			choice.set_item_metadata(choice.item_count - 1, {"mode": source, "deckId": ""})
		for option in range(choice.item_count):
			var data: Dictionary = choice.get_item_metadata(option)
			if data.mode == profile.get("mode", "saved") and (data.mode in ["precon", "commander"] or data.deckId == profile.get("deckId", "")): choice.select(option)
		choice.item_selected.connect(func(option):
			var data: Dictionary = choice.get_item_metadata(option)
			var previous_mode: String = profile.get("mode", "saved")
			profile.mode = data.mode
			if data.mode not in ["precon", "commander"] or previous_mode != data.mode: profile.deckId = data.deckId
			_update_deck_button(profile, index)
			_valid()
			if data.mode in ["precon", "commander"]: _choose_deck(profile, index))
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.clip_text = true
		choice.add_theme_font_size_override("font_size", 15)
		choice.custom_minimum_size.y = 30
		deck_choices.append(choice)
		deck_column.add_child(choice)
		var pick := _button("Choose deck...", func(): _choose_deck(profile, index))
		pick.clip_text = true
		pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
		pick.add_theme_font_size_override("font_size", 14)
		pick.custom_minimum_size.y = 28
		deck_pick_buttons.append(pick)
		deck_column.add_child(pick)
		_update_deck_button(profile, index)

	else:
		var selected: Array = decks.filter(func(deck): return deck.id == selected_deck)
		var deck_name := _text(str(selected[0].name) if not selected.is_empty() else "Choose a deck from the carousel", 17)
		deck_name.clip_text = true
		deck_name.tooltip_text = deck_name.text
		deck_column.add_child(deck_name)
		deck_column.add_child(_text("-- YOUR SELECTED DISK --", 12, DIM))
	if index >= 0:
		var remove := _button("[X] REMOVE", func(): value.bots.remove_at(index); _render())
		remove.disabled = not _may_remove_bot()
		remove.custom_minimum_size.x = 122
		remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		remove.add_theme_font_size_override("font_size", 14)
		remove_buttons.append(remove)
		row.add_child(remove)
	else:
		var command := Control.new()
		command.custom_minimum_size.x = 122
		row.add_child(command)

func _roster_row(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(panel)
	rows.append(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	panel.mouse_entered.connect(func(): _select_row(index))
	return panel

func _select_row(index: int) -> void:
	selected_row = clampi(index, 0, value.bots.size())
	for row_index in range(rows.size()):
		var frame := P.box(Color("0a272b") if row_index == selected_row else Color.TRANSPARENT, Color("1e464b"), 0, 8)
		frame.set_border_width_all(0)
		frame.border_width_bottom = 1
		rows[row_index].add_theme_stylebox_override("panel", frame)

func _empty_slot(slot: int, offer_bot: bool) -> void:
	var panel := _roster_row(slot - 1)
	var row := panel.get_child(0)
	var label := _text("[%02d]" % slot, 20, DIM)
	label.custom_minimum_size.x = 66
	row.add_child(label)
	var plus := _text("[ + ]", 24, DIM)
	plus.custom_minimum_size.x = 84
	row.add_child(plus)
	if offer_bot:
		add_button = _button("[ + ] ADD BOT", func(): _add_bot())
		add_button.custom_minimum_size.x = row_name_width
		add_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(add_button)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size.x = row_name_width
		row.add_child(spacer)
	row.add_child(_text("-- OPEN // ANY PLAYER CAN JOIN --" if _hosting() or _joined() else "-- EMPTY SLOT --", 15, DIM))

func _add_bot() -> void:
	if not _joined() and value.bots.size() + _net_players().size() < 3:
		value.bots.append(Preferences.bot(value.bots.size() + 1))
		_render()

func _hosting() -> bool: return net != null and net.is_hosting()
func _joined() -> bool: return net != null and net.is_joined()
func _net_players() -> Array: return net.players() if _hosting() else []

## A local game needs one bot. A host can drop them all once a real player has joined.
func _may_remove_bot() -> bool:
	return value.bots.size() + _net_players().size() > 1

## A seat somebody else fills: the host may remove a joined player, nobody edits them here.
func _net_row(entry: Dictionary, slot: int) -> void:
	var panel := _roster_row(slot - 1)
	panel.custom_minimum_size.y = 90
	var row := panel.get_child(0) as HBoxContainer
	var seat := VBoxContainer.new()
	seat.custom_minimum_size.x = 66
	seat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var is_you: bool = int(entry.get("id", -1)) == net.you and entry.get("kind", "") == "player" and _joined()
	seat.add_child(_text("[%02d]" % slot, 20))
	seat.add_child(_text("YOU" if is_you else {"host": "HOST", "bot": "BOT"}.get(entry.get("kind", ""), "NET"), 13, DIM))
	row.add_child(seat)
	var phosphor := ShaderMaterial.new()
	phosphor.shader = preload("res://shaders/match_portrait.gdshader")
	if is_you:
		# Your own seat stays editable after joining; the host applies the change for everyone.
		var own := _button("", func(): pass)
		own.icon = Portraits.texture(value.human)
		own.expand_icon = true
		own.custom_minimum_size = Vector2(84, 72)
		own.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		own.tooltip_text = "Change profile picture"
		own.material = phosphor
		own.pressed.connect(func(): _choose_portrait(value.human, own))
		portrait_buttons.append(own)
		row.add_child(own)
	else:
		var portrait := TextureRect.new()
		portrait.texture = Portraits.texture(entry)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(84, 56)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		portrait.material = phosphor
		row.add_child(portrait)
	var name_label := _text(str(entry.get("name", "PLAYER")), 21)
	name_label.custom_minimum_size.x = row_name_width
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.clip_text = true
	row.add_child(name_label)
	var deck_column := VBoxContainer.new()
	deck_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(deck_column)
	var deck_label := _text(str(entry.get("deck", "-- HOST'S CHOICE --" if entry.get("kind", "") in ["host", "bot"] else "")), 17)
	deck_label.clip_text = true
	deck_column.add_child(deck_label)
	if entry.get("kind", "") != "bot":
		deck_column.add_child(_text("READY" if entry.get("ready", false) else "NOT READY", 13, INK if entry.get("ready", false) else DIM))
	if not str(entry.get("commander", "")).is_empty():
		var commander := _text(str(entry.commander), 12, DIM)
		commander.clip_text = true
		deck_column.add_child(commander)
	if _hosting():
		var kick := _button("[X] REMOVE", func(): net.kick(int(entry.id)))
		kick.custom_minimum_size.x = 122
		kick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kick.add_theme_font_size_override("font_size", 14)
		kick_buttons.append(kick)
		row.add_child(kick)

func _render_joined_roster() -> void:
	for index in range(net.roster.size()): _net_row(net.roster[index], index + 1)
	for extra in range(net.open_seats): _empty_slot(net.roster.size() + extra + 1, false)
	add_button = null
	roster.caption = "[ ROSTER // %d OF 4 SLOTS ]" % net.roster.size()
	save_button.disabled = false
	roster.queue_redraw()
	_select_row(0)
	_layout()
	_valid()

## Lobby polling arrives every second, so only rebuild when something visible has changed:
## a rebuild would otherwise take focus from a field the player is typing in.
func _net_changed() -> void:
	var signature := JSON.stringify([net.role, net.players(), net.roster, net.open_seats])
	var seats_changed := signature != net_signature
	net_signature = signature
	if seats_changed: _render()
	_render_online()

func _render_online() -> void:
	if online_body == null or net == null: return
	var typed: String = server_field.text if is_instance_valid(server_field) else Preferences.last_server()
	var had_focus: bool = is_instance_valid(server_field) and server_field.has_focus()
	for child in online_body.get_children():
		online_body.remove_child(child)
		child.queue_free()
	server_field = null
	host_button = null
	join_button = null
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	online_body.add_child(row)
	row.add_child(_text("[ ONLINE ]", 15))
	if net.is_hosting(): _online_hosting(row)
	elif net.is_joined(): _online_joined(row)
	else: _online_idle(row, typed, had_focus)
	if not net.error.is_empty():
		var problem := _text("> " + str(net.error), 13, Color("ffc891"))
		problem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		online_body.add_child(problem)
	for child in online_body.get_children():
		if child is Label:
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _online_idle(row: Container, typed: String, had_focus: bool) -> void:
	host_button = _button("[F5] HOST SESSION", _host)
	row.add_child(host_button)
	var prompt := _text("SERVER IP>", 15, DIM)
	row.add_child(prompt)
	server_field = LineEdit.new()
	server_field.text = typed
	server_field.placeholder_text = "address from the host"
	server_field.custom_minimum_size.x = 180
	server_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	server_field.add_theme_font_size_override("font_size", 17)
	server_field.text_submitted.connect(func(_text_value): _join())
	row.add_child(server_field)
	if had_focus: server_field.grab_focus.call_deferred()
	join_button = _button("CONNECTING..." if net.role == "connecting" else "[F6] JOIN SESSION", _join)
	row.add_child(join_button)
	var blocked: bool = game_running or net.role == "connecting"
	host_button.disabled = blocked
	join_button.disabled = blocked
	if game_running:
		host_button.tooltip_text = "End the live game first"
		join_button.tooltip_text = "End the live game first"

func _online_hosting(row: Container) -> void:
	var address: String = net.share_address()
	var label := _text("HOSTING  //  FRIENDS TYPE THIS IP:", 15, DIM)
	row.add_child(label)
	var shown := _text(address if not address.is_empty() else "FINDING ADDRESS...", 21)
	shown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shown.clip_text = true
	row.add_child(shown)
	var copy := _button("[COPY]", func(): DisplayServer.clipboard_set(net.share_address()))
	copy.disabled = address.is_empty()
	row.add_child(copy)
	row.add_child(_button("[F5] STOP HOSTING", func(): net.stop_hosting()))
	var port := int(net.host_status.get("port", net.DEFAULT_PORT))
	var router: String = {"open": "ROUTER PORT %d OPENED AUTOMATICALLY" % port, "working": "OPENING ROUTER PORT %d..." % port}.get(net.host_status.get("upnp", ""), "ROUTER PORT NOT OPENED: FORWARD TCP %d FOR PLAYERS OUTSIDE YOUR NETWORK" % port)
	var lan: String = net.host_status.get("lan", "")
	online_body.add_child(_text("> " + ("SAME NETWORK: %s  //  " % lan if not lan.is_empty() else "") + router, 13, DIM))
	online_body.add_child(_text("> EVERY PLAYER: SAVE, THEN PRESS PLAY TO READY UP. STARTS WHEN ALL ARE READY.", 13, DIM))
	online_body.add_child(_text("> HOST: " + ("READY" if net.is_ready() else "NOT READY"), 13, DIM))

func _online_joined(row: Container) -> void:
	var label := _text("CONNECTED TO %s  //  %s" % [net.address, "READY - WAITING FOR ALL PLAYERS" if net.is_ready() else "SAVE, THEN PRESS PLAY TO READY UP"], 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	row.add_child(label)
	row.add_child(_button("[F6] LEAVE SESSION", func(): net.leave()))

func _host() -> void:
	if net == null or game_running or not net.is_idle(): return
	net.host(value)

func _join() -> void:
	if net == null or game_running or not net.is_idle() or not is_instance_valid(server_field): return
	var chosen: Array = decks.filter(func(deck): return deck.id == selected_deck and deck.get("legal", true))
	if chosen.is_empty():
		net.error = "Select a legal deck on the carousel before joining."
		_render_online()
		return
	Preferences.save_last_server(server_field.text.strip_edges())
	net.join(server_field.text, value.human, selected_deck)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	for child in get_children():
		if child is Window and child.visible: return
	var editing := get_viewport().gui_get_focus_owner() is LineEdit
	match event.keycode:
		KEY_ESCAPE: canceled.emit()
		KEY_F10:
			if _valid(): saved.emit(value.duplicate(true))
		KEY_F2: _add_bot()
		KEY_F5:
			if _hosting(): net.stop_hosting()
			else: _host()
		KEY_F6:
			if _joined(): net.leave()
			else: _join()
		KEY_DELETE:
			if editing or selected_row == 0 or _joined() or not _may_remove_bot() or selected_row > value.bots.size(): return
			value.bots.remove_at(selected_row - 1)
			_render()
		KEY_UP, KEY_DOWN:
			if editing: return
			_select_row(selected_row + (1 if event.keycode == KEY_DOWN else -1))
			roster_scroll.ensure_control_visible(rows[selected_row])
		KEY_LEFT, KEY_RIGHT:
			if editing or selected_row == 0 or selected_row > deck_choices.size(): return
			var choice := deck_choices[selected_row - 1]
			var direction := 1 if event.keycode == KEY_RIGHT else -1
			var next := posmod(choice.selected + direction, choice.item_count)
			while choice.is_item_disabled(next): next = posmod(next + direction, choice.item_count)
			choice.select(next)
			choice.item_selected.emit(next)
		_: return
	get_viewport().set_input_as_handled()

func _valid() -> bool:
	var valid := names.all(func(field): return not field.text.strip_edges().is_empty())
	error_label.text = "Enter a name for every player." if not valid else "> %d BOTS READY  [ %s ]  -  RANDOM USES FORGE'S COMMANDER GENERATOR" % [value.bots.size(), "||||".repeat(value.bots.size())]
	if _joined(): error_label.text = "> SEATED. YOU PLAY THE DISK SELECTED ON THE CAROUSEL."
	for bot in value.bots:
		if bot.get("mode", "saved") == "saved" and not bot.get("deckId", "").is_empty():
			var matching: Array = decks.filter(func(deck): return deck.id == bot.deckId and deck.get("legal", true))
			if matching.is_empty():
				valid = false
				error_label.text = "Choose a valid saved deck for " + str(bot.name) + "."
		elif bot.get("mode", "saved") in ["precon", "commander"]:
			var matching: Array = deck_catalog.get(bot.mode, []).filter(func(deck): return deck.id == bot.get("deckId", "") and deck.get("legal", true))
			if matching.is_empty():
				valid = false
				error_label.text = "Choose a Forge deck for " + str(bot.name) + "." if deck_catalog.has(bot.mode) else (catalog_error if not catalog_error.is_empty() else "Loading Forge's deck lists...")
	terminal_status.text = "> SYS: deck pool indexed ........................ OK" if deck_catalog.has("commander") else "> SYS: deck pool indexing ..."
	save_button.disabled = not valid
	error_label.add_theme_color_override("font_color", DIM if valid else Color("ffc891"))
	return valid

func _catalog_response(id: int, operation: String, result: Dictionary) -> void:
	if id != catalog_request or operation != "bot.decks": return
	catalog_request = -1
	deck_catalog["precon"] = result.get("precon", [])
	deck_catalog["commander"] = result.get("commander", [])
	for index in range(value.bots.size()): _update_deck_button(value.bots[index], index)
	if is_instance_valid(deck_browser) and deck_browser.visible: _filter_decks()
	_valid()

func _catalog_failed(id: int, message: String) -> void:
	if id != catalog_request: return
	catalog_request = -1
	catalog_error = "Could not load Forge decks. Close and reopen settings to retry. " + message
	if is_instance_valid(deck_browser) and deck_browser.visible: _filter_decks()
	_valid()

func _update_deck_button(profile: Dictionary, index: int) -> void:
	var button := deck_pick_buttons[index]
	button.visible = profile.get("mode", "saved") in ["precon", "commander"]
	var matching: Array = deck_catalog.get(profile.get("mode", ""), []).filter(func(deck): return deck.id == profile.get("deckId", ""))
	button.text = str(matching[0].name) if not matching.is_empty() else "Choose deck..."
	button.tooltip_text = button.text

func _choose_deck(profile: Dictionary, index: int) -> void:
	browser_profile = profile
	browser_index = index
	if is_instance_valid(deck_browser): deck_browser.queue_free()
	deck_browser = AcceptDialog.new()
	_embed_dialog(deck_browser)
	deck_browser.theme = P.popup_theme()
	deck_browser.title = "Commander precons" if profile.mode == "precon" else "Random Commander decks"
	deck_browser.ok_button_text = "Use deck"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	deck_browser.add_child(column)
	var hint := Label.new()
	hint.text = "Choose one of Forge's Commander precons." if profile.mode == "precon" else "Choose a commander; Forge generates their deck when the match starts."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = minf(760, size.x - 150)
	column.add_child(hint)
	deck_search = LineEdit.new()
	deck_search.placeholder_text = "Search decks or commanders..."
	deck_search.text_changed.connect(func(_text): _filter_decks())
	column.add_child(deck_search)
	deck_list = ItemList.new()
	deck_list.add_theme_stylebox_override("panel", P.box(Color("061712"), Color("32676c"), 2, 10))
	deck_list.add_theme_color_override("font_color", Color("a6dfdf"))
	deck_list.add_theme_stylebox_override("selected", P.box(Color("1b2032"), Color("bd9bf2"), 2, 6))
	deck_list.custom_minimum_size = Vector2(0, 340)
	deck_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_list.item_selected.connect(func(_item): deck_browser.get_ok_button().disabled = false)
	deck_list.item_activated.connect(func(_item): _select_browser_deck())
	column.add_child(deck_list)
	deck_browser.confirmed.connect(_select_browser_deck)
	add_child(deck_browser)
	_filter_decks()
	deck_browser.popup_centered(Vector2i(mini(820, int(size.x) - 90), mini(580, int(size.y) - 100)))
	deck_search.grab_focus()

func _filter_decks() -> void:
	deck_list.clear()
	browser_entries.clear()
	deck_browser.get_ok_button().disabled = true
	if not deck_catalog.has(browser_profile.mode):
		deck_list.add_item(catalog_error if not catalog_error.is_empty() else "Loading Forge's deck lists...")
		deck_list.set_item_disabled(0, true)
		return
	var query := deck_search.text.strip_edges().to_lower()
	for deck in deck_catalog[browser_profile.mode]:
		var text: String = str(deck.name)
		if not str(deck.get("commander", "")).is_empty(): text += " / " + str(deck.commander)
		if not query.is_empty() and not text.to_lower().contains(query): continue
		var row := deck_list.add_item(text)
		browser_entries.append(deck)
		deck_list.set_item_disabled(row, not deck.get("legal", true))
		deck_list.set_item_tooltip(row, str(deck.get("problem", "")) if not deck.get("legal", true) else text)
		if deck.id == browser_profile.get("deckId", "") and deck.get("legal", true):
			deck_list.select(row)
			deck_browser.get_ok_button().disabled = false
	if browser_entries.is_empty():
		deck_list.add_item("No decks match your search.")
		deck_list.set_item_disabled(0, true)

func _select_browser_deck() -> void:
	var selected := deck_list.get_selected_items()
	if selected.is_empty() or selected[0] >= browser_entries.size(): return
	var deck: Dictionary = browser_entries[selected[0]]
	if not deck.get("legal", true): return
	browser_profile.deckId = deck.id
	_update_deck_button(browser_profile, browser_index)
	_valid()
	deck_browser.hide()

## Settings runs inside a ScaledSurface SubViewport. Godot resolves an embedded
## dialog's transient parent past that SubViewport to the root window, so an
## exclusive dialog makes the root drop every event before it reaches this
## surface: the dialog shows but nothing, including the dialog, can be clicked.
func _embed_dialog(dialog: Window) -> void:
	dialog.exclusive = false

func _choose_portrait(profile: Dictionary, button: Button) -> void:
	editing_profile = profile
	editing_button = button
	if portrait_dialog != null: portrait_dialog.queue_free()
	portrait_dialog = AcceptDialog.new()
	_embed_dialog(portrait_dialog)
	portrait_dialog.title = "Choose a Forge avatar"
	var choices := VBoxContainer.new()
	portrait_dialog.add_child(choices)
	var caption := Label.new()
	caption.text = "Forge avatars"
	choices.add_child(caption)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650, 410)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	avatar_choices.clear()
	for index in range(Portraits.count()):
		var preset := _button("", func():
			editing_profile.avatar = index
			editing_profile.portrait = ""
			editing_button.icon = Portraits.texture(editing_profile)
			_portrait_chosen()
			portrait_dialog.hide())
		preset.icon = Portraits.texture({"avatar": index})
		preset.expand_icon = true
		preset.custom_minimum_size = Vector2(74, 74)
		preset.tooltip_text = "Forge avatar %d" % (index + 1)
		preset.accessibility_name = preset.tooltip_text
		preset.toggle_mode = true
		preset.button_pressed = profile.get("portrait", "").is_empty() and int(profile.get("avatar", 0)) == index
		grid.add_child(preset)
		avatar_choices.append(preset)
	choices.add_child(_button("Choose image…", _choose_file))
	add_child(portrait_dialog)
	portrait_dialog.popup_centered()

func _choose_file() -> void:
	if file_picker == null:
		file_picker = FileDialog.new()
		_embed_dialog(file_picker)
		file_picker.access = FileDialog.ACCESS_FILESYSTEM
		file_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		file_picker.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp;Profile pictures"])
		file_picker.file_selected.connect(_import_portrait)
		add_child(file_picker)
	file_picker.popup_centered_ratio(0.75)

func _import_portrait(path: String) -> void:
	var pixels: Image = load(path).get_image() if path.begins_with("res://") else Image.load_from_file(path)
	if pixels == null or pixels.is_empty(): error_label.text = "That image could not be read."; return
	var side := mini(pixels.get_width(), pixels.get_height())
	pixels = pixels.get_region(Rect2i((pixels.get_width() - side) / 2, (pixels.get_height() - side) / 2, side, side))
	pixels.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	editing_profile.portrait = Marshalls.raw_to_base64(pixels.save_jpg_to_buffer(0.85))
	editing_button.icon = Portraits.texture(editing_profile)
	_portrait_chosen()
	portrait_dialog.hide()

## Joined to someone else's lobby: send your new portrait to the host (Save & Return keeps it locally).
func _portrait_chosen() -> void:
	if not _joined() or not is_same(editing_profile, value.human): return
	net.set_profile(value.human)
