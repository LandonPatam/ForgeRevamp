extends Control
const P = preload("res://scripts/ui/Palette.gd")
const Backdrop = preload("res://scripts/ui/TableBackdrop.gd")
const Api = preload("res://scripts/library/LibraryClient.gd")
const Images = preload("res://scripts/library/LibraryImages.gd")
const Tile = preload("res://scripts/library/LibraryCard.gd")
const Computer = preload("res://scripts/app/ComputerMenu.gd")
const Startup = preload("res://scripts/app/StartupScreen.gd")
const Bundled = preload("res://scripts/app/BundledService.gd")
const EditorScene = preload("res://scenes/DeckCollection.tscn")
var api: Node
var images: Node
var client_owner := ""
var launch_key := ""
var session := ""
var match_pid := 0
var view := "menu"
var online := false
var busy := false
var decks: Array = []
var selected_id := ""
var selected_deck: Dictionary = {}
var requests: Dictionary = {}
var deck_request := -1
var status_pending := false
var content: Control
var menu_panel: PanelContainer
var menu_body: VBoxContainer
var status_label: Label
var start_button: Button
var confirm: Control
var editor: Control
var game: Control
var status_timer: Timer
var checks: RefCounted
var quit_after_stop := false
var ending_session := false
var end_cleanup_done := false
var end_visual_done := false
var status_message := ""
var startup_file := ""
var bundled: RefCounted # the service started by an exported build; null in development
var startup_done := false
var startup_finishing := false
var open_editor_after_load := false
var startup_timer: Timer
var startup_progress: Control
var computer: Control
var pending_game_url := ""
var transition_viewport: SubViewport
var parked := false
var match_deck: Dictionary = {}
var parked_poll := 0.0
var match_keys: Dictionary = {}
var artwork_session := ""
var last_editor_setup_ms := 0.0
var match_preferences: Dictionary = {}
var bot_deck_catalog: Dictionary = {}
var match_settings: Control
var settings_viewport: SubViewport
var net: Node
## This game is someone else's: its engine runs on the host, so this app starts and stops nothing.
var remote_game := false
var remote_token := ""
var remote_end_pending := ""
var remote_store = preload("res://scripts/app/RemoteSession.gd").new()
var remote_resume: Dictionary = {}
## Hosting a table with joined players: ending it ends it for them too.
var online_table := false

func _process(delta: float) -> void:
	if ending_session:
		# Reconcile a slow/lost stop acknowledgment without recreating its disk
		# or replaying Stop. The menu remains usable after the visual timeout.
		parked_poll += delta
		if end_visual_done and parked_poll > 1.0:
			parked_poll = 0.0
			if online: _poll_match()
		return
	if game == null or not parked: return
	# The hidden scene cannot receive input; its existing connection still pumps.
	game.adapter.poll(delta)
	parked_poll += delta
	if parked_poll > 1.0:
		parked_poll = 0.0
		if not busy: computer.set_session_info(_session_info())
		if online and not busy: _poll_match()

func _session_info() -> Dictionary:
	if game == null: return remote_resume.get("info", {}).duplicate(true)
	var state: Dictionary = game.snapshot
	return {"session": session, "name": match_deck.get("name", "Commander"), "turn": state.get("game", {}).get("turn", 1), "phase": state.get("game", {}).get("phase", ""), "life": state.players[0].life if not state.get("players", []).is_empty() else 40, "decision": state.get("prompt", {}).get("message", "Resume the same live game")}

