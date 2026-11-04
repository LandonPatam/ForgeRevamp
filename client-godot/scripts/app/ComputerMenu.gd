extends Control
signal commander_requested
signal editor_requested
signal home_requested
signal quit_requested
signal start_requested
signal settings_requested
signal deck_selected(index: int)
signal deck_inserted
signal zoom_started
signal resume_requested
signal end_game_requested
signal startup_pullback_started
## The shared carousel filter changed; `decks` now holds only the visible disks.
signal deck_filter_changed
const P = preload("res://scripts/ui/Palette.gd")
const World = preload("res://scripts/app/ComputerWorld.gd")
const Carousel = preload("res://scripts/app/DeckCarousel.gd")
const Loading = preload("res://scripts/app/LoadingProgress.gd")
const DISPLAY_SIZE := Vector2i(1024, 744)
## Full light/dark room fade; a reversal mid-fade takes only the remaining share.
const LIGHTING_SECONDS := 0.35
## Deck sources shown in the shared home/editor carousel.
const DECK_FILTERS := [["all", "ALL"], ["custom", "CUSTOM"], ["precon", "PRECONS"]]
const CRT_INK := Color("70d6bc")
const CRT_DARK := Color("061712")
const CRT_PANEL := Color("0b2320")
var images: Node
var world: Node3D
var world_view: SubViewport
var monitor_view: SubViewport
var monitor_root: PanelContainer
var monitor_body: VBoxContainer
var normal_body: VBoxContainer
var boot_body: VBoxContainer
var selected_name: Label
var selected_rules: Label
var status_label: Label
var start_button: Button
var settings_button: Button
var console: Control
var boot_content: VBoxContainer
var format_log: Control
var format_cleanup := Callable()
var format_info: Dictionary = {}
var format_generation := 0
var boot_log: Control
var boot_deck: Dictionary = {}
var boot_setup: Dictionary = {}
var boot_engine_ready := false
var inserting_session := false
var loading: Control
var shelf: Control
var tiles: Array = []
var decks: Array = []
var all_decks: Array = []
var deck_filter := "all"
## The filter saved for the next launch; a non-persisted change never leaks into it.
var saved_deck_filter := "all"
## Typed on the home screen into the CRT's search bar; narrows the carousel by
## deck or commander name. Cleared on entering the editor, never persisted.
var search_query := ""
var search_focused := false
var filter_buttons: Dictionary = {}
var selected_id := ""
var phase := "idle"
var inserted := false
var header: Control
var forge_badge: PanelContainer
var forge_star: Control
var editor_button: Button
var quit_button: Button
var monitor_hovered := false
var last_monitor_position := Vector2.ZERO
var atmosphere: ColorRect
var session_disk: Control
var light_switch: Button
var menu_frame: Control
var dark_mode := false
var darkness := 0.0
var lighting_animation: Tween
var editor_surface: Control
var editor_progress := 0.0
var editor_animation: Tween
var world_container: SubViewportContainer
var room_backdrop: ColorRect
const APPEARANCE_PATH := "user://menu-appearance.cfg"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	theme = P.make_theme()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono"])
	theme.default_font = font
	room_backdrop = ColorRect.new()
	room_backdrop.color = Color("d9dfe2")
	room_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(room_backdrop)
	var container := SubViewportContainer.new()
	world_container = container
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	world_view = SubViewport.new()
	world_view.own_world_3d = true
	world_view.msaa_3d = Viewport.MSAA_4X
	world_view.handle_input_locally = false
	container.add_child(world_view)
	world = World.new()
	world_view.add_child(world)
	world.disk_entering.connect(func():
		if phase == "inserting": _show_boot_log(inserting_session)
		elif phase == "formatting": _show_format_log())
	monitor_view = SubViewport.new()
	monitor_view.size = DISPLAY_SIZE
	monitor_view.disable_3d = true
	monitor_view.gui_embed_subwindows = true
	monitor_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(monitor_view)
	monitor_root = PanelContainer.new()
	monitor_root.size = DISPLAY_SIZE
	monitor_root.theme = _screen_theme(font)
	monitor_root.add_theme_stylebox_override("panel", P.box(CRT_DARK, Color.TRANSPARENT, 0, 0))
	monitor_view.add_child(monitor_root)
	monitor_body = VBoxContainer.new()
	monitor_body.add_theme_constant_override("separation", 13)
	monitor_root.add_child(monitor_body)
	world.set_display(monitor_view.get_texture())
	start_button = Button.new()
	start_button.name = "PhysicalPlayButton"
	start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	start_button.tooltip_text = "Play selected deck"
	start_button.z_index = 45
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		start_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	start_button.button_down.connect(func(): if phase == "idle" and not start_button.disabled: world.begin_key_press(true))
	start_button.button_up.connect(func(): world.end_key_press(true))
	start_button.pressed.connect(func():
		if phase == "idle": start_requested.emit())
	start_button.mouse_entered.connect(func(): if phase == "idle": world.set_key_hover(true, true))
	start_button.mouse_exited.connect(func(): world.set_key_hover(true, false))
	add_child(start_button)
	settings_button = Button.new()
	settings_button.name = "PhysicalSettingsButton"
	settings_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	settings_button.tooltip_text = "Commander match settings"
	settings_button.z_index = 45
	for state in ["normal", "hover", "pressed", "disabled", "focus"]: settings_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	settings_button.button_down.connect(func(): if phase == "idle" and not settings_button.disabled: world.begin_key_press(false))
	settings_button.button_up.connect(func(): world.end_key_press(false))
	settings_button.pressed.connect(func(): if phase == "idle": settings_requested.emit())
	settings_button.mouse_entered.connect(func(): if phase == "idle": world.set_key_hover(false, true))
	settings_button.mouse_exited.connect(func(): world.set_key_hover(false, false))
	add_child(settings_button)
	header = Control.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(header)
	var frame := preload("res://scripts/app/MenuFrame.gd").new()
	menu_frame = frame
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header.add_child(frame)
	forge_badge = PanelContainer.new()
	forge_badge.add_theme_stylebox_override("panel", P.box(Color("e4e9ea"), Color("b4c1c7"), 3, 3))
	forge_badge.mouse_filter = Control.MOUSE_FILTER_STOP
	var badge_row := HBoxContainer.new()
	badge_row.add_theme_constant_override("separation", 6)
	forge_star = Control.new()
	forge_star.custom_minimum_size = Vector2(14, 14)
	forge_star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	forge_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forge_star.draw.connect(func():
		# Align the vector star to the text's visible capitals, avoiding the
		# different baseline metrics of the font used for the star glyph.
		var center := forge_star.size * 0.5 + Vector2(0, -2)
		var points := PackedVector2Array()
		for point in [Vector2(0, -6), Vector2(1.8, -1.8), Vector2(6, 0), Vector2(1.8, 1.8), Vector2(0, 6), Vector2(-1.8, 1.8), Vector2(-6, 0), Vector2(-1.8, -1.8)]:
			points.append(center + point)
		forge_star.draw_colored_polygon(points, Color.WHITE))
	badge_row.add_child(forge_star)
	var forge_name := _outside_label("FORGE", 13)
	forge_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_row.add_child(forge_name)
	forge_badge.add_child(badge_row)
	header.add_child(forge_badge)
	editor_button = _outside_button("▧  DECK EDITOR", func():
		if editor_progress > 0.5: home_requested.emit()
		else: editor_requested.emit())
	header.add_child(editor_button)
	quit_button = _outside_button("→  QUIT", func(): quit_requested.emit())
	header.add_child(quit_button)
	for option in DECK_FILTERS:
		var filter_button := _outside_button(option[1], set_deck_filter.bind(option[0]))
		filter_button.tooltip_text = {"all": "Show every deck", "custom": "Show only your saved decks", "precon": "Show Forge's official Commander precons"}[option[0]]
		filter_buttons[option[0]] = filter_button
		header.add_child(filter_button)
	light_switch = preload("res://scripts/app/LightSwitch.gd").new()
	light_switch.pressed.connect(func():
		if phase == "idle": set_dark_mode(not dark_mode))
	header.add_child(light_switch)
	set_forge_connected(false)
	shelf = Carousel.new()
	shelf.images = images
	shelf.deck_selected.connect(func(index):
		if phase == "idle": deck_selected.emit(index))
	shelf.new_deck_requested.connect(func():
		if phase == "idle" and is_instance_valid(editor_surface): editor_surface.create_from_carousel())
	add_child(shelf)
	resized.connect(_layout)
	world_view.size_changed.connect(_position_play_button)
	gui_input.connect(_monitor_input)
	visibility_changed.connect(_sync_visibility)
	mouse_exited.connect(_clear_monitor_hover)
	header.mouse_entered.connect(_clear_monitor_hover)
	shelf.mouse_entered.connect(_clear_monitor_hover)
	atmosphere = ColorRect.new()
	atmosphere.name = "MenuAtmosphere"
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	atmosphere.z_index = 100
	var finish := ShaderMaterial.new()
	finish.shader = preload("res://scripts/app/MenuAtmosphere.gdshader")
	atmosphere.material = finish
	add_child(atmosphere)
	var appearance := ConfigFile.new()
	if appearance.load(APPEARANCE_PATH) == OK:
		dark_mode = bool(appearance.get_value("room", "dark_mode", false))
		var saved_filter := str(appearance.get_value("library", "filter", "all"))
		if filter_buttons.has(saved_filter):
			deck_filter = saved_filter
			saved_deck_filter = saved_filter
	set_dark_mode(dark_mode, false, false)
	_sync_visibility()
	_layout()

