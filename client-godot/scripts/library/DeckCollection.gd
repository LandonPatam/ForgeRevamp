extends Control
var app_host: Node
const P = preload("res://scripts/ui/Palette.gd")
const Backdrop = preload("res://scripts/ui/TableBackdrop.gd")
const Api = preload("res://scripts/library/LibraryClient.gd")
const Art = preload("res://scripts/library/LibraryImages.gd")
const Tile = preload("res://scripts/library/LibraryCard.gd")
var preferred_columns := 0
var density_slider: HSlider
var density_value: Label
var density_save_timer: Timer
var api: Node
var images: Node
var decks: Array = []
var draft: Dictionary = {}
var dirty := false
var online := false
var revision := 0
var history: Array = []
var future: Array = []
var contexts: Dictionary = {}
var catalog_mode := false
var shown_cards: Array = []
var validation_id := -1
var validated_revision := -1
var validating_revision := -1
var busy := false
var carousel: Control
var workspace: MarginContainer
var workspace_top := 310.0
var context_menu: PopupMenu
var context_card: Dictionary = {}
var open_request := -1
var loading_deck := false
var requested_deck_id := ""
var deck_cache: Dictionary = {}
var card_pool: Array = []
var pool_root: Node
var styled_darkness := -1.0
var last_card_render_ms := 0.0
var card_render_generation := 0
var new_slot_active := false
var card_search: Control
var validate_button: Button
var validation_reason: Label
var delete_button: Button
var darkness := 0.0
var artwork_cards: Array = []
var artwork_page := 0
var artwork_mode := false
var apply_art_to_all := false
var printing_cache: Dictionary = {}
var pending_switch := false
var switch_cancel_button: Button
var card_grid: GridContainer
var card_scroll: ScrollContainer
var name_edit: LineEdit
var search: LineEdit
var type_filter: OptionButton
var color_filter: OptionButton
var mana_filter: OptionButton
var section_filter: OptionButton
var count_label: Label
var library_label: Label
var stats_label: Label
var status_label: Label
var connection_label: Label
var empty_label: Label
var save_button: Button
var undo_button: Button
var redo_button: Button
var deck_button: Button
var catalog_button: Button
var tab_styles: Dictionary = {"active": {}, "inactive": {}}
var overlay: ColorRect
var dialog: PanelContainer
var dialog_body: VBoxContainer
var file_dialog: FileDialog
var export_dialog: FileDialog
var export_text := ""
var import_text: TextEdit
var import_url: LineEdit
var import_name: LineEdit
var import_behavior: OptionButton
var import_art: OptionButton
var import_core: CheckBox
var import_smart: CheckBox
var import_restricted: CheckBox
var import_date: CheckBox
var import_year: SpinBox
var import_month: OptionButton
var import_status: Label
var inspect_card: Dictionary = {}
var preview: Dictionary = {}
var preview_behavior := 0
var search_timer: Timer
var validation_timer: Timer
var integration_checks: RefCounted
var quit_after_save := false
## A precon was just saved as a custom copy; show it once the library list refreshes.
var reveal_saved_copy := false