func _ready() -> void:
	# Keep the existing explicit match, mock and visual-test entry points working.
	for arg in OS.get_cmdline_user_args():
		if arg in ["--smoke", "--live-check", "--mock"] or arg.begins_with("--live=") or arg.begins_with("--visual-checks=") or arg.begins_with("--capture="):
			get_tree().change_scene_to_file.call_deferred("res://scenes/Main.tscn")
			return
	theme = P.popup_theme()
	theme.default_font = P.make_theme().default_font
	client_owner = Crypto.new().generate_random_bytes(16).hex_encode()
	match_preferences = preload("res://scripts/app/MatchPreferences.gd").read()
	var backdrop := Backdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	api = Api.new()
	images = Images.new()
	images.api = api
	var library_url_given := false
	var service_port := 7778
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--library-url="):
			api.url = arg.trim_prefix("--library-url=")
			library_url_given = true
		if arg.begins_with("--service-port="): service_port = int(arg.trim_prefix("--service-port="))
		if arg == "--app-check": images.network_enabled = false
		if arg.begins_with("--startup-status="): startup_file = arg.trim_prefix("--startup-status=")
		if arg == "--open-decks": open_editor_after_load = true
		if arg.begins_with("--library-fixture=") and "--app-check" in OS.get_cmdline_user_args():
			remote_store.path = arg.trim_prefix("--library-fixture=").path_join("online-session.cfg")
	_restore_remote_session()
	if not library_url_given and Bundled.available():
		bundled = Bundled.new()
		api.url = "ws://127.0.0.1:%d/ws" % service_port
		if bundled.start(service_port): startup_file = bundled.status_file
	api.connected.connect(func():
		online = true
		_request("list")
		if not launch_key.is_empty(): _poll_match()
		_update_status())
	api.disconnected.connect(func():
		online = false
		status_pending = false
		net.library_lost()
		_update_status())
	api.response.connect(_response)
	api.failed.connect(_failed)
	add_child(api)
	add_child(images)
	net = preload("res://scripts/app/OnlineSession.gd").new()
	net.api = api
	net.changed.connect(_net_changed)
	net.notice.connect(func(text): status_message = text; _update_status())
	net.match_started.connect(_begin_remote_match)
	add_child(net)
	status_timer = Timer.new()
	status_timer.wait_time = 0.6
	status_timer.timeout.connect(_poll_match)
	add_child(status_timer)
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_request_quit)
	_show_startup()
	if bundled != null and not bundled.error.is_empty(): _startup_error(bundled.error)
	startup_timer = Timer.new()
	startup_timer.wait_time = 0.25
	startup_timer.timeout.connect(_poll_startup)
	add_child(startup_timer)
	startup_timer.start()
	_poll_startup()
	for arg in OS.get_cmdline_user_args():
		if arg == "--app-check":
			checks = load("res://tests/ApplicationIntegration.gd").new()
			checks.run.call_deferred(self)

func _show_startup() -> void:
	view = "loading"
	startup_progress = Startup.new()
	content.add_child(startup_progress)
	startup_progress.quit_requested.connect(_request_quit)

func _poll_startup() -> void:
	if startup_done or startup_finishing: return
	if not startup_file.is_empty() and FileAccess.file_exists(startup_file):
		var status = JSON.parse_string(FileAccess.get_file_as_string(startup_file))
		if status is Dictionary:
			startup_progress.present(status.get("title", "Starting Forge"), status.get("detail", "Preparing the game library."), status.get("stage", "starting"))
			if status.get("stage", "") == "failed":
				startup_timer.stop()
				return
	if bundled != null and not online and not bundled.running():
		_startup_error("The Forge service stopped before it was ready. Its log is at " + bundled.log_path())
		return
	if online: startup_progress.present("Reading saved Commander decks", "Client connection established. Reading the deck library.", "online")

func _finish_startup() -> void:
	if startup_finishing: return
	startup_finishing = true
	startup_timer.stop()
	var verified: bool = await startup_progress.complete()
	if not verified or not online:
		startup_finishing = false
		_startup_error("The Forge connection was lost during startup. Relaunch to reconnect.")
		return
	# Build the menu behind the still-visible verification screen, then move that
	# same animated screen into the monitor without exposing an unrendered frame.
	_prepare_menu()
	content.move_child(computer, 0)
	view = "startup_transition"
	busy = true
	var cover := TextureRect.new()
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if DisplayServer.get_name() != "headless":
		cover.texture = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
	content.add_child(cover)
	var startup_view := SubViewport.new()
	startup_view.size = Vector2i(size)
	startup_view.disable_3d = true
	startup_view.gui_disable_input = true
	startup_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(startup_view)
	startup_progress.reparent(startup_view, false)
	startup_progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	startup_progress.size = size
	await get_tree().process_frame
	await get_tree().process_frame
	computer.prepare_startup_pullback(startup_view.get_texture())
	await get_tree().process_frame
	await get_tree().process_frame
	cover.hide()
	await computer.pullback_startup(startup_view.get_texture())
	startup_progress.reparent(content, false)
	startup_progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	startup_progress.position = Vector2.ZERO
	startup_view.queue_free()
	cover.queue_free()
	busy = false
	startup_finishing = false
	if not online or startup_progress.failed:
		computer.hide()
		view = "loading"
		_startup_error("The Forge connection was lost during startup. Relaunch to reconnect.")
		return
	startup_done = true
	startup_progress.hide()
	startup_progress.process_mode = Node.PROCESS_MODE_DISABLED
	view = "menu"
	_render_deck()
	_update_status()
	if open_editor_after_load: open_editor()

func _startup_error(message: String) -> void:
	startup_progress.present("Forge could not start", message, "failed")
	startup_timer.stop()