func set_dark_mode(enabled: bool, animated: bool = true, persist: bool = true) -> void:
	dark_mode = enabled
	light_switch.dark = enabled
	light_switch.tooltip_text = "Turn room lights on" if enabled else "Turn room lights off"
	if lighting_animation != null: lighting_animation.kill()
	# Restyling the card grid invalidates its theme/layout. Do it once per
	# switch, rather than rebuilding every card's theme on each tween frame.
	if is_instance_valid(editor_surface): editor_surface.set_darkness(1.0 if enabled else 0.0)
	if animated:
		var target := 1.0 if enabled else 0.0
		lighting_animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		lighting_animation.tween_method(_apply_darkness, darkness, target, maxf(0.1, LIGHTING_SECONDS * absf(target - darkness)))
	else: _apply_darkness(1.0 if enabled else 0.0)
	if persist:
		_save_appearance()

func _save_appearance() -> void:
	var appearance := ConfigFile.new()
	appearance.set_value("room", "dark_mode", dark_mode)
	appearance.set_value("library", "filter", saved_deck_filter)
	appearance.save(APPEARANCE_PATH)

func _apply_darkness(value: float) -> void:
	darkness = value
	room_backdrop.color = Color("d9dfe2").lerp(Color("111719"), value)
	world.set_room_darkness(value)
	light_switch.darkness = value
	menu_frame.darkness = value
	atmosphere.material.set_shader_parameter("darkness", value)
	if shelf != null: shelf.darkness = value
	for button in [editor_button, quit_button]:
		button.add_theme_color_override("font_color", Color("334d58").lerp(Color("b8cecb"), value))
		button.add_theme_color_override("font_hover_color", Color("203d48").lerp(Color("e2f2ef"), value))
		button.add_theme_color_override("font_pressed_color", Color("203d48").lerp(Color("e2f2ef"), value))
		button.add_theme_stylebox_override("normal", P.box(Color("e4e9ea").lerp(Color("3a4447"), value), Color("b4c1c7").lerp(Color("63787a"), value), 3, 6))
		button.add_theme_stylebox_override("hover", P.box(Color("f2f5f5").lerp(Color("4c5c5e"), value), Color("648b8a").lerp(Color("85aaa6"), value), 3, 6))
		button.add_theme_stylebox_override("pressed", P.box(Color("d2dfe0").lerp(Color("2d393c"), value), Color("648b8a").lerp(Color("85aaa6"), value), 3, 6))
	forge_badge.add_theme_stylebox_override("panel", P.box(Color("e4e9ea").lerp(Color("3a4447"), value), Color("b4c1c7").lerp(Color("63787a"), value), 3, 3))
	forge_badge.get_child(0).get_child(1).add_theme_color_override("font_color", Color("455f6a").lerp(Color("b8cecb"), value))
	_style_filters()