func _ready() -> void:
	get_window().gui_embed_subwindows = true
	_load_density()
	theme = P.popup_theme()
	theme.default_font = P.make_theme().default_font
	theme.default_font_size = 15
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if app_host == null:
		var background := ColorRect.new()
		background.color = Color("d9dfe2")
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(background)
	if app_host == null:
		api = Api.new()
		images = Art.new()
		images.api = api
	else:
		api = app_host.api
		images = app_host.images
		decks = app_host.decks.duplicate(true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--library-url="): api.url = arg.trim_prefix("--library-url=")
		if arg in ["--library-check", "--app-check"]: images.network_enabled = false
	if "--library-online-images" in OS.get_cmdline_user_args(): images.network_enabled = true
	_build()
	set_darkness(app_host.computer.darkness if app_host != null else 0.0)
	api.connected.connect(func():
		online = true
		connection_label.text = "●  FORGE CONNECTED"
		connection_label.modulate = Color("6ce3bd")
		_request("list")
		_controls())
	api.disconnected.connect(func():
		online = false
		connection_label.text = "○  RECONNECTING · changes retained"
		connection_label.modulate = Color("e8b76a")
		_controls())
	api.response.connect(_response)
	api.failed.connect(_failed)
	if app_host == null:
		add_child(api)
		add_child(images)
	else:
		online = app_host.online
		connection_label.text = "FORGE CONNECTED" if online else "CONNECTING"
	search_timer = Timer.new()
	search_timer.one_shot = true
	search_timer.wait_time = 0.3
	search_timer.timeout.connect(_refresh_cards)
	add_child(search_timer)
	validation_timer = Timer.new()
	validation_timer.one_shot = true
	validation_timer.wait_time = 0.35
	validation_timer.timeout.connect(_validate)
	add_child(validation_timer)
	density_save_timer = Timer.new()
	density_save_timer.one_shot = true
	density_save_timer.wait_time = 0.25
	density_save_timer.timeout.connect(_save_density)
	add_child(density_save_timer)
	pool_root = Node.new()
	add_child(pool_root)
	resized.connect(_resize)
	_resize.call_deferred()
	_controls()
	if app_host != null and online:
		if app_host.selected_deck.has("sections"): _load_deck(app_host.selected_deck)
		_request("list")
	if app_host == null:
		get_tree().auto_accept_quit = false
		get_window().close_requested.connect(_close_requested)
	for arg in OS.get_cmdline_user_args():
		if arg == "--library-check":
			integration_checks = load("res://tests/LibraryIntegration.gd").new()
			integration_checks.run.call_deferred(self)

func _label(text: String, font_size: int = 15, color: Color = P.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if color in [P.TEXT, Color.WHITE, P.MUTED]: label.add_theme_color_override("font_color", Color("304a55").lerp(Color("d5e6e3"), darkness))
	return label

func _button(text: String, callback: Callable, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	P.style_menu_button(button, accent)
	button.add_theme_font_size_override("font_size", 14)
	button.custom_minimum_size.y = 40
	button.set_meta("workbench_accent", accent)
	_style_workbench(button, Color("304a55").lerp(Color("d5e6e3"), darkness), Color("58707a").lerp(Color("a5bdb8"), darkness), Color("e4e9ea").lerp(Color("3a4447"), darkness), Color("b4c1c7").lerp(Color("63787a"), darkness))
	button.pressed.connect(callback)
	return button

func _option(items: Array, callback: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item in items: option.add_item(item)
	P.style_menu_button(option)
	option.add_theme_font_size_override("font_size", 13)
	option.custom_minimum_size.y = 38
	_style_workbench(option, Color("304a55").lerp(Color("d5e6e3"), darkness), Color("58707a").lerp(Color("a5bdb8"), darkness), Color("e4e9ea").lerp(Color("3a4447"), darkness), Color("b4c1c7").lerp(Color("63787a"), darkness))
	option.item_selected.connect(callback)
	return option

func _spacer(parent: Container) -> void:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

func _build() -> void:
	connection_label = _label("CONNECTING", 12, P.MUTED)
	library_label = _label("", 12, P.MUTED)
	if app_host == null:
		var header := HBoxContainer.new()
		header.position = Vector2(32, 20)
		add_child(header)
		header.add_child(_label("FORGE / DECK EDITOR", 20))
		header.add_child(library_label)
		carousel = preload("res://scripts/app/DeckCarousel.gd").new()
		carousel.images = images
		carousel.position = Vector2(0, 60)
		carousel.size = Vector2(size.x, 225)
		carousel.configure_editor(true)
		carousel.deck_selected.connect(func(index): select_deck(decks[index].id))
		carousel.new_deck_requested.connect(create_from_carousel)
		add_child(carousel)
	else:
		add_child(library_label)
		library_label.hide()
	workspace = MarginContainer.new()
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.offset_left = 40
	workspace.offset_right = -40
	workspace.offset_top = workspace_top
	workspace.offset_bottom = -20
	add_child(workspace)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 10)
	workspace.add_child(main)
	var name_row := HBoxContainer.new()
	main.add_child(name_row)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Select a deck or create one"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 30)
	name_edit.add_theme_font_override("font", P.display_font())
	name_edit.add_theme_stylebox_override("normal", P.box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	name_edit.text_changed.connect(func(text):
		if draft.is_empty(): return
		_record()
		draft.name = text
		_changed(false))
	name_row.add_child(name_edit)
	count_label = _label("", 23, Color.WHITE)
	name_row.add_child(count_label)
	status_label = _label("", 12, P.MUTED)
	status_label.custom_minimum_size.x = 200
	status_label.clip_text = true
	status_label.hide()
	name_row.add_child(status_label)
	name_row.add_child(connection_label)
	var actions := HBoxContainer.new()
	main.add_child(actions)
	deck_button = _button("DECK", func(): _set_mode(false), true)
	catalog_button = _button("+ ADD CARDS", func(): _set_mode(true))
	for style in ["normal", "hover", "pressed", "disabled", "focus"]:
		tab_styles.active[style] = deck_button.get_theme_stylebox(style)
		tab_styles.inactive[style] = catalog_button.get_theme_stylebox(style)
	actions.add_child(deck_button)
	actions.add_child(catalog_button)
	stats_label = _label("", 13, P.MUTED)
	actions.add_child(stats_label)
	var validation_group := HBoxContainer.new()
	validation_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validation_group.add_theme_constant_override("separation", 10)
	actions.add_child(validation_group)
	validate_button = preload("res://scripts/library/DeckValidationStatus.gd").new()
	validate_button.pressed.connect(func(): _validate(true))
	validate_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	validation_group.add_child(validate_button)
	validation_reason = _label("", 12, Color("8a651e"))
	validation_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_reason.custom_minimum_size.x = 100
	validation_reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validation_reason.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	validation_reason.hide()
	validation_group.add_child(validation_reason)
	undo_button = _button("Undo", _undo)
	redo_button = _button("Redo", _redo)
	actions.add_child(undo_button)
	actions.add_child(redo_button)
	actions.add_child(_button("New / import", _show_import))
	actions.add_child(_button("Deck actions", _show_actions))
	save_button = _button("Save deck", _save, true)
	actions.add_child(save_button)
	var filters := HBoxContainer.new()
	main.add_child(filters)
	search = LineEdit.new()
	search.placeholder_text = "Search cards or rules text…"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_text): search_timer.start())
	filters.add_child(search)
	type_filter = _option(["All types", "Creature", "Instant", "Sorcery", "Artifact", "Enchantment", "Planeswalker", "Land", "Battle"], _filter_changed)
	filters.add_child(type_filter)
	color_filter = _option(["All colors", "White", "Blue", "Black", "Red", "Green", "Colorless"], _filter_changed)
	filters.add_child(color_filter)
	mana_filter = _option(["Any mana", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"], _filter_changed)
	filters.add_child(mana_filter)
	section_filter = _option(["All sections", "Commander", "Main", "Sideboard", "Avatar", "Planes", "Schemes", "Conspiracy", "Dungeon", "Attractions", "Contraptions", "Stickers"], _filter_changed)
	filters.add_child(section_filter)
	density_slider = HSlider.new()
	density_slider.min_value = 0
	density_slider.max_value = 12
	density_slider.step = 1
	density_slider.value = preferred_columns
	density_slider.custom_minimum_size = Vector2(140, 28)
	density_slider.tooltip_text = "Choose 1–12 cards per row. The far left uses Auto."
	density_slider.value_changed.connect(_density_changed)
	density_value = _label("Auto" if preferred_columns == 0 else str(preferred_columns), 13)
	density_value.custom_minimum_size.x = 40
	filters.add_child(_label("Cards per row", 12, P.MUTED))
	filters.add_child(density_slider)
	filters.add_child(density_value)
	card_scroll = ScrollContainer.new()
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	card_scroll.resized.connect(_resize)
	main.add_child(card_scroll)
	card_grid = GridContainer.new()
	card_grid.columns = 6
	card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_grid.add_theme_constant_override("h_separation", 15)
	card_grid.add_theme_constant_override("v_separation", 18)
	card_scroll.add_child(card_grid)
	empty_label = _label("Your decks will appear here once Forge connects.", 18, P.MUTED)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_grid.add_child(empty_label)
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 80
	overlay.hide()
	add_child(overlay)
	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_card_action)
	add_child(context_menu)
	_render_decks()

func _ensure_file_dialogs() -> void:
	if file_dialog != null: return
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.dck;Forge decks", "*.txt,*.dec;Text deck lists", "*;All files"])
	file_dialog.file_selected.connect(func(path):
		if FileAccess.get_file_as_bytes(path).size() > 900000: import_status.text = "Choose a file smaller than 900 KB."; return
		import_text.text = FileAccess.get_file_as_string(path)
		import_status.text = "Loaded " + path.get_file())
	add_child(file_dialog)
	export_dialog = FileDialog.new()
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.filters = PackedStringArray(["*.dck;Forge deck"])
	export_dialog.file_selected.connect(func(path):
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: _notice("Could not write the exported deck.", true); return
		file.store_string(export_text)
		_notice("Exported " + path.get_file()))
	add_child(export_dialog)

func _density_path() -> String:
	# Integration runs keep preferences inside their isolated fixture directory.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--library-fixture="):
			return arg.trim_prefix("--library-fixture=").path_join("collection-layout.cfg")
	return "user://collection-layout.cfg"

func _load_density() -> void:
	var config := ConfigFile.new()
	if config.load(_density_path()) != OK: return
	var value = config.get_value("cards", "columns", 0)
	if value is int and value >= 0 and value <= 12: preferred_columns = value

func _density_changed(value: float) -> void:
	preferred_columns = roundi(value)
	density_value.text = "Auto" if preferred_columns == 0 else str(preferred_columns)
	_resize()
	density_save_timer.start()

func _save_density() -> void:
	var config := ConfigFile.new()
	config.set_value("cards", "columns", preferred_columns)
	if config.save(_density_path()) != OK:
		_notice("Card layout changed, but the preference could not be saved.", true)

func _exit_tree() -> void:
	if density_save_timer != null and not density_save_timer.is_stopped(): _save_density()

func _resize() -> void:
	queue_redraw()
	if carousel != null:
		carousel.size = Vector2(size.x, clampf(size.y * 0.38, 290, 390))
		set_workspace_top(carousel.position.y + carousel.size.y + 6)
	if card_grid == null: return
	var width := maxf(400, card_scroll.size.x - 16)
	var automatic_width := clampf((card_scroll.size.y-40)/1.4, 140, 190)
	card_grid.columns = preferred_columns if preferred_columns > 0 else maxi(2, ceili((width+15) / (automatic_width+15)))
	var card_width := floorf((width - 15 * (card_grid.columns - 1)) / card_grid.columns)
	for child in card_grid.get_children():
		if child is Tile: child.custom_minimum_size = Vector2(card_width, card_width * 1.4 + 30)

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _render_decks() -> void:
	library_label.text = str(decks.size()) + " DECKS"
	var active: String = draft.get("id", "")
	if not draft.is_empty() and active.is_empty(): active = "__new_deck__"
	if active.is_empty() and app_host != null: active = app_host.selected_id
	if carousel != null: carousel.set_decks(decks, active)
	elif app_host != null: app_host.sync_editor_library(decks, active)

func select_deck(id: String) -> void:
	if busy: return
	if id == draft.get("id", ""):
		if not loading_deck: return
		open_request = -1
		loading_deck = false
		_sync_selection(id)
		name_edit.text = draft.name
		_refresh_cards()
		_controls()
		return
	if loading_deck and id == requested_deck_id: return
	_switch_to(func():
		_sync_selection(id)
		if deck_cache.has(id):
			open_request = -1
			_load_deck(deck_cache[id])
			_request("open", {"id": id}, {"background": true, "revision": revision})
		else: _request("open", {"id": id}))

func _sync_selection(id: String) -> void:
	if carousel != null: carousel.select_id(id)
	elif app_host != null:
		if id != "__new_deck__": app_host.selected_id = id
		app_host.computer.select_id(id)

func create_from_carousel() -> void:
	if busy: return
	new_slot_active = true
	_show_import()

func _request(operation: String, arguments: Dictionary = {}, context: Dictionary = {}) -> int:
	var id: int = api.request(operation, arguments)
	if operation == "open" and not context.get("background", false):
		open_request = id
		requested_deck_id = arguments.id
		loading_deck = true
		name_edit.text = "Loading deck..."
		_controls()
	contexts[id] = context.duplicate(true)
	contexts[id].operation = operation
	return id

func _response(id: int, operation: String, result: Dictionary) -> void:
	if operation == "image" or not contexts.has(id): return
	var context: Dictionary = contexts.get(id, {})
	contexts.erase(id)
	match operation:
		"list":
			if decks != result.decks: deck_cache.clear()
			decks = result.decks
			_render_decks()
			if reveal_saved_copy:
				reveal_saved_copy = false
				if app_host != null and app_host.computer.deck_filter == "precon": app_host.computer.set_deck_filter("custom")
			if draft.is_empty() and not loading_deck and not decks.is_empty(): _request("open", {"id": app_host.selected_id if app_host != null and decks.any(func(deck): return deck.id == app_host.selected_id) else decks[0].id})
			elif draft.is_empty(): _notice("No decks yet. Use + to create or import your first deck.")
			if not result.get("warnings", []).is_empty(): _notice("Some deck files could not be read: " + "; ".join(result.warnings), true)
		"open":
			deck_cache[result.id] = result.duplicate(true)
			if context.get("background", false):
				if not busy and not dirty and not loading_deck and context.get("revision", -1) == revision and result.id == draft.get("id", "") and result.version != draft.get("version", ""): _load_deck(result)
			elif id == open_request: _load_deck(result)
		"save":
			busy = false
			reveal_saved_copy = context.get("copy", false)
			_load_deck(result)
			_request("list")
			_notice("Saved to your Forge Commander library.")
			if quit_after_save: get_tree().quit()
		"delete":
			busy = false
			deck_cache.erase(result.id)
			decks = decks.filter(func(deck): return deck.id != result.id)
			draft = {}
			dirty = false
			catalog_mode = false
			open_request = -1
			loading_deck = false
			history.clear()
			future.clear()
			revision += 1
			name_edit.text = ""
			_summary()
			_refresh_cards()
			_render_decks()
			overlay.hide()
			_request("list")
		"validate":
			if context.get("revision", -1) != revision: return
			if context.get("explicit", false):
				validated_revision = revision
				validating_revision = -1
			for key in ["count", "lands", "averageMana", "curve", "legal", "validation"]: draft[key] = result[key]
			_summary()
		"import":
			busy = false
			preview = result
			preview_behavior = context.get("behavior", 0)
			_show_import_preview()
		"export":
			if context.get("clipboard", false):
				DisplayServer.clipboard_set(result.text)
				_notice("Deck list copied to clipboard.")
			else:
				export_text = result.text
				_ensure_file_dialogs()
				export_dialog.current_file = draft.get("name", "Deck").validate_filename() + ".dck"
				export_dialog.popup_centered_ratio(0.7)
		"printings":
			if printing_cache.size() >= 32: printing_cache.erase(printing_cache.keys()[0])
			printing_cache[context.get("name", "")] = result.cards
			if overlay.visible and context.get("art_gallery", false) == artwork_mode and context.get("key", "") == inspect_card.get("key", ""):
				if context.get("art_gallery", false):
					artwork_cards = result.cards
					artwork_page = 0
					_render_artwork()
				else: _printing_choices(result.cards)
	_controls()

func _failed(id: int, message: String) -> void:
	if not contexts.has(id): return # artwork failures retain the card's text face
	var failed_operation: String = contexts[id].get("operation", "")
	if failed_operation == "validate" and contexts[id].get("revision", -1) == revision and contexts[id].get("explicit", false): validating_revision = -1
	if contexts[id].get("background", false):
		contexts.erase(id)
		return
	if contexts[id].get("operation", "") == "open" and id != open_request:
		contexts.erase(id)
		return
	contexts.erase(id)
	if id == open_request:
		loading_deck = false
		_sync_selection(draft.get("id", ""))
		name_edit.text = draft.get("name", "")
	busy = false
	quit_after_save = false
	_notice(message, true)
	if failed_operation == "delete":
		var body := _dialog("DECK WAS NOT DELETED", 620, 300)
		var report := _label(message, 16)
		report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(report)
		body.add_child(_button("Back to deck", func(): overlay.hide()))
	if overlay.visible and is_instance_valid(import_status): import_status.text = message
	_controls()

func _load_deck(value: Dictionary) -> void:
	open_request = -1
	busy = false
	loading_deck = false
	new_slot_active = false
	if not str(value.get("id", "")).is_empty(): deck_cache[value.id] = value.duplicate(true)
	draft = value.duplicate(true)
	dirty = false
	history.clear()
	future.clear()
	revision += 1
	validated_revision = revision if value.get("legal", false) else -1
	validating_revision = -1
	name_edit.text = draft.name
	_summary()
	_refresh_cards()
	_update_draft_cover()
	_sync_selection(str(draft.id) if not str(draft.id).is_empty() else "__new_deck__")
	_controls()

func _set_mode(catalog: bool) -> void:
	if busy or loading_deck: return
	if catalog:
		_show_card_search()
		return
	overlay.hide()
	catalog_mode = false
	_refresh_cards()
	_controls()

func _filter_changed(_index: int) -> void:
	_refresh_cards()

func _filters() -> Dictionary:
	return {"query": search.text, "type": "" if type_filter.selected == 0 else type_filter.text,
		"color": "" if color_filter.selected == 0 else "WUBRGC".substr(color_filter.selected - 1, 1),
		"mana": mana_filter.selected - 1}

func _refresh_cards(keep_scroll: bool = false) -> void:
	shown_cards.clear()
	var filter := _filters()
	var query_key: String = preload("res://scripts/library/CardSearch.gd").search_key(str(filter.query))
	for section in draft.get("sections", {}):
		if section_filter.selected != 0 and section_filter.text != section: continue
		for card in draft.sections[section]:
			if not query_key.is_empty() and not preload("res://scripts/library/CardSearch.gd").search_key(card.name + " " + card.text).contains(query_key): continue
			if not filter.type.is_empty() and not card.typeLine.to_lower().contains(filter.type.to_lower()): continue
			if not filter.color.is_empty():
				var mask := int(card.colorIdentity)
				if filter.color == "C" and mask != 0: continue
				if filter.color != "C" and (mask & (1 << "WUBRG".find(filter.color))) == 0: continue
			if filter.mana >= 0 and int(card.manaValue) != filter.mana: continue
			var entry: Dictionary = card.duplicate(true)
			entry.section = section
			entry.commander = section == "Commander"
			shown_cards.append(entry)
	shown_cards.sort_custom(func(a, b):
		if (a.section == "Commander") != (b.section == "Commander"): return a.section == "Commander"
		if a.manaValue != b.manaValue: return a.manaValue < b.manaValue
		return a.name < b.name)
	_render_cards(0, keep_scroll)

func _render_cards(append_from: int = 0, keep_scroll: bool = false) -> void:
	var render_start := Time.get_ticks_usec()
	var scroll_position := card_scroll.scroll_vertical
	card_render_generation += 1
	if append_from == 0:
		for child in card_grid.get_children():
			card_grid.remove_child(child)
			if child is Tile:
				child.hide()
				pool_root.add_child(child)
				card_pool.append(child)
			else: child.queue_free()
	var entries: Array = shown_cards.slice(append_from) if append_from > 0 else shown_cards
	for card in entries:
		var reused := not card_pool.is_empty()
		var tile: Control = card_pool.pop_back() if reused else Tile.new()
		if reused: pool_root.remove_child(tile)
		tile.card = card
		tile.images = images
		tile.ink = Color("304a55").lerp(Color("d5e6e3"), darkness)
		tile.hot = false
		if reused: tile.texture = images.request_texture(card)
		tile.tooltip_text = card.name + "\n" + card.get("section", card.typeLine)
		if not reused:
			tile.chosen.connect(_inspect)
			tile.context_requested.connect(_card_context)
		card_grid.add_child(tile)
		tile.show()
		tile.queue_redraw()
	if shown_cards.is_empty():
		var empty := _label("No cards match these filters." if not draft.is_empty() else "Choose a deck from the carousel, or create a new one.", 17, P.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_grid.add_child(empty)
	if append_from == 0 and not keep_scroll: card_scroll.scroll_vertical = 0
	images.prioritize(entries)
	_resize.call_deferred()
	if keep_scroll: _restore_card_scroll(scroll_position, card_render_generation)
	last_card_render_ms = (Time.get_ticks_usec()-render_start)/1000.0

func _restore_card_scroll(position: int, generation: int) -> void:
	# The grid and scrollbar need to settle after replacing pooled card tiles.
	await get_tree().process_frame
	await get_tree().process_frame
	if generation == card_render_generation:
		card_scroll.scroll_vertical = position

func _record() -> void:
	history.append(draft.duplicate(true))
	if history.size() > 60: history.pop_front()
	future.clear()

func _changed(refresh: bool = true, keep_scroll: bool = false) -> void:
	dirty = true
	revision += 1
	validated_revision = -1
	validating_revision = -1
	validation_timer.start()
	if refresh: _refresh_cards(keep_scroll)
	_update_draft_cover()
	_controls()

func _update_draft_cover() -> void:
	var leaders: Array = draft.get("sections", {}).get("Commander", [])
	var main: Array = draft.get("sections", {}).get("Main", [])
	var cover: Dictionary = leaders[0] if not leaders.is_empty() else (main[0] if not main.is_empty() else {})
	for deck in decks:
		if deck.id == draft.get("id", "") and deck.get("cover", {}) != cover:
			deck.cover = cover.duplicate(true)
			_render_decks()
			return

func _undo() -> void:
	if history.is_empty() or busy or loading_deck: return
	future.append(draft.duplicate(true))
	draft = history.pop_back()
	name_edit.text = draft.name
	_changed()

func _redo() -> void:
	if future.is_empty() or busy or loading_deck: return
	history.append(draft.duplicate(true))
	draft = future.pop_back()
	name_edit.text = draft.name
	_changed()

func _validate(explicit: bool = false) -> void:
	if online and not draft.is_empty() and not draft.name.strip_edges().is_empty():
		if explicit and validating_revision == revision: return
		if explicit: validation_timer.stop()
		if explicit: validating_revision = revision
		validation_id = _request("validate", {"deck": draft}, {"revision": revision, "explicit": explicit})
		_controls()

func _summary() -> void:
	count_label.text = str(int(draft.get("count", 0))) + " / 100"
	stats_label.text = "%s lands  ·  %s nonlands  ·  %.2f avg mana" % [int(draft.get("lands", 0)), int(draft.get("count", 0)) - int(draft.get("lands", 0)), draft.get("averageMana", 0.0)]
	var text: String = draft.get("validation", "")
	_notice(("✓ " if draft.get("legal", false) else "Deck check: ") + text, false)
	status_label.tooltip_text = text
	count_label.tooltip_text = text
	if not draft.get("legal", false): status_label.modulate = Color("d9bd86")

func _controls() -> void:
	if save_button == null: return
	if carousel != null: carousel.enabled = not busy
	elif app_host != null and app_host.view == "editor" and app_host.computer.phase == "idle": app_host.computer.shelf.enabled = not busy
	var read_only: bool = draft.get("readOnly", false)
	save_button.text = ("Save as copy" if read_only else "Save deck") + " *" if dirty else ("Save as copy" if read_only else "Saved")
	save_button.tooltip_text = "Forge precons are read-only. Saving creates your own custom deck." if read_only else ""
	var locked := busy or loading_deck
	validate_button.update_status(validated_revision == revision and draft.get("legal", false) and not draft.is_empty() and not loading_deck, validating_revision == revision, not locked and online and not draft.is_empty() and not draft.get("name", "").strip_edges().is_empty(), draft.get("validation", "") if validated_revision == revision else "")
	validation_reason.visible = validated_revision == revision and not draft.get("legal", false) and not draft.is_empty() and not loading_deck and validating_revision != revision
	validation_reason.text = str(draft.get("validation", "")) if validation_reason.visible else ""
	validation_reason.tooltip_text = validation_reason.text
	catalog_button.disabled = locked or not online or draft.is_empty()
	card_grid.modulate.a = 0.45 if loading_deck else 1.0
	save_button.disabled = locked or not online or draft.is_empty() or not (dirty or read_only) or draft.get("name", "").strip_edges().is_empty()
	name_edit.editable = not draft.is_empty() and not locked
	undo_button.disabled = history.is_empty() or locked
	redo_button.disabled = future.is_empty() or locked
	for tab in [deck_button, catalog_button]:
		_style_workbench(tab, Color("304a55").lerp(Color("d5e6e3"), darkness), Color("58707a").lerp(Color("a5bdb8"), darkness), Color("e4e9ea").lerp(Color("3a4447"), darkness), Color("b4c1c7").lerp(Color("63787a"), darkness))

func _save() -> void:
	if busy or loading_deck or draft.is_empty(): return
	busy = true
	if draft.get("readOnly", false):
		# Precons are never overwritten: save the edited cards as a new custom deck.
		var copy := draft.duplicate(true)
		copy.sourceId = copy.id
		copy.id = ""
		copy.version = ""
		copy.erase("readOnly")
		copy.erase("source")
		_request("save", {"deck": copy}, {"copy": true})
	else: _request("save", {"deck": draft})
	_controls()

func _notice(text: String, error: bool = false) -> void:
	status_label.text = text
	status_label.tooltip_text = text
	status_label.visible = error
	status_label.modulate = Color("ff9b91") if error else Color("c5c9ce")

func _switch_to(callback: Callable) -> void:
	if busy: return
	if not dirty: callback.call(); return
	var body := _dialog("Unsaved deck changes", 600, 270)
	pending_switch = true
	var message := _label("Discard your unsaved changes and open the other deck?", 16)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(message)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	switch_cancel_button = _button("Keep editing", func(): _cancel_switch(); overlay.hide())
	actions.add_child(switch_cancel_button)
	actions.add_child(_button("Discard changes", func(): pending_switch = false; overlay.hide(); callback.call(), true))

func _cancel_switch() -> void:
	if new_slot_active:
		new_slot_active = false
		_sync_selection(draft.get("id", ""))
	if not pending_switch: return
	pending_switch = false
	if carousel != null: carousel.select_id(draft.get("id", ""))
	elif app_host != null: app_host.computer.select_id(draft.get("id", ""))

func close_transient_ui() -> void:
	if carousel != null: carousel.close_color_menu()
	_cancel_switch()
	overlay.hide()
	context_menu.hide()
	for child in get_children():
		if child is Window: child.hide()

func _dialog(title: String, width: int = 820, height: int = 650) -> VBoxContainer:
	artwork_mode = false
	_clear(overlay)
	overlay.show()
	dialog = PanelContainer.new()
	P.style_popup(dialog, 25)
	dialog.theme = theme
	dialog.add_theme_stylebox_override("panel", P.box(Color("e4e9ea").lerp(Color("303a3d"), darkness), Color("9bb3b9"), 10, 25))
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var dialog_size := Vector2(mini(width, int(size.x) - 60), mini(height, int(size.y) - 70))
	dialog.offset_left = -dialog_size.x / 2
	dialog.offset_right = dialog_size.x / 2
	dialog.offset_top = -dialog_size.y / 2
	dialog.offset_bottom = dialog_size.y / 2
	overlay.add_child(dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 13)
	dialog.add_child(body)
	var top := HBoxContainer.new()
	body.add_child(top)
	top.add_child(_label(title, 23, Color.WHITE))
	_spacer(top)
	top.add_child(_button("×", func():
		if not busy: _cancel_switch(); overlay.hide()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	dialog_body = VBoxContainer.new()
	dialog_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_body.add_theme_constant_override("separation", 12)
	scroll.add_child(dialog_body)
	return dialog_body

func _show_import() -> void:
	if busy: return
	if loading_deck:
		open_request = -1
		loading_deck = false
		name_edit.text = draft.get("name", "")
		_sync_selection("__new_deck__" if new_slot_active else draft.get("id", ""))
		_controls()
	var body := _dialog("ADD A DECK", 850, 800)
	body.add_child(_label("Build something new, or bring a deck into your Forge library.", 14, P.MUTED))
	import_name = LineEdit.new()
	import_name.placeholder_text = "Deck name (optional for imports)"
	body.add_child(import_name)
	var create_row := HBoxContainer.new()
	body.add_child(create_row)
	create_row.add_child(_button("+ Blank deck", func():
		var name := import_name.text.strip_edges()
		var blank := {"id": "", "version": "", "name": name if not name.is_empty() else "Untitled deck", "sections": {"Commander": [], "Main": [], "Sideboard": []}}
		_switch_to(func(): _load_deck(blank); dirty = true; _controls(); overlay.hide(); _set_mode(true); _validate()), true))
	var duplicate := _button("Duplicate selected deck", func():
		var copy := draft.duplicate(true)
		copy.sourceId = draft.get("id", "") if not draft.get("id", "").is_empty() else draft.get("sourceId", "")
		copy.id = ""
		copy.version = ""
		copy.erase("readOnly")
		copy.erase("source")
		copy.name = import_name.text.strip_edges() if not import_name.text.strip_edges().is_empty() else draft.name + " copy"
		_load_deck(copy)
		dirty = true
		_controls()
		overlay.hide())
	duplicate.disabled = draft.is_empty()
	create_row.add_child(duplicate)
	body.add_child(HSeparator.new())
	var sources := HBoxContainer.new()
	body.add_child(sources)
	sources.add_child(_button("Paste clipboard", func(): import_text.text = DisplayServer.clipboard_get()))
	sources.add_child(_button("Choose deck file…", func(): _ensure_file_dialogs(); file_dialog.popup_centered_ratio(0.75)))
	body.add_child(_label("PASTED LIST OR FILE CONTENTS", 12, P.MUTED))
	import_text = TextEdit.new()
	import_text.placeholder_text = "Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n1 Sol Ring\n…"
	import_text.custom_minimum_size.y = 155
	body.add_child(import_text)
	import_url = LineEdit.new()
	import_url.placeholder_text = "Or a deck URL: Moxfield, Archidekt, TappedOut, MTGGoldfish"
	body.add_child(import_url)
	body.add_child(_label("A URL takes precedence over pasted text. Private decks may be unavailable.", 12, P.MUTED))
	var behavior_row := HBoxContainer.new()
	body.add_child(behavior_row)
	behavior_row.add_child(_label("Import into"))
	import_behavior = _option(["New deck", "Merge into selected deck", "Replace selected deck"], func(_index): pass)
	import_behavior.set_item_disabled(1, draft.is_empty())
	import_behavior.set_item_disabled(2, draft.is_empty())
	behavior_row.add_child(import_behavior)
	var advanced := VBoxContainer.new()
	advanced.hide()
	body.add_child(_button("Forge import settings ▾", func(): advanced.visible = not advanced.visible))
	body.add_child(advanced)
	var art_row := HBoxContainer.new()
	advanced.add_child(art_row)
	art_row.add_child(_label("Unspecified printings"))
	import_art = _option(["Latest printing", "Original printing"], func(_index): pass)
	art_row.add_child(import_art)
	import_core = CheckBox.new()
	import_core.text = "Core / expansion sets only"
	art_row.add_child(import_core)
	import_smart = CheckBox.new()
	import_smart.text = "Smart art selection"
	import_smart.button_pressed = true
	advanced.add_child(import_smart)
	import_restricted = CheckBox.new()
	import_restricted.text = "Include banned / restricted cards (keep legality warnings)"
	import_restricted.button_pressed = true
	advanced.add_child(import_restricted)
	var date_row := HBoxContainer.new()
	advanced.add_child(date_row)
	import_date = CheckBox.new()
	import_date.text = "Printings released before"
	date_row.add_child(import_date)
	import_month = _option(["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"], func(_index): pass)
	import_month.select(11)
	date_row.add_child(import_month)
	import_year = SpinBox.new()
	import_year.min_value = 1993
	import_year.max_value = int(Time.get_date_dict_from_system().year)
	import_year.value = import_year.max_value
	date_row.add_child(import_year)
	import_status = _label("Forge recognizes common text formats and native .dck files.", 12, P.MUTED)
	import_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(import_status)
	body.add_child(_button("Preview import", _preview_import, true))

func _preview_import() -> void:
	if busy: return
	busy = true
	import_status.text = "Reading deck with Forge…"
	_request("import", {"name": import_name.text, "text": import_text.text, "url": import_url.text,
		"art": "latest" if import_art.selected == 0 else "original", "coreOnly": import_core.button_pressed,
		"smartArt": import_smart.button_pressed, "includeRestricted": import_restricted.button_pressed,
		"dateEnabled": import_date.button_pressed, "year": int(import_year.value), "month": import_month.selected}, {"behavior": import_behavior.selected})
	_controls()

func _show_import_preview() -> void:
	var body := _dialog("REVIEW IMPORT", 850, 760)
	var action: String = ["Create a new deck", "Merge into " + draft.get("name", "deck"), "Replace " + draft.get("name", "deck")][preview_behavior]
	body.add_child(_label(preview.name, 23, Color.WHITE))
	body.add_child(_label(action + " · %s cards recognized" % int(preview.count), 15))
	var validation := _label(preview.validation, 13, Color("dfc594"))
	validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(validation)
	var grid := GridContainer.new()
	grid.columns = 5
	body.add_child(grid)
	var count := 0
	for section in preview.sections:
		for card in preview.sections[section]:
			if count >= 10: break
			var tile := Tile.new()
			tile.card = card
			tile.images = images
			tile.custom_minimum_size = Vector2(140, 225)
			grid.add_child(tile)
			count += 1
	if not preview.get("warnings", []).is_empty():
		var warning := _label("These lines will not be imported:\n" + "\n".join(preview.warnings), 13, Color("ffb294"))
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(warning)
	body.add_child(_button("Import recognized cards" if not preview.get("warnings", []).is_empty() else "Use this deck", _apply_import, true))

func _apply_import() -> void:
	if preview_behavior == 0: _switch_to(_commit_import)
	else: _commit_import()

func _commit_import() -> void:
	if preview_behavior == 0:
		_load_deck(preview)
	else:
		_record()
		if preview_behavior == 2: draft.sections = preview.sections.duplicate(true)
		else:
			for section in preview.sections:
				if not draft.sections.has(section): draft.sections[section] = []
				for card in preview.sections[section]:
					var matching: Array = draft.sections[section].filter(func(c): return c.key == card.key)
					if matching.is_empty(): draft.sections[section].append(card.duplicate(true))
					else: matching[0].quantity += card.quantity
	dirty = true
	_changed()
	overlay.hide()
	_set_mode(false)
	_validate()

func _show_actions() -> void:
	var body := _dialog("DECK ACTIONS", 560, 420)
	body.add_child(_button("Create / import / duplicate…", _show_import, true))
	var copy := _button("Copy deck list to clipboard", func(): _request("export", {"deck": draft, "format": "text"}, {"clipboard": true}); overlay.hide())
	copy.disabled = draft.is_empty()
	body.add_child(copy)
	var export_button := _button("Export Forge deck file…", func(): _request("export", {"deck": draft}); overlay.hide())
	export_button.disabled = draft.is_empty()
	body.add_child(export_button)
	delete_button = _button("Delete deck…", _show_delete)
	delete_button.disabled = draft.get("id", "").is_empty() or draft.get("readOnly", false) or not online
	if draft.get("readOnly", false): delete_button.tooltip_text = "Forge precons are part of the installed game and cannot be deleted."
	body.add_child(delete_button)
	body.add_child(_label("Changes are written to your Forge library only when you save.", 12, P.MUTED))

func _show_delete() -> void:
	if busy or loading_deck or str(draft.get("id", "")).is_empty() or draft.get("readOnly", false): return
	var body := _dialog("DELETE DECK", 580, 330)
	var explanation := _label("Delete “%s” from your deck library?%s" % [draft.name, " Unsaved changes will also be discarded." if dirty else ""], 18)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(explanation)
	var delete_id: String = draft.id
	var delete_version: String = draft.version
	var keep := _button("Keep deck", func(): overlay.hide())
	body.add_child(keep)
	delete_button = _button("Delete deck", func():
		if busy: return
		busy = true
		delete_button.disabled = true
		keep.disabled = true
		_request("delete", {"id": delete_id, "version": delete_version})
		_controls(), true)
	body.add_child(delete_button)

func _show_card_search() -> void:
	if busy or loading_deck or draft.is_empty(): return
	var body := _dialog("ADD CARDS", 720, 620)
	card_search = preload("res://scripts/library/CardSearch.gd").new()
	card_search.api = api
	card_search.images = images
	card_search.ink = Color("304a55").lerp(Color("d5e6e3"), darkness)
	card_search.card_added.connect(func(card, section): _adjust(card, section, 1, true))
	card_search.closed.connect(func(): overlay.hide(); _refresh_cards())
	body.add_child(card_search)

func _inspect(card: Dictionary) -> void:
	if busy or loading_deck: return
	inspect_card = card
	var body := _dialog(card.name, 880, 730)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	body.add_child(row)
	var tile := Tile.new()
	tile.card = card
	tile.images = images
	tile.custom_minimum_size = Vector2(290, 438)
	row.add_child(tile)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	var type_line := _label(card.manaCost + "  ·  " + card.typeLine, 16, Color("dedfe2"))
	type_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(type_line)
	var rules := _label(card.text.replace("\\n", "\n"), 16)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(rules)
	details.add_child(_label(card.edition + " · #" + card.collectorNumber + " · " + card.rarity, 12, P.MUTED))
	var section := _option(["Main", "Commander", "Sideboard", "Avatar", "Planes", "Schemes", "Conspiracy", "Dungeon", "Attractions", "Contraptions", "Stickers"], func(_index): pass)
	var target: String = card.get("section", "Commander" if section_filter.text == "Commander" else "Main")
	for i in range(section.item_count):
		if section.get_item_text(i) == target: section.select(i)
	details.add_child(_label("Deck section", 12, P.MUTED))
	details.add_child(section)
	var add := _button("+ Add one to deck", func(): _adjust(card, section.text, 1), true)
	add.disabled = draft.is_empty() or not online
	details.add_child(add)
	if not catalog_mode:
		details.add_child(_button("− Remove one", func(): _adjust(card, card.get("section", "Main"), -1)))
		details.add_child(_button("Move to selected section", func():
			if section.text == card.get("section", "Main"): return
			_move_card(card, section.text)))
	var hint := _label("Choose a printing below to change this deck entry's artwork.", 12, P.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	_request_printings(card)

func _printing_choices(cards: Array) -> void:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 38
	for card in cards:
		option.add_item(card.edition + " · #" + card.collectorNumber)
		if card.key == inspect_card.key: option.select(option.item_count - 1)
	option.item_selected.connect(func(index):
		var printing: Dictionary = cards[index].duplicate(true)
		if not catalog_mode and not draft.is_empty():
			_record()
			var entries: Array = draft.sections[inspect_card.section]
			var existing: Array = entries.filter(func(c): return c.key == inspect_card.key)
			if not existing.is_empty():
				printing.quantity = existing[0].quantity
				entries.erase(existing[0])
				var duplicate: Array = entries.filter(func(c): return c.key == printing.key)
				if duplicate.is_empty(): entries.append(printing)
				else: duplicate[0].quantity += printing.quantity
			printing.section = inspect_card.section
			_changed(true, true)
		_inspect(printing))
	dialog_body.add_child(option)

func _adjust(card: Dictionary, section: String, delta: int, keep_open: bool = false) -> void:
	if draft.is_empty() or busy or loading_deck: return
	if section == "Commander" and delta > 0:
		_assign_commander(card)
		if not keep_open: overlay.hide()
		return
	_record()
	if not draft.sections.has(section): draft.sections[section] = []
	var entries: Array = draft.sections[section]
	var matching: Array = entries.filter(func(c): return c.key == card.key)
	if matching.is_empty() and delta > 0:
		var entry := card.duplicate(true)
		entry.quantity = delta
		entry.erase("section")
		entries.append(entry)
	elif not matching.is_empty():
		matching[0].quantity += delta
		if matching[0].quantity <= 0: entries.erase(matching[0])
	_changed()
	if not keep_open: overlay.hide()

func _move_card(card: Dictionary, section: String) -> void:
	if busy or loading_deck: return
	if section == "Commander":
		_assign_commander(card)
		overlay.hide()
		return
	_record()
	var entries: Array = draft.sections[card.section]
	var matching: Array = entries.filter(func(c): return c.key == card.key)
	if matching.is_empty(): return
	var entry: Dictionary = matching[0]
	entries.erase(entry)
	if not draft.sections.has(section): draft.sections[section] = []
	var duplicates: Array = draft.sections[section].filter(func(c): return c.key == entry.key)
	if duplicates.is_empty(): draft.sections[section].append(entry)
	else: duplicates[0].quantity += entry.quantity
	_changed()
	overlay.hide()

func _assign_commander(card: Dictionary, second: bool = false) -> void:
	if busy or loading_deck or draft.is_empty(): return
	var leaders: Array = draft.get("sections", {}).get("Commander", [])
	if leaders.any(func(value): return value.key == card.key) and (second or leaders.size() == 1): return
	_record()
	if not draft.sections.has("Commander"): draft.sections.Commander = []
	if not draft.sections.has("Main"): draft.sections.Main = []
	var entry := card.duplicate(true)
	entry.erase("section")
	entry.quantity = 1
	var source: String = card.get("section", "Main")
	if draft.sections.has(source):
		var matches: Array = draft.sections[source].filter(func(value): return value.key == card.key)
		if not matches.is_empty():
			matches[0].quantity -= 1
			if matches[0].quantity <= 0: draft.sections[source].erase(matches[0])
	if not second:
		for previous in draft.sections.Commander:
			var moved: Dictionary = previous.duplicate(true)
			moved.commander = false
			var existing: Array = draft.sections.Main.filter(func(value): return value.key == moved.key)
			if existing.is_empty(): draft.sections.Main.append(moved)
			else: existing[0].quantity += moved.quantity
		draft.sections.Commander = []
	if not draft.sections.Commander.any(func(value): return value.key == entry.key): draft.sections.Commander.append(entry)
	_changed()
	_validate()

func set_workspace_top(value: float) -> void:
	workspace_top = value
	if workspace != null: workspace.offset_top = value

func set_darkness(value: float) -> void:
	if is_equal_approx(styled_darkness, value): return
	styled_darkness = value
	darkness = value
	if carousel != null: carousel.darkness = value
	var ink := Color("304a55").lerp(Color("d5e6e3"), value)
	var muted := Color("58707a").lerp(Color("a5bdb8"), value)
	var fill := Color("e4e9ea").lerp(Color("3a4447"), value)
	var edge := Color("b4c1c7").lerp(Color("63787a"), value)
	theme.default_font = app_host.computer.get_theme_default_font() if app_host != null else SystemFont.new()
	theme.set_color("font_color", "Label", ink)
	theme.set_stylebox("panel", "PopupMenu", P.box(fill, edge, 8, 10))
	theme.set_color("font_color", "PopupMenu", ink)
	theme.set_color("font_hover_color", "PopupMenu", ink)
	theme.set_stylebox("hover", "PopupMenu", P.box(fill.lightened(0.15), edge, 4, 8))
	theme.set_stylebox("panel", "AcceptDialog", P.box(fill, edge, 8, 18))
	for kind in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme.set_stylebox(state, kind, P.box(fill.lightened(0.08) if state == "hover" else fill, edge, 5, 8))
			theme.set_color("font_color" if state == "normal" else "font_" + state + "_color", kind, ink)
	_style_workbench(self, ink, muted, fill, edge)
	validation_reason.add_theme_color_override("font_color", Color("8a651e").lerp(Color("e6c878"), value))

func _style_workbench(node: Node, ink: Color, muted: Color, fill: Color, edge: Color) -> void:
	if node == overlay or node is Window: return
	if node == validate_button or node == validation_reason: return
	if node is Tile:
		node.ink = ink
		node.queue_redraw()
		# Card artwork has its own rendering/theme; only the tile caption uses
		# the workbench palette. Avoid traversing every card's SubViewport.
		return
	if node is Label:
		node.add_theme_color_override("font_color", ink if node.get_theme_font_size("font_size") >= 17 else muted)
		node.add_theme_font_override("font", get_theme_default_font())
	elif node is Button:
		var accent: bool = node.get_meta("workbench_accent", false)
		if node in [deck_button, catalog_button]: accent = (node == catalog_button) == catalog_mode
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			node.add_theme_stylebox_override(state, P.box(Color("127d85") if accent else (fill.lightened(0.08) if state == "hover" else fill), edge, 5, 8))
			node.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", Color.WHITE if accent else ink)
		node.add_theme_font_override("font", get_theme_default_font())
	elif node is LineEdit:
		node.add_theme_font_override("font", get_theme_default_font())
		node.add_theme_color_override("font_color", ink)
		node.add_theme_color_override("font_placeholder_color", muted)
		node.add_theme_stylebox_override("normal", P.box(Color(fill, 0.75), edge, 5, 8))
		node.add_theme_stylebox_override("focus", P.box(fill, Color("479d99"), 5, 8))
	for child in node.get_children(): _style_workbench(child, ink, muted, fill, edge)

func _card_context(card: Dictionary) -> void:
	if busy or loading_deck or draft.is_empty(): return
	context_card = card.duplicate(true)
	context_menu.clear()
	context_menu.add_item("View card", 0)
	context_menu.add_item("Add a copy", 1)
	if not catalog_mode:
		context_menu.add_item("Remove one", 2)
		context_menu.add_item("Remove all copies", 3)
	context_menu.add_separator()
	context_menu.add_item("Change artwork...", 4)
	if not catalog_mode:
		context_menu.add_separator()
		context_menu.add_item("Set as commander", 5)
		context_menu.add_item("Add as second commander", 8)
		context_menu.add_item("Move to Main", 6)
		context_menu.add_item("Move to Sideboard", 7)
	context_menu.position = Vector2i(get_global_mouse_position())
	context_menu.popup()

func _card_action(action: int) -> void:
	var card := context_card.duplicate(true)
	if card.is_empty() or busy: return
	match action:
		0: _inspect(card)
		1: _adjust(card, card.get("section", "Main"), 1)
		2: _adjust(card, card.get("section", "Main"), -1)
		3: _adjust(card, card.get("section", "Main"), -int(card.get("quantity", 1)))
		4:
			inspect_card = card
			_dialog("Choose artwork / " + str(card.name), 920, 780)
			artwork_mode = true
			artwork_cards = []
			dialog_body.add_child(_label("Loading available artwork...", 14, P.MUTED))
			_request_printings(card, true)
		5, 6, 7:
			var section: String = ["Commander", "Main", "Sideboard"][action-5]
			if section == "Commander" or section != card.get("section", "Main"): _move_card(card, section)
		8:
			_assign_commander(card, true)

func _request_printings(card: Dictionary, gallery: bool = false) -> void:
	if printing_cache.has(card.name):
		if gallery:
			artwork_cards = printing_cache[card.name]
			artwork_page = 0
			_render_artwork()
		else: _printing_choices(printing_cache[card.name])
		return
	_request("printings", {"name": card.name}, {"key": card.key, "name": card.name, "art_gallery": gallery})

func _render_artwork() -> void:
	_clear(dialog_body)
	var grid := GridContainer.new()
	grid.columns = maxi(2, int((dialog.size.x-70)/180))
	dialog_body.add_child(grid)
	var per_page := grid.columns * clampi(int((dialog.size.y-160)/300), 1, 2)
	var visible_cards := artwork_cards.slice(artwork_page*per_page, (artwork_page+1)*per_page)
	for printing in visible_cards:
		var group := VBoxContainer.new()
		grid.add_child(group)
		var tile := Tile.new()
		tile.images = images
		tile.card = printing
		tile.custom_minimum_size = Vector2(164, 258)
		tile.ink = Color("304a55").lerp(Color("d5e6e3"), darkness)
		tile.chosen.connect(func(selected):
			if catalog_mode: _inspect(selected)
			else: _replace_printing(selected); overlay.hide())
		group.add_child(tile)
		group.add_child(_label(str(printing.edition) + " / #" + str(printing.collectorNumber), 12))
	images.prioritize(visible_cards)
	# Warm just the next page, after requesting everything currently on screen.
	for printing in artwork_cards.slice((artwork_page+1)*per_page, (artwork_page+2)*per_page):
		images.request_texture(printing)
	var pages := HBoxContainer.new()
	dialog_body.add_child(pages)
	var previous := _button("Previous", func(): artwork_page -= 1; _render_artwork())
	previous.disabled = artwork_page == 0
	pages.add_child(previous)
	pages.add_child(_label("%d / %d" % [artwork_page+1, maxi(1, ceili(float(artwork_cards.size())/per_page))]))
	var next := _button("Next", func(): artwork_page += 1; _render_artwork())
	next.disabled = (artwork_page+1)*per_page >= artwork_cards.size()
	pages.add_child(next)
	if not catalog_mode and not draft.is_empty():
		var all_copies := CheckBox.new()
		all_copies.text = "Apply to every copy of this card in the deck"
		all_copies.button_pressed = apply_art_to_all
		all_copies.toggled.connect(func(on): apply_art_to_all = on)
		pages.add_child(all_copies)

func _replace_printing(value: Dictionary) -> void:
	var printing := value.duplicate(true)
	if not catalog_mode and not draft.is_empty() and apply_art_to_all:
		var changed := false
		for section in draft.sections.keys():
			var entries: Array = draft.sections[section]
			var same: Array = entries.filter(func(card): return str(card.name) == str(inspect_card.name))
			if same.is_empty(): continue
			if not changed: _record()
			changed = true
			var total := 0
			for card in same:
				total += int(card.quantity)
				entries.erase(card)
			var copy: Dictionary = printing.duplicate(true)
			copy.quantity = total
			copy.section = section
			var merged: Array = entries.filter(func(card): return card.key == copy.key)
			if merged.is_empty(): entries.append(copy)
			else: merged[0].quantity += total
		if changed: _changed(true, true)
	elif not catalog_mode and not draft.is_empty():
		var entries: Array = draft.sections.get(inspect_card.get("section", "Main"), [])
		var existing: Array = entries.filter(func(card): return card.key == inspect_card.key)
		if existing.is_empty(): return
		_record()
		printing.quantity = existing[0].quantity
		entries.erase(existing[0])
		var duplicate: Array = entries.filter(func(card): return card.key == printing.key)
		if duplicate.is_empty(): entries.append(printing)
		else: duplicate[0].quantity += printing.quantity
		_changed(true, true)
	else: _inspect(printing)

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and overlay.visible and not busy: _cancel_switch(); overlay.hide(); get_viewport().set_input_as_handled()
		if event.ctrl_pressed and event.keycode == KEY_S and not save_button.disabled: _save(); get_viewport().set_input_as_handled()

func _close_requested() -> void:
	if busy: return
	if not dirty:
		get_tree().quit()
		return
	var confirm := ConfirmationDialog.new()
	confirm.title = "Unsaved deck changes"
	confirm.dialog_text = "Save your changes before closing the deck collection?"
	confirm.ok_button_text = "Discard and close"
	confirm.cancel_button_text = "Keep editing"
	confirm.add_button("Save and close", false, "save")
	confirm.confirmed.connect(func(): get_tree().quit())
	confirm.custom_action.connect(func(action):
		if action == "save" and not save_button.disabled:
			quit_after_save = true
			_save()
			confirm.queue_free())
	confirm.canceled.connect(confirm.queue_free)
	add_child(confirm)
	confirm.popup_centered()