func _label(text: String, font_size: int = 16, color: Color = P.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font_size >= 20: label.add_theme_font_override("font", P.display_font())
	return label

func _button(text: String, action: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	P.style_menu_button(button, primary)
	button.pressed.connect(action)
	return button

func _clear_menu() -> void:
	if menu_panel != null:
		content.remove_child(menu_panel)
		menu_panel.queue_free()
	menu_panel = PanelContainer.new()
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu_panel.offset_left = -460
	menu_panel.offset_right = 460
	menu_panel.offset_top = -340
	menu_panel.offset_bottom = 340
	P.style_popup(menu_panel, 32)
	content.add_child(menu_panel)
	menu_body = VBoxContainer.new()
	menu_body.add_theme_constant_override("separation", 16)
	menu_panel.add_child(menu_body)
	status_label = null
	start_button = null

func show_menu() -> void:
	if busy or (game != null and not parked) or not startup_done: return
	if view == "editor" and computer != null:
		busy = true
		editor.close_transient_ui()
		await computer.set_editor_mode(false)
		busy = false
	_prepare_menu()
	if online: _request("list")

func _prepare_menu() -> void:
	view = "menu"
	status_message = ""
	if editor != null: editor.hide()
	_ensure_computer()
	computer.present_menu()
	status_label = computer.status_label
	start_button = computer.start_button
	computer.set_decks(decks, selected_id)
	if selected_id.is_empty() and not computer.decks.is_empty(): selected_id = computer.decks[0].id
	_fill_decks()
	_update_status()

func show_commander() -> void:
	if busy or (game != null and not parked) or not startup_done: return
	view = "commander"
	status_message = ""
	if editor != null: editor.hide()
	_ensure_computer()
	computer.present_commander()
	start_button = computer.start_button
	status_label = computer.status_label
	computer.set_decks(decks, selected_id)
	_fill_decks()
	if online: _request("list")
	_update_status()

func _ensure_computer() -> void:
	if menu_panel != null: menu_panel.hide()
	if computer == null:
		computer = Computer.new()
		computer.images = images
		computer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		computer.commander_requested.connect(show_commander)
		computer.editor_requested.connect(open_editor)
		computer.home_requested.connect(show_menu)
		computer.quit_requested.connect(_request_quit)
		computer.start_requested.connect(start_game)
		computer.settings_requested.connect(open_match_settings)
		computer.resume_requested.connect(resume_game)
		computer.end_game_requested.connect(request_end_game)
		computer.deck_filter_changed.connect(_deck_filter_changed)
		computer.deck_selected.connect(func(index):
			if view == "editor":
				editor.select_deck(computer.decks[index].id)
				return
			if view == "menu": show_commander()
			_select_deck(index))
		computer.deck_inserted.connect(func():
			if not pending_game_url.is_empty(): _show_game(pending_game_url))
		content.add_child(computer)
		if not remote_resume.is_empty(): computer.set_session_info(_session_info())
	computer.show()

func _fill_decks() -> void:
	if computer != null and view in ["menu", "commander"]: computer.set_decks(decks, selected_id)
	if view not in ["menu", "commander"]: return
	# Indexes refer to the carousel's visible (filtered) disks.
	var visible: Array = computer.decks
	if not visible.is_empty():
		var selected := 0
		for index in range(visible.size()):
			if visible[index].id == selected_id: selected = index
		_select_deck(selected)
	else:
		selected_deck.clear()
		_render_deck()

func _deck_filter_changed() -> void:
	if view in ["menu", "commander"]: _fill_decks()
	elif view == "editor" and editor != null and not computer.decks.is_empty():
		var current: String = editor.draft.get("id", "")
		if not computer.decks.any(func(deck): return deck.id == current): editor.select_deck(computer.decks[0].id)

func _select_deck(index: int) -> void:
	if busy or index < 0 or index >= computer.decks.size(): return
	selected_id = computer.decks[index].id
	computer.select_id(selected_id)
	if (net.is_joined() or net.is_hosting()) and computer.decks[index].get("legal", true): net.set_deck(selected_id)
	selected_deck.clear()
	deck_request = _request("open", {"id": selected_id})
	_render_deck()
	_update_status()

func _render_deck() -> void:
	if view not in ["menu", "commander"] or computer == null or not is_instance_valid(computer.console): return
	if busy and (ending_session or not launch_key.is_empty() or computer.phase == "play_press"):
		return
	computer.render_selection(selected_deck, _table_size())

func open_editor() -> void:
	if busy or (game != null and not parked) or not startup_done: return
	view = "editor"
	if menu_panel != null: menu_panel.hide()
	busy = true
	# Move the existing room on the very first click frame. Cold editor setup
	# and card loading happen after the movement, never before it.
	if editor != null: editor.show()
	await computer.set_editor_mode(true)
	var setup_start := Time.get_ticks_usec()
	if editor == null:
		editor = EditorScene.instantiate()
		editor.app_host = self
		editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		computer.add_child(editor)
		computer.editor_surface = editor
	else:
		if editor.online: editor._request("list")
	if editor.dirty: editor._render_decks()
	elif not editor.draft.is_empty() and editor.draft.get("id", "") != selected_id: editor.select_deck(selected_id)
	computer._layout()
	last_editor_setup_ms = (Time.get_ticks_usec()-setup_start)/1000.0
	busy = false

func sync_editor_library(value: Array, active_id: String) -> void:
	if view != "editor": return
	decks = value.duplicate(true)
	if not active_id.is_empty() and active_id != computer.shelf.CREATE_ID: selected_id = active_id
	computer.set_decks(decks, active_id if not active_id.is_empty() else selected_id)

func open_match_settings() -> void:
	if busy or not startup_done or view not in ["menu", "commander"]: return
	busy = true
	view = "settings_transition"
	computer.phase = "settings_press"
	computer.shelf.enabled = false
	await computer.world.click_settings()
	settings_viewport = SubViewport.new()
	settings_viewport.disable_3d = true
	settings_viewport.size = Vector2i(size)
	settings_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	settings_viewport.gui_disable_input = true
	add_child(settings_viewport)
	match_settings = preload("res://scripts/app/MatchSettings.gd").new()
	match_settings.value = match_preferences.duplicate(true)
	match_settings.api = api
	match_settings.deck_catalog = bot_deck_catalog
	match_settings.decks = decks.duplicate(true)
	match_settings.selected_deck = selected_id
	match_settings.net = net
	match_settings.game_running = game != null or parked
	match_settings.size = size
	match_settings.saved.connect(func(value):
		if preload("res://scripts/app/MatchPreferences.gd").save(value) != OK:
			match_settings.error_label.text = "Could not save match settings. Try again."
			return
		match_preferences = value.duplicate(true)
		net.configure(match_preferences)
		close_match_settings())
	match_settings.canceled.connect(func():
		net.configure(match_preferences)
		close_match_settings())
	settings_viewport.add_child(match_settings)
	# The key has already rebounded and rendered; retuning overlaps the zoom.
	computer.zoom_into_settings(settings_viewport.get_texture())
	await computer.world.animation.finished
	match_settings.reparent(content, false)
	match_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_viewport.queue_free()
	settings_viewport = null
	computer.hide()
	view = "settings"
	busy = false

func close_match_settings() -> void:
	if busy or view != "settings": return
	busy = true
	view = "settings_transition"
	for child in match_settings.get_children():
		if child is Window: child.hide()
	settings_viewport = SubViewport.new()
	settings_viewport.disable_3d = true
	settings_viewport.size = Vector2i(size)
	settings_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	settings_viewport.gui_disable_input = true
	add_child(settings_viewport)
	match_settings.reparent(settings_viewport, false)
	match_settings.size = size
	await get_tree().process_frame
	await get_tree().process_frame
	computer.world.prepare_settings_zoom_out(settings_viewport.get_texture(), size)
	computer.show()
	await computer.zoom_out_of_settings(settings_viewport.get_texture())
	computer.reset_launch()
	if is_instance_valid(computer.session_disk): computer.session_disk.modulate.a = 1.0
	settings_viewport.queue_free()
	settings_viewport = null
	match_settings = null
	busy = false
	show_menu()

func _table_size() -> int:
	if net.is_joined(): return net.roster.size()
	return 1 + match_preferences.bots.size() + net.players().size()

func _net_changed() -> void:
	_update_status()
	_render_deck()
	if net.all_ready(): _launch_ready_online_match.call_deferred()

func _launch_ready_online_match() -> void:
	if not net.all_ready() or busy or game != null or parked or view != "menu": return
	if not selected_deck.get("legal", false): return
	if match_preferences.bots.is_empty() and net.players().is_empty(): return
	_launch_game(false)

## Everyone is ready. Bring this app back to the computer, then run the normal disk insertion.
func _begin_remote_match(url: String, token: String) -> void:
	# Save as soon as the lobby hands off the seat, including crashes during insertion.
	remote_resume = {"url": url, "token": token, "session_id": "", "deck": {"id": net.deck_id, "name": selected_deck.get("name", "Online game")}, "info": {"name": selected_deck.get("name", "Online game"), "reconnect": true, "decision": "Rejoin while the host is still running. Disconnected seats are held for up to five minutes."}}
	_save_remote_session()
	while busy: await get_tree().process_frame
	if view == "settings": close_match_settings()
	elif view == "editor": show_menu()
	await get_tree().process_frame
	while busy: await get_tree().process_frame
	var seated: Array = decks.filter(func(deck): return deck.id == net.deck_id)
	if not seated.is_empty() and selected_id != net.deck_id:
		selected_id = net.deck_id
		computer.select_id(selected_id)
	remote_game = true
	remote_token = token
	busy = true
	computer.shelf.enabled = false
	match_deck = selected_deck.duplicate(true) if selected_deck.get("id", "") == net.deck_id else (seated[0].duplicate(true) if not seated.is_empty() else selected_deck.duplicate(true))
	status_message = ""
	launch_key = Crypto.new().generate_random_bytes(16).hex_encode()
	artwork_session = ""
	images.warm_deck(match_deck)
	computer.phase = "idle"
	computer.begin_launch(match_deck, {"human": match_preferences.human, "bots": _last_roster_others()})
	computer.set_boot_engine_ready()
	pending_game_url = url
	if computer.inserted: _show_game(url)
	_update_status()

## OnlineSession has already left the lobby when a match starts; it keeps the final roster for the boot log.
func _last_roster_others() -> Array:
	return net.last_roster.filter(func(entry): return int(entry.get("id", -1)) != net.last_you or entry.get("kind", "") != "player")

func start_game() -> void:
	if busy or game != null or parked or not online or not selected_deck.get("legal", false): return
	if is_instance_valid(confirm) and confirm.visible: return
	if net.is_joined() or net.is_hosting():
		if net.is_ready() or net.deck_request >= 0: return
		busy = true
		computer.phase = "play_press"
		await computer.world.click_play()
		computer.phase = "idle"
		busy = false
		net.set_ready(true)
		_update_status()
		return
	_launch_game()

func _launch_game(press_key := true) -> void:
	if match_preferences.bots.is_empty():
		if net.is_hosting() and net.players().is_empty():
			status_message = "Add a bot or wait for a player to join."
			_update_status()
			return
		if not net.is_hosting(): match_preferences.bots.append(preload("res://scripts/app/MatchPreferences.gd").bot(1))
	online_table = net.is_hosting() and not net.players().is_empty()
	busy = true
	computer.phase = "play_press"
	computer.shelf.enabled = false
	if press_key: await computer.world.click_play()
	match_deck = selected_deck.duplicate(true)
	status_message = ""
	launch_key = Crypto.new().generate_random_bytes(16).hex_encode()
	artwork_session = ""
	images.warm_deck(match_deck)
	_render_deck()
	computer.phase = "idle" # The completed PLAY rebound can now hand off to insertion.
	computer.begin_launch(match_deck, match_preferences)
	_request("match.start", {"id": selected_id, "launchKey": launch_key, "setup": match_preferences})
	_update_status()

func _request(operation: String, arguments: Dictionary = {}) -> int:
	var args := arguments.duplicate(true)
	if operation.begins_with("match."): args.owner = client_owner
	var id: int = api.request(operation, args)
	requests[id] = operation
	if operation.begins_with("match."): match_keys[id] = launch_key
	return id

func _response(id: int, operation: String, result: Dictionary) -> void:
	var owned := requests.has(id)
	var expected: String = match_keys.get(id, launch_key)
	requests.erase(id)
	match_keys.erase(id)
	if operation.begins_with("match.") and not owned: return
	if operation.begins_with("match.") and expected != launch_key: return
	match operation:
		"list":
			decks = result.decks
			if not startup_done:
				_finish_startup()
			else: _fill_decks()
		"open":
			if id != deck_request or result.get("id", "") != selected_id: return
			selected_deck = result
			_render_deck()
		"match.start", "match.status", "match.artworkSeen":
			status_pending = false
			_match_state(result)
		"match.stop":
			status_pending = false
			status_timer.stop()
			_clear_ended_match()
			end_cleanup_done = true
			if quit_after_stop: get_tree().quit()
			elif not ending_session or end_visual_done:
				ending_session = false
				busy = false
				show_menu()
	_update_status()

func _failed(id: int, message: String) -> void:
	if not requests.has(id): return
	var operation: String = requests[id]
	var expected: String = match_keys.get(id, launch_key)
	requests.erase(id)
	match_keys.erase(id)
	if operation.begins_with("match.") and expected != launch_key: return
	if operation == "match.artworkSeen": return
	if operation == "match.status": status_pending = false
	if operation == "match.start" and online:
		# A timeout may have happened after Forge started. Query instead of replaying Start.
		status_timer.start()
		_poll_match()
	elif operation == "match.stop":
		quit_after_stop = false
		if ending_session:
			push_warning("FORMAT A: stop acknowledgment failed: " + message)
			# Keep ownership until status confirms the engine is gone. Never
			# replay the destructive request or revive a consumed session disk.
		else:
			busy = false
			if game != null: game.process_mode = Node.PROCESS_MODE_INHERIT
	else: busy = false
	_update_status()
	status_message = message
	if not startup_done: _startup_error(message)
	_update_status()
	if game != null: game._notify(message)

func _match_state(state: Dictionary) -> void:
	var kind: String = state.get("state", "none")
	if ending_session:
		if kind in ["failed", "none", "stopped"]:
			_clear_ended_match()
			end_cleanup_done = true
			if end_visual_done:
				ending_session = false
				busy = false
				show_menu()
		return
	if state.has("session"): session = state.session
	if state.has("pid"): match_pid = int(state.pid)
	if state.has("artwork") and artwork_session != session:
		artwork_session = session
		images.warm_deck(state.artwork)
		_request("match.artworkSeen", {"session": session})
	if kind == "starting":
		busy = true
		status_timer.start()
	elif kind == "ready":
		status_timer.stop()
		computer.set_boot_engine_ready()
		if game == null:
			busy = true
			pending_game_url = state.url
			if computer.inserted: _show_game(state.url)
	elif kind in ["failed", "none", "stopped"]:
		if game == null:
			computer.reset_launch()
		busy = false
		status_timer.stop()
		launch_key = ""
		status_message = state.get("error", status_message if not status_message.is_empty() else "No game is running. You can start a new Commander game.")
		if parked and not busy and game != null:
			content.remove_child(game)
			game.queue_free()
			game = null
			parked = false
			computer.set_session_info({})
		_render_deck()

func _poll_match() -> void:
	if not online or status_pending or remote_game: return
	status_pending = true
	_request("match.status")

func _show_game(url: String, resuming := false) -> void:
	if game != null: return
	game = load("res://scenes/Main.tscn").instantiate()
	game.app_host = self
	game.live = true
	game.adapter = load("res://scripts/bridge/LiveAdapter.gd").new()
	game.adapter.url = url
	if remote_game:
		game.adapter.seat_token = remote_token
		game.adapter.expected_session = remote_resume.get("session_id", "")
		game.adapter.state_changed.connect(_remember_remote_snapshot)
		game.adapter.session_ended.connect(_remote_session_ended)
	await _reveal_game(resuming)

func _save_remote_session() -> void:
	if remote_store.save(remote_resume) != OK:
		push_warning("Could not save the online reconnect details.")

func _restore_remote_session() -> void:
	remote_resume = remote_store.read()
	if remote_resume.is_empty(): return
	remote_game = true
	remote_token = remote_resume.token
	match_deck = remote_resume.get("deck", {}).duplicate(true)
	parked = true
	if is_instance_valid(computer): computer.set_session_info(_session_info())

func _remember_remote_snapshot(state: Dictionary) -> void:
	if not remote_game or remote_resume.is_empty() or not state.get("connectionReady", false): return
	if state.get("game", {}).get("gameOver", false):
		remote_store.clear()
		return
	var info := {"name": match_deck.get("name", "Online game"), "turn": state.get("game", {}).get("turn", 1), "phase": state.get("game", {}).get("phase", ""), "life": state.players[0].life if not state.get("players", []).is_empty() else 40, "reconnect": true, "decision": "Rejoin while the host is still running. Disconnected seats are held for up to five minutes."}
	var identity: String = state.get("sessionId", "")
	if remote_resume.get("info", {}) == info and remote_resume.get("session_id", "") == identity: return
	remote_resume.info = info
	remote_resume.session_id = identity
	remote_resume.deck = {"id": match_deck.get("id", ""), "name": match_deck.get("name", "Online game")}
	_save_remote_session()

func _table_can_reveal(snapshot: Dictionary, resuming: bool) -> bool:
	if snapshot.get("players", []).size() < 2 or not snapshot.get("connectionReady", false): return false
	if snapshot.get("tableReady", false): return true
	# At an online table the first choice can be another person's, and they may take a while.
	# Forge's "Waiting for..." message proves the game has begun, so show the table meanwhile.
	if (remote_game or online_table) and not str(snapshot.get("prompt", {}).get("message", "")).is_empty(): return true
	# Forge prepares and shuffles all libraries before its first player/hand
	# choice. An initial locked/empty snapshot only proves the socket exists.
	return resuming or not snapshot.get("asks", []).is_empty() or snapshot.get("prompt", {}).get("inputKind", "") not in ["", "InputLockUI"]

func _reveal_game(resuming: bool) -> void:
	view = "transition"
	if menu_panel != null: menu_panel.hide()
	if editor != null: editor.hide()
	computer.show()
	game.set_transition_preview(true)
	game.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	game.size = size
	transition_viewport = SubViewport.new()
	transition_viewport.disable_3d = true
	transition_viewport.size = Vector2i(size)
	transition_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	transition_viewport.gui_disable_input = true
	add_child(transition_viewport)
	if game.get_parent() == null:
		transition_viewport.add_child(game)
		game.library_return_button = game._terminal_button("Main menu", request_return_to_menu)
		game.rail.add_child(game.library_return_button)
		game.rail.move_child(game.library_return_button, 0)
		var end_button: Button = game._terminal_button("End game", request_end_game)
		game.rail.add_child(end_button)
		game.rail.move_child(end_button, 1)
	else: game.reparent(transition_viewport, false)
	game.process_mode = Node.PROCESS_MODE_INHERIT
	game.show()
	await get_tree().process_frame
	await get_tree().process_frame
	if resuming: await computer.insert_session_disk()
	# Wait for the existing adapter's first real table snapshot before revealing it.
	# Startup player choices belong on the table; don't wait for them to resolve.
	var ready_deadline := Time.get_ticks_msec() + 180000
	while is_instance_valid(game) and not _table_can_reveal(game.snapshot, resuming):
		if not remote_end_pending.is_empty():
			busy = false
			return
		if game.snapshot.get("players", []).size() >= 2: computer.boot_log.players_ready(game.snapshot.players)
		await get_tree().create_timer(0.05).timeout
		if Time.get_ticks_msec() > ready_deadline:
			computer.boot_log.fail("TABLE CONNECTION TIMED OUT")
			busy = false
			return
	if not is_instance_valid(game): return
	computer.boot_log.engine_ready()
	computer.boot_log.players_ready(game.snapshot.players)
	if not resuming and game.snapshot.get("prompt", {}).get("inputKind", "") in ["", "InputLockUI"] and not game.snapshot.get("asks", []).is_empty():
		# Forge can pause during zone preparation to warn about an AI deck.
		# Reveal that required response; don't claim the shuffle has finished.
		computer.boot_log.rows[5] = "AWAITING PLAYER INPUT"
	computer.zoom_started.connect(game.begin_transition_zoom, CONNECT_ONE_SHOT)
	await computer.zoom_into_game(transition_viewport.get_texture())
	game.reparent(content, false)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.position = Vector2.ZERO
	game._layout_board.call_deferred()
	computer.hide()
	if resuming: computer.set_session_info({})
	transition_viewport.queue_free()
	transition_viewport = null
	pending_game_url = ""
	var reveal_blocker := Control.new()
	reveal_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reveal_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	reveal_blocker.z_index = 500
	content.add_child(reveal_blocker)
	await game.fade_in_game_ui()
	reveal_blocker.queue_free()
	view = "game"
	busy = false

func request_return_to_menu() -> void:
	if busy or game == null or (is_instance_valid(confirm) and confirm.visible): return
	confirm = preload("res://scripts/app/GameConfirm.gd").new()
	confirm.title = "Return to main menu?"
	confirm.dialog_text = "Your Commander game will stay running. Use its session disk to resume when you are ready."
	confirm.ok_button_text = "Main menu"
	confirm.cancel_button_text = "Keep playing"
	confirm.confirmed.connect(func(): confirm.hide(); confirm.queue_free(); request_leave_game())
	confirm.canceled.connect(func(): confirm.hide(); confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()

func request_leave_game() -> void:
	if busy or game == null: return
	busy = true
	parked = true
	images.clear_match_focus()
	parked_poll = 0.0
	view = "transition"
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var frame: Texture2D = GradientTexture2D.new()
	if DisplayServer.get_name() != "headless":
		# The confirmation is hidden, but the viewport still contains the previous
		# rendered frame until drawing completes. Capture the uncovered table.
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		if pixels != null and not pixels.is_empty(): frame = ImageTexture.create_from_image(pixels)
	game.hide()
	if match_deck.has("id"):
		selected_id = match_deck.id
		computer.select_id(selected_id)
	await computer.return_to_carousel(frame, _session_info())
	busy = false
	show_menu()

func resume_game() -> void:
	if busy or ending_session or not parked: return
	if game == null and remote_resume.is_empty(): return
	busy = true
	parked = false
	if game == null:
		await _show_game(remote_resume.url, true)
		return
	await _reveal_game(true)

func request_end_game() -> void:
	if busy or ending_session or (game == null and remote_resume.is_empty()): return
	if is_instance_valid(confirm) and confirm.visible: return
	confirm = preload("res://scripts/app/GameConfirm.gd").new()
	confirm.title = "Leave online game?" if remote_game else "End Commander game?"
	confirm.dialog_text = "You will concede and the others will play on without you." if remote_game else ("This ends the game for everyone at your table." if online_table else "End this game and remove its session disk?")
	confirm.ok_button_text = "Leave game" if remote_game else "End game"
	confirm.cancel_button_text = "Keep playing"
	if game == null:
		confirm.title = "Forget online session?"
		confirm.dialog_text = "Remove this saved reconnect? The host may keep waiting until your seat times out."
		confirm.ok_button_text = "Forget session"
	confirm.confirmed.connect(func():
		confirm.hide()
		confirm.queue_free()
		if game == null: _forget_remote_session()
		else: _end_confirmed_session())
	confirm.canceled.connect(func(): confirm.hide(); confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()

## A won game continues straight into the end-of-game wipe, without the confirmation.
func end_after_victory() -> void:
	if busy or ending_session or game == null: return
	_end_confirmed_session()

func _clear_ended_match() -> void:
	if remote_game:
		remote_store.clear()
		remote_resume.clear()
	if is_instance_valid(images): images.clear_match_focus()
	# Engine acknowledgment owns cleanup, never a presentation coroutine.
	if is_instance_valid(game):
		game.get_parent().remove_child(game)
		game.queue_free()
	game = null
	if is_instance_valid(transition_viewport): transition_viewport.queue_free()
	transition_viewport = null
	parked = false
	match_deck.clear()
	session = ""
	launch_key = ""
	match_pid = 0
	remote_game = false
	remote_token = ""
	remote_end_pending = ""
	online_table = false
	if not ending_session: computer.set_session_info({})

func _forget_remote_session() -> void:
	busy = true
	ending_session = true
	_clear_ended_match()
	await computer.format_session_disk(func(): return true)
	ending_session = false
	busy = false
	show_menu()

func _remote_session_ended(message: String) -> void:
	if not remote_game or ending_session: return
	remote_store.clear()
	status_message = message
	remote_end_pending = message
	# Allow an insertion/zoom already in progress to release its scene safely.
	while busy: await get_tree().process_frame
	if not remote_game or game == null or ending_session: return
	if is_instance_valid(confirm):
		confirm.hide()
		confirm.queue_free()
	await _end_confirmed_session()
	status_message = message
	_update_status()

func _end_confirmed_session() -> void:
	busy = true
	ending_session = true
	end_cleanup_done = false
	end_visual_done = false
	status_timer.stop()
	var info := _session_info()
	var from_table := not parked
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var frame: Texture2D = GradientTexture2D.new()
	if from_table and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var pixels := get_viewport().get_texture().get_image()
		if pixels != null and not pixels.is_empty(): frame = ImageTexture.create_from_image(pixels)
	game.hide()
	view = "transition"
	var deck_id_for_return: String = str(match_deck.get("id", selected_id))
	# Stop exactly once, concurrently with the visual. Data above is frozen.
	if remote_game:
		# The engine is the host's. Give up the seat; there is no stop to wait for.
		game.adapter.leave_table()
		_clear_ended_match()
		end_cleanup_done = true
	else: _request("match.stop", {"session": session})
	_update_status()
	if from_table:
		computer.select_id(deck_id_for_return)
		await computer.return_to_carousel(frame, info, true)
	await computer.format_session_disk(func(): return end_cleanup_done)
	# A timeout only releases the visual; a late acknowledgment still cleans up.
	end_visual_done = true
	ending_session = not end_cleanup_done
	busy = false
	parked = game != null
	view = "menu"
	show_menu()
	if not end_cleanup_done: status_message = "Engine cleanup pending. The session disk has been erased."
	_update_status()

func _update_status() -> void:
	if is_instance_valid(computer): computer.set_forge_connected(online)
	if view == "loading": return
	if start_button != null:
		start_button.disabled = busy or game != null or parked or not online or not selected_deck.get("legal", false) or ((net.is_joined() or net.is_hosting()) and (net.is_ready() or net.deck_request >= 0))
		start_button.text = ""
		start_button.tooltip_text = "Starting game" if busy else ("Play selected deck" if not start_button.disabled else "Select a valid saved Commander deck to play")
		if net.is_joined() or net.is_hosting(): start_button.tooltip_text = "Ready - waiting for the other players" if net.is_ready() else "Press PLAY to ready up"
		computer.world.set_play_enabled(not start_button.disabled)
		if ending_session and end_visual_done: start_button.tooltip_text = "Waiting for the previous engine to stop"
		elif parked: start_button.tooltip_text = "Resume or end the live game using its session disk first"
	if computer != null:
		var lobby := ""
		if net.is_joined() or net.is_hosting(): lobby = "[READY] WAITING FOR PLAYERS" if net.is_ready() else "[NET] PRESS PLAY TO READY"
		computer.set_console_status(status_message, online, lobby)
	if status_label != null:
		status_label.text = "Starting your Commander game…" if busy else (status_message if not status_message.is_empty() else ("Ready" if online else "Connecting to Forge…"))
		if ending_session and end_visual_done: status_label.text = "ENGINE CLEANUP PENDING"
		elif parked and not busy: status_label.text = "LIVE GAME SET ASIDE - SELECT SESSION DISK"
		elif (net.is_joined() or net.is_hosting()) and not busy: status_label.text = "READY - WAITING FOR ALL PLAYERS" if net.is_ready() else "ONLINE LOBBY - PRESS PLAY TO READY UP"

func _request_quit() -> void:
	if busy: return
	if is_instance_valid(confirm) and confirm.visible: return
	var unsaved: bool = editor != null and editor.dirty
	if game == null and not unsaved:
		get_tree().quit()
		return
	confirm = preload("res://scripts/app/GameConfirm.gd").new()
	confirm.title = "Quit Forge?"
	confirm.dialog_text = ("There are unsaved deck edits. Quit discards those changes.\n" if unsaved else "") + (("Quitting concedes your seat in this online game." if remote_game else ("Quitting ends the game for everyone at your table." if online_table else "Quitting ends your current game.")) if game != null else "")
	confirm.ok_button_text = "Quit"
	confirm.cancel_button_text = "Keep open"
	confirm.confirmed.connect(func():
		confirm.hide()
		if remote_game and game != null:
			remote_store.clear()
			game.adapter.leave_table()
			get_tree().quit()
			return
		if game != null and online:
			busy = true
			quit_after_stop = true
			_request("match.stop", {"session": session})
		else: get_tree().quit()
		confirm.queue_free())
	confirm.canceled.connect(func(): confirm.hide(); confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()