func _style_filters() -> void:
	var value := darkness
	for key in filter_buttons:
		var button: Button = filter_buttons[key]
		var active: bool = key == deck_filter
		var edge := Color("8a6ccf").lerp(Color("bd9bf2"), value) if active else Color("b4c1c7").lerp(Color("63787a"), value)
		var fill := Color("eceff6").lerp(Color("34364a"), value) if active else Color("e4e9ea").lerp(Color("3a4447"), value)
		button.add_theme_color_override("font_color", Color("4b3a78").lerp(Color("d8c8f7"), value) if active else Color("334d58").lerp(Color("b8cecb"), value))
		button.add_theme_color_override("font_hover_color", Color("203d48").lerp(Color("e2f2ef"), value))
		button.add_theme_color_override("font_pressed_color", Color("203d48").lerp(Color("e2f2ef"), value))
		button.add_theme_stylebox_override("normal", P.box(fill, edge, 3, 6))
		button.add_theme_stylebox_override("hover", P.box(Color("f2f5f5").lerp(Color("4c5c5e"), value), edge if active else Color("648b8a").lerp(Color("85aaa6"), value), 3, 6))
		button.add_theme_stylebox_override("pressed", P.box(Color("d2dfe0").lerp(Color("2d393c"), value), edge, 3, 6))

## Shows all decks, only saved (custom) decks, or only Forge's bundled precons.
func set_deck_filter(value: String, persist: bool = true) -> void:
	if value == deck_filter or not filter_buttons.has(value): return
	deck_filter = value
	_style_filters()
	if persist:
		saved_deck_filter = value
		_save_appearance()
	set_decks(all_decks, selected_id)
	deck_filter_changed.emit()

func deck_visible(deck: Dictionary) -> bool:
	if deck_filter != "all" and str(deck.get("source", "custom")) != deck_filter: return false
	if search_query.strip_edges().is_empty(): return true
	var haystack := (str(deck.get("name", "")) + " " + str(deck.get("cover", {}).get("name", ""))).to_lower()
	for word in search_query.to_lower().split(" ", false):
		if not haystack.contains(word): return false
	return true

func set_search_query(value: String) -> void:
	if value == search_query: return
	search_query = value
	set_decks(all_decks, selected_id)
	deck_filter_changed.emit()

func set_search_focused(value: bool) -> void:
	search_focused = value
	_update_search_display()

func _update_search_display() -> void:
	if is_instance_valid(console): console.set_search(search_query, search_focused, decks.size())

## Home-screen typing goes to the search bar. Handled before GUI focus so a
## space or letter never presses a header button that kept focus after a click.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or phase != "idle" or editor_progress > 0.01 or not is_visible_in_tree(): return
	if not is_instance_valid(console) or not console.is_visible_in_tree(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	var key := event as InputEventKey
	if key.keycode == KEY_ESCAPE and (search_focused or not search_query.is_empty()):
		search_focused = false
		set_search_query("")
		_update_search_display()
	elif key.keycode == KEY_BACKSPACE and not search_query.is_empty():
		search_focused = true
		set_search_query("" if key.ctrl_pressed else search_query.left(-1))
		_update_search_display()
	elif key.keycode in [KEY_ENTER, KEY_KP_ENTER] and search_focused:
		set_search_focused(false) # commit; the next Enter presses Play
	elif key.unicode >= 32 and not key.ctrl_pressed and not key.alt_pressed and not key.meta_pressed:
		if search_query.length() >= 40: return
		search_focused = true
		set_search_query(search_query + char(key.unicode))
		_update_search_display()
	else: return
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if atmosphere == null or world.camera == null or world_view.size.x <= 0 or world_view.size.y <= 0: return
	var upper: Vector2 = (world.camera.unproject_position(world.screen_point(Vector2.ZERO)) + world_container.position) / Vector2(world_view.size)
	var lower: Vector2 = (world.camera.unproject_position(world.screen_point(Vector2.ONE)) + world_container.position) / Vector2(world_view.size)
	atmosphere.material.set_shader_parameter("monitor_rect", Vector4(upper.x, upper.y, lower.x - upper.x, lower.y - upper.y))

func _screen_theme(font: Font) -> Theme:
	var result := Theme.new()
	var terminal_font := font.duplicate() as SystemFont
	terminal_font.font_weight = 600
	result.default_font = terminal_font
	result.default_font_size = 32
	result.set_color("font_color", "Label", CRT_INK)
	result.set_color("font_shadow_color", "Label", Color(0.12, 0.55, 0.49, 0.35))
	result.set_constant("shadow_offset_x", "Label", 1)
	result.set_constant("shadow_offset_y", "Label", 1)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		for kind in ["Button", "OptionButton"]:
			result.set_stylebox(state, kind, P.box(CRT_DARK if state != "hover" else CRT_PANEL, Color.TRANSPARENT, 0, 8))
			result.set_color("font_color" if state == "normal" else "font_" + state + "_color", kind, CRT_INK if state != "disabled" else Color("39756e"))
	result.set_stylebox("separator", "HSeparator", P.box(Color("2c8178"), Color.TRANSPARENT, 0, 0))
	return result

func _outside_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("455f6a"))
	return label

func _outside_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 26
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("334d58"))
	button.add_theme_stylebox_override("normal", P.box(Color("e4e9ea"), Color("b4c1c7"), 3, 6))
	button.add_theme_stylebox_override("hover", P.box(Color("f2f5f5"), Color("648b8a"), 3, 6))
	button.pressed.connect(func():
		if phase == "idle": action.call())
	return button

func set_forge_connected(connected: bool) -> void:
	forge_star.modulate = Color("458aa8") if connected else Color("9aa7aa")
	forge_badge.tooltip_text = "Forge connected and running" if connected else "Forge disconnected — waiting for connection"

func _screen_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _clear_screen() -> void:
	boot_log = null
	for child in monitor_body.get_children():
		monitor_body.remove_child(child)
		child.queue_free()
	normal_body = VBoxContainer.new()
	normal_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	monitor_body.add_child(normal_body)
	boot_body = VBoxContainer.new()
	boot_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	monitor_body.add_child(boot_body)
	var safe := MarginContainer.new()
	safe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]: safe.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]: safe.add_theme_constant_override("margin_" + side, 48)
	boot_body.add_child(safe)
	boot_content = VBoxContainer.new()
	boot_content.add_theme_constant_override("separation", 18)
	safe.add_child(boot_content)
	var brand := _screen_label("ForgeCheck / SYSTEM ACTIVITY", 30)
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	boot_content.add_child(brand)
	boot_body.hide()
	# Retain service status for diagnostics, without a second footer on the CRT.
	status_label = Label.new()
	monitor_body.add_child(status_label)
	status_label.hide()
	loading = null

func present_menu() -> void:
	present_commander()

func present_commander() -> void:
	reset_launch()
	_clear_screen()
	console = preload("res://scripts/app/DeckConsole.gd").new()
	normal_body.add_child(console)
	_update_search_display()

func render_selection(info: Dictionary, player_count: int = 3) -> void:
	if phase == "formatting": return
	if phase != "idle": reset_launch()
	var selected: Array = decks.filter(func(deck): return deck.id == selected_id)
	console.present(info, player_count, decks.is_empty(), str(selected[0].name) if not selected.is_empty() else "")

func set_console_status(message: String, connected: bool, lobby: String = "") -> void:
	if is_instance_valid(console): console.set_status(message, connected, lobby)

func show_loading() -> Control:
	normal_body.hide()
	boot_body.show()
	boot_content.get_parent().show()
	if is_instance_valid(boot_log):
		boot_log.stop()
		boot_log.hide()
	if loading == null:
		loading = Loading.new()
		loading.compact = true
		boot_content.add_child(loading)
		loading.heading.add_theme_font_size_override("font_size", 43)
		loading.detail.add_theme_font_size_override("font_size", 30)
		loading.elapsed.add_theme_font_size_override("font_size", 25)
		for label in [loading.detail, loading.elapsed]: label.add_theme_color_override("font_color", CRT_INK)
		loading.progress.add_theme_stylebox_override("background", P.box(CRT_PANEL, Color("285c55"), 0, 0))
		loading.progress.add_theme_stylebox_override("fill", P.box(Color("61cdbc"), Color.TRANSPARENT, 0, 0))
		loading.present("READING DECK…", "Preparing Commander and two AI opponents.\nYour game will open here when ready.", "game")
	return loading

func _show_boot_log(resuming: bool = false) -> void:
	normal_body.hide()
	boot_body.show()
	boot_content.get_parent().hide()
	if not is_instance_valid(boot_log):
		boot_log = preload("res://scripts/app/MatchBootLog.gd").new()
		boot_body.add_child(boot_log)
		boot_log.activity.connect(world.pulse_drive)
	world.drive_log_active = true
	boot_log.begin(boot_deck, boot_setup, resuming)
	if boot_engine_ready: boot_log.engine_ready()

func set_boot_engine_ready() -> void:
	boot_engine_ready = true
	if is_instance_valid(boot_log) and boot_log.active: boot_log.engine_ready()

func set_decks(value: Array, active_id: String) -> void:
	all_decks = value.duplicate(true)
	decks = all_decks.filter(deck_visible)
	selected_id = active_id
	shelf.set_decks(decks, active_id)
	tiles = shelf.tiles
	_update_search_display()
	_layout()

func select_id(id: String) -> void:
	selected_id = id
	shelf.select_id(id)

func _layout() -> void:
	if shelf == null: return
	forge_badge.position = Vector2(34, 13)
	forge_badge.size = Vector2(88, 26)
	editor_button.size = Vector2(148, 26)
	editor_button.position = Vector2((size.x - editor_button.size.x) * 0.5, 13)
	quit_button.size = Vector2(90, 26)
	quit_button.position = Vector2(size.x - quit_button.size.x - 34, 13)
	light_switch.position = Vector2(size.x - 244, 9)
	var filter_x := forge_badge.position.x + forge_badge.size.x + 12
	for option in DECK_FILTERS:
		var filter_button: Button = filter_buttons[option[0]]
		filter_button.size = Vector2(52 if option[0] == "all" else 82, 26)
		filter_button.position = Vector2(filter_x, 13)
		filter_x += filter_button.size.x + 4
	light_switch.size = Vector2(104, 34)
	var height := clampf(size.y * 0.38, 290, 390)
	var home_top := size.y-height-10
	var travel := (home_top-70)*editor_progress
	shelf.night_visibility = 1.0 - smoothstep(0.2, 0.85, editor_progress)
	# Clear the closer-framed case and its contact shadow above the editor.
	world_container.position.y = -travel-200*editor_progress
	if is_instance_valid(atmosphere):
		atmosphere.position.y = world_container.position.y
		atmosphere.material.set_shader_parameter("home_visibility",1.0-smoothstep(0.25,0.85,editor_progress))
		atmosphere.visible = editor_progress < 1.0
	shelf.position = Vector2(0, home_top-travel)
	shelf.minimum_disk_height = 210
	shelf.size = Vector2(size.x, height)
	if is_instance_valid(editor_surface):
		editor_surface.set_workspace_top(shelf.position.y+shelf.size.y+6)
		editor_surface.modulate.a = smoothstep(0.3, 0.85, editor_progress)
	if is_instance_valid(session_disk):
		var disk_size := clampf(size.y * 0.235, 180, 235)
		session_disk.position = Vector2(minf(size.x * 0.82 - disk_size * 0.5, size.x - disk_size - 24), size.y * 0.22-travel)
		session_disk.size = Vector2(disk_size, disk_size + 126)
		session_disk.modulate.a = 0.0 if phase == "formatting" else 1.0-editor_progress
	_position_play_button.call_deferred()

func _position_play_button() -> void:
	if start_button == null or phase != "idle": return
	start_button.visible = editor_progress < 0.01
	var bounds: Rect2 = world.play_button_rect()
	start_button.position = bounds.position
	start_button.size = bounds.size
	settings_button.visible = editor_progress < 0.01
	var settings_bounds: Rect2 = world.settings_button_rect()
	settings_button.position = settings_bounds.position
	settings_button.size = settings_bounds.size

func zoom_into_settings(texture: Texture2D) -> void:
	phase = "settings_transition"
	shelf.enabled = false
	start_button.hide()
	settings_button.hide()
	_clear_monitor_hover()
	normal_body.show()
	boot_body.hide()
	var fade := create_tween().set_parallel(true)
	fade.tween_property(header, "modulate:a", 0.0, 0.2)
	fade.tween_property(shelf, "modulate:a", 0.0, 0.2)
	if is_instance_valid(session_disk): fade.tween_property(session_disk, "modulate:a", 0.0, 0.2)
	fade.tween_property(atmosphere.material, "shader_parameter/strength", 0.0, 1.1)
	await world.zoom_into_settings(monitor_view.get_texture(), size, texture)
	phase = "settings"

func zoom_out_of_settings(texture: Texture2D) -> void:
	phase = "settings_exit"
	# Start pulling back immediately; retune to the console during the move.
	normal_body.show()
	boot_body.hide()
	await world.zoom_out_settings(texture, size, monitor_view.get_texture())

func set_editor_mode(enabled: bool) -> void:
	if enabled and (not search_query.is_empty() or search_focused):
		# The search bar lives on the home monitor; the editor shows every deck again.
		search_query = ""
		search_focused = false
		set_decks(all_decks, selected_id)
	phase = "editor_transition"
	shelf.enabled = false
	shelf.begin_editor_transition(enabled)
	start_button.hide()
	if editor_animation != null: editor_animation.kill()
	editor_animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	editor_animation.tween_method(func(value):
		editor_progress = value
		shelf.set_editor_transition_progress(value if enabled else 1.0 - value)
		_layout(), editor_progress, 1.0 if enabled else 0.0, 0.65)
	await editor_animation.finished
	shelf.finish_editor_transition()
	editor_button.text = "MAIN MENU" if enabled else "DECK EDITOR"
	shelf.enabled = not (enabled and is_instance_valid(editor_surface) and editor_surface.busy)
	phase = "idle"
	_position_play_button()

func scroll_by(amount: float) -> void:
	if phase != "idle": return
	shelf.step(1 if amount > 0 else -1)

func _monitor_input(event: InputEvent) -> void:
	if phase != "idle" or editor_progress > 0.01 or not event is InputEventMouse: return
	var uv: Vector2 = world.screen_uv(event.position)
	if uv.x < 0 or uv.y < 0 or uv.x > 1 or uv.y > 1:
		if monitor_hovered: monitor_view.notify_mouse_exited()
		monitor_hovered = false
		return
	if not monitor_hovered: monitor_view.notify_mouse_entered()
	monitor_hovered = true
	var forwarded: InputEvent = event.duplicate()
	forwarded.position = uv * Vector2(DISPLAY_SIZE)
	forwarded.global_position = forwarded.position
	if forwarded is InputEventMouseMotion: forwarded.relative = forwarded.position - last_monitor_position
	if forwarded is InputEventMouseButton and forwarded.pressed and forwarded.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(console) and console.is_visible_in_tree():
		var local: Vector2 = console.get_global_transform().affine_inverse() * forwarded.position
		set_search_focused(console.SEARCH_RECT.has_point(local * console.DESIGN_SIZE / console.size))
	last_monitor_position = forwarded.position
	monitor_view.push_input(forwarded, true)
	accept_event()

func monitor_point(control: Control) -> Vector2:
	var uv := control.get_global_rect().get_center() / Vector2(DISPLAY_SIZE)
	var point: Vector3 = world.screen_point(uv)
	return world.camera.unproject_position(point)

func begin_launch(deck: Dictionary, setup: Dictionary) -> void:
	if phase != "idle": return
	boot_deck = deck.duplicate(true)
	boot_setup = setup.duplicate(true)
	boot_engine_ready = false
	inserting_session = false
	phase = "pressing"
	shelf.enabled = false
	_clear_monitor_hover()
	inserted = false
	normal_body.show()
	boot_body.hide()
	await world.wait_for_key_feedback(true)
	if phase != "pressing": return
	phase = "inserting"
	var tile: Control = null
	for i in range(tiles.size()):
		if decks[i].id == selected_id: tile = tiles[i]; break
	var rect := Rect2(size.x * 0.5 - 40, size.y - 160, 80, 112)
	var texture: Texture2D
	var tilt := 0.0
	var color := Color("c9a34e")
	if tile != null:
		rect = tile.cover_rect()
		rect.position -= global_position
		tile.ensure_face()
		texture = tile.cover.texture
		tilt = tile.rotation
		color = tile.shell_color
		tile.hide_cover(true)
	if not await world.insert_deck(texture, rect, tilt, color): return
	if phase != "inserting": return
	phase = "loading"
	inserted = true
	var fade := create_tween()
	fade.tween_property(shelf, "modulate:a", 0.0, 0.25)
	deck_inserted.emit()

func zoom_into_game(texture: Texture2D) -> void:
	phase = "completing_load"
	shelf.enabled = false
	if is_instance_valid(boot_log):
		boot_log.table_ready()
		if not await boot_log.wait_for_finish() or phase != "completing_load": return
		boot_log.stop()
	world.drive_log_active = false
	world.drive_activity = 0
	world.working = false
	phase = "materializing"
	await world.materialize_board(texture)
	phase = "zooming"
	zoom_started.emit()
	var fade := create_tween().set_parallel(true)
	fade.tween_property(header, "modulate:a", 0.0, 0.2)
	fade.tween_property(shelf, "modulate:a", 0.0, 0.2)
	if is_instance_valid(session_disk): fade.tween_property(session_disk, "modulate:a", 0.0, 0.2)
	fade.tween_property(atmosphere.material, "shader_parameter/strength", 0.0, 1.1)
	await world.zoom_into(texture, size)
	phase = "playing"

func reset_launch() -> void:
	if phase == "formatting": finish_session_format()
	if is_instance_valid(boot_log): boot_log.stop()
	phase = "idle"
	shelf.enabled = true
	inserted = false
	world.reset_view()
	world.set_display(monitor_view.get_texture())
	header.modulate.a = 1.0
	shelf.modulate.a = 1.0
	(atmosphere.material as ShaderMaterial).set_shader_parameter("strength", 1.0)
	for tile in tiles: tile.hide_cover(false)
	if normal_body != null: normal_body.show()
	if boot_body != null: boot_body.hide()

func prepare_startup_pullback(texture: Texture2D) -> void:
	phase = "startup_pullback"
	shelf.enabled = false
	start_button.disabled = true
	world.set_play_enabled(false)
	header.modulate.a = 0.0
	shelf.modulate.a = 0.0
	atmosphere.material.set_shader_parameter("strength", 0.0)
	world.prepare_startup_pullback(texture, size)

func pullback_startup(texture: Texture2D) -> void:
	startup_pullback_started.emit()
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(atmosphere.material, "shader_parameter/strength", 1.0, 1.65)
	reveal.tween_property(header, "modulate:a", 1.0, 0.5).set_delay(0.9)
	reveal.tween_property(shelf, "modulate:a", 1.0, 0.55).set_delay(1.0)
	await world.pullback_startup()
	phase = "startup_console"
	await world.change_channel(monitor_view.get_texture())
	phase = "idle"
	shelf.enabled = true

func return_to_carousel(texture: Texture2D, resume_info: Dictionary = {}, erasing: bool = false) -> void:
	phase = "returning"
	shelf.enabled = false
	# Resuming inserts the session disk, so the deck's carousel copy is already
	# visible. Reserve its center slot again before either return animation.
	for tile in tiles: tile.hide_cover(tile.deck.id == selected_id)
	start_button.disabled = true
	world.set_play_enabled(false)
	show()
	if not resume_info.is_empty():
		set_session_info(resume_info)
		session_disk.modulate.a = 0.0
		session_disk.disk.hide_cover(true)
	await world.zoom_out(texture, size)
	shelf.cursor = shelf.target
	shelf._arrange()
	var fade := create_tween().set_parallel(true)
	fade.tween_property(header, "modulate:a", 1.0, 0.25)
	fade.tween_property(shelf, "modulate:a", 1.0, 0.25)
	fade.tween_property(atmosphere.material, "shader_parameter/strength", 1.0, 0.4)
	if erasing:
		# Erase plays on the CRT only: no floppy is ejected.
		for tile in tiles: tile.hide_cover(false)
		await world.change_channel(monitor_view.get_texture())
		return
	for tile in tiles:
		if tile.deck.id != selected_id: continue
		tile.ensure_face()
		world.set_disk_face(tile.cover.texture, tile.shell_color)
		await world.eject_deck(tile.cover_rect(), tile.rotation)
		tile.hide_cover(false)
		break
	if normal_body != null: normal_body.show()
	if boot_body != null: boot_body.hide()
	if not resume_info.is_empty() and is_instance_valid(session_disk):
		phase = "session_ejecting"
		world.set_disk_face(session_disk.disk.cover.texture, session_disk.disk.shell_color)
		await world.eject_deck(session_disk.disk.cover_rect(), 0.0, monitor_view.get_texture())
		session_disk.disk.hide_cover(false)
		session_disk.modulate.a = 1.0
	else:
		phase = "channel_change"
		await world.change_channel(monitor_view.get_texture())
	phase = "idle"

func _show_format_log() -> void:
	normal_body.hide()
	boot_body.show()
	boot_content.get_parent().hide()
	if is_instance_valid(boot_log): boot_log.hide()
	format_log = preload("res://scripts/app/FormatLog.gd").new()
	boot_body.add_child(format_log)
	format_log.activity.connect(world.pulse_drive)
	world.drive_log_active = true
	world.drive_format_active = true
	format_log.begin_format(format_info, format_cleanup)

func format_session_disk(stopped: Callable) -> void:
	if not is_instance_valid(session_disk): return
	format_generation += 1
	var generation := format_generation
	phase = "formatting"
	format_info = session_disk.info.duplicate(true)
	format_cleanup = stopped
	shelf.enabled = false
	for button in [start_button, settings_button, editor_button, light_switch]: button.disabled = true
	world.set_play_enabled(false)
	session_disk.resume_button.disabled = true
	session_disk.end_button.disabled = true
	# No floppy moves: the session disk fades and the wipe runs on the CRT.
	create_tween().tween_property(session_disk, "modulate:a", 0.0, 0.18)
	_show_format_log()
	if generation != format_generation: return
	if phase == "formatting" and is_instance_valid(format_log):
		# Wait in the owning menu, so freeing an interrupted log cannot strand
		# the application coroutine on a signal from a deleted object.
		while generation == format_generation and is_instance_valid(format_log) and format_log.active and (not format_log.complete or format_log.value < 1.0 or format_log.ready_age < 0.65):
			await get_tree().process_frame
	if generation != format_generation: return
	finish_session_format()

func finish_session_format() -> void:
	# Also used by reset_launch: interruption never leaves a face or amber LED.
	format_generation += 1
	if is_instance_valid(format_log):
		format_log.stop()
		format_log.queue_free()
	format_log = null
	format_info.clear()
	format_cleanup = Callable()
	world.drive_format_active = false
	world.drive_log_active = false
	world.drive_activity = 0.0
	world.working = false
	world.disk.hide()
	world._set_label_erase(0.0)
	world.disk_face.material_override = world.disk_night_material if darkness > 0.0 else world.disk_day_material
	set_session_info({})
	if normal_body != null: normal_body.show()
	if boot_body != null: boot_body.hide()
	for button in [settings_button, editor_button, light_switch]: button.disabled = false
	shelf.enabled = true
	phase = "idle"

func set_session_info(info: Dictionary) -> void:
	if info.is_empty():
		if is_instance_valid(session_disk):
			remove_child(session_disk)
			session_disk.queue_free()
		session_disk = null
		return
	if not is_instance_valid(session_disk):
		session_disk = preload("res://scripts/app/SessionDisk.gd").new()
		session_disk.images = images
		session_disk.info = info
		session_disk.z_index = 40
		session_disk.resume_requested.connect(func():
			if phase == "idle": resume_requested.emit())
		session_disk.end_requested.connect(func():
			if phase == "idle": end_game_requested.emit())
		add_child(session_disk)
	session_disk.update_info(info)
	_layout()

func insert_session_disk() -> void:
	phase = "inserting"
	inserting_session = true
	shelf.enabled = false
	var source: Control = session_disk.disk
	var rect: Rect2 = source.cover_rect()
	source.hide_cover(true)
	session_disk.modulate.a = 0.0
	normal_body.show()
	boot_body.hide()
	await world.insert_deck(source.cover.texture, rect, 0.0, source.shell_color)
	inserted = true
	phase = "loading"


func _sync_visibility() -> void:
	var active := is_visible_in_tree()
	world_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	monitor_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	world.set_process(active)
	if not active: _clear_monitor_hover()

func _clear_monitor_hover() -> void:
	if monitor_hovered:
		monitor_view.notify_mouse_exited()
		monitor_hovered = false

func _unhandled_key_input(event: InputEvent) -> void:
	if phase != "idle" or not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and editor_progress < 0.01 and not start_button.disabled:
			start_button.pressed.emit()
			accept_event()
			return
		if event.keycode in [KEY_LEFT, KEY_RIGHT]:
			shelf.step(1 if event.keycode == KEY_RIGHT else -1)
			accept_event()
			return
	if editor_progress < 0.01 and monitor_view.gui_get_focus_owner() != null:
		monitor_view.push_input(event, true)
		accept_event()
