extends RefCounted
const LibraryTile = preload("res://scripts/library/LibraryCard.gd")
const CoinTossDialog = preload("res://scripts/ui/CoinTossPanel.gd")
var app: Control
var active_scale: float = preload("res://scripts/app/DisplayPreferences.gd").current()
var deadline := 0
var capture_directory := "res://artifacts"

func until(condition: Callable, message: String) -> bool:
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return true
		await app.get_tree().create_timer(0.1).timeout
	push_error("UI scale check timed out: " + message)
	app.get_tree().quit(1)
	return false

func check(value: bool, message: String) -> bool:
	if value: return true
	push_error(message)
	app.get_tree().quit(1)
	return false

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	app.get_window().grab_focus()
	await app.get_tree().process_frame
	RenderingServer.force_draw()
	app.get_viewport().get_texture().get_image().save_png(capture_directory.path_join("ui-scale-%d-%s.png" % [roundi(active_scale * 100), name]))

func click(surface: Control, button: Control, factor: float = 0.0) -> void:
	if button is BaseButton:
		if not await until(func(): return not button.disabled, "button becomes enabled: " + button.text): return
	app.get_window().grab_focus()
	var point := surface.global_position + button.get_global_rect().get_center() * (active_scale if factor == 0 else factor)
	app.get_viewport().warp_mouse(point)
	await app.get_tree().create_timer(0.15).timeout
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await app.get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await app.get_tree().process_frame
	event.pressed = false
	event.button_mask = 0
	Input.parse_input_event(event)
	await app.get_tree().process_frame

func run(root: Control) -> void:
	app = root
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-scale-capture="): capture_directory = argument.trim_prefix("--ui-scale-capture=")
	var progress := Timer.new()
	progress.wait_time = 5.0
	app.add_child(progress)
	progress.timeout.connect(func(): print("UI SCALE STATE: ", app.view, " / ", app.computer.phase if app.computer != null else "startup"))
	progress.timeout.connect(func(): RenderingServer.force_draw())
	progress.start()
	deadline = Time.get_ticks_msec() + 240000
	if not await until(func(): return app.startup_done and not app.busy and app.selected_deck.get("legal", false), "startup"): return
	app.computer.set_deck_filter("custom", false)
	if not await until(func(): return app.selected_deck.get("id", "") == "Scale.dck" and app.selected_deck.get("legal", false), "fixture selection"): return
	if not await preload("res://tests/ScaledSurfaceChecks.gd").new().run(app): return
	if "--artwork-only" in OS.get_cmdline_user_args():
		await app.open_editor()
		if not await until(func(): return not app.editor.draft.is_empty() and app.editor.card_grid.get_child_count() > 0, "editor artwork fixture"): return
		for dimensions in [Vector2i(3200, 2000), Vector2i(1600, 1000)]:
			app.get_window().size = dimensions
			app.get_window().position = Vector2i.ZERO
			await app.get_tree().create_timer(0.4).timeout
			if not await _artwork_gallery_check(): return
		print("PASS: scaled editor/game artwork mouse input")
		app.get_tree().quit()
		return
	var home_size: Vector2i = app.computer.world_view.size
	await app.open_match_settings()
	if not await until(func(): return app.view == "settings" and not app.busy, "PC cog settings zoom"): return
	# Windows may fit the native window to odd pixel dimensions; logical viewports
	# use whole pixels, so a half pixel rounds down rather than changing the scale.
	if not check(app.match_settings.get_viewport_rect().size.is_equal_approx((app.size / active_scale).floor()), "PC settings use the selected scale: viewport=%s app=%s surface=%s" % [app.match_settings.get_viewport_rect().size, app.size, app.settings_surface.size]): return
	if not check(app.settings_surface.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and not app.settings_surface.render_when_hidden, "Visible settings render continuously after the CRT zoom"): return
	await capture("settings")
	await click(app.settings_surface, app.match_settings.names[0])
	if not check(app.match_settings.names[0].has_focus(), "Scaled settings name field receives input"): return
	await click(app.settings_surface, app.match_settings.portrait_buttons[0])
	if not await until(func(): return is_instance_valid(app.match_settings.portrait_dialog) and app.match_settings.portrait_dialog.visible, "scaled portrait dialog"): return
	await capture("settings-portrait")
	app.match_settings.portrait_dialog.hide()
	await click(app.settings_surface, app.match_settings.server_field)
	if not check(app.match_settings.server_field.has_focus(), "Scaled online server field receives input"): return
	app.get_window().size = Vector2i(1600, 1000)
	await app.get_tree().create_timer(0.5).timeout
	await capture("settings-small")
	app.get_window().size = home_size
	await app.get_tree().create_timer(0.5).timeout
	await click(app.settings_surface, app.match_settings.save_button)
	if not await until(func(): return app.view == "menu" and not app.busy, "settings Save and Return input"): return
	print("UI SCALE: PC settings, portrait, online input and return passed")
	print("UI SCALE: opening editor")
	await app.open_editor()
	print("UI SCALE: editor opened ", app.editor.get_viewport_rect())
	if not check(app.editor.get_viewport_rect().size.is_equal_approx((app.editor_surface.size / active_scale).floor()), "Editor gets the selected logical viewport size"): return
	if not await until(func(): return not app.editor.draft.is_empty() and app.editor.card_grid.get_child_count() > 0, "editor deck"): return
	if not check(app.editor_surface.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "The visible editor keeps every animation frame"): return
	print("UI SCALE: editor deck loaded")
	await capture("editor-before-input")
	if not await _artwork_gallery_check(): return

	deadline = Time.get_ticks_msec() + 15000
	await click(app.editor_surface, app.editor.catalog_button)
	if not await until(func(): return is_instance_valid(app.editor.card_search) and app.editor.overlay.visible, "scaled Add Cards input"): return
	await capture("card-search")
	# The selected floppy overlaps this part of the dialog. Compare the final
	# window against the editor texture to catch cross-viewport occlusion.
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		var sample := Vector2i(app.editor.card_search.query.get_global_rect().get_center() * active_scale)
		var actual: Color = app.get_viewport().get_texture().get_image().get_pixelv(sample)
		var expected: Color = app.editor_surface.viewport.get_texture().get_image().get_pixelv(sample)
		if not check(Vector3(actual.r, actual.g, actual.b).distance_to(Vector3(expected.r, expected.g, expected.b)) < 0.03, "Add Cards draws above the selected floppy"): return
	await click(app.editor_surface, app.editor.card_search.query)
	if not check(app.editor.card_search.query.has_focus(), "Add Cards search receives clicks over the floppy"): return
	app.editor.close_transient_ui()
	await click(app.editor_surface, app.editor.deck_button)
	if not await until(func(): return not app.editor.catalog_mode, "scaled deck-button input"): return
	await capture("editor")
	app.editor._show_import()
	await app.get_tree().process_frame
	await capture("import")
	app.editor.close_transient_ui()
	app.get_window().size = Vector2i(1600, 1000)
	await app.get_tree().create_timer(0.5).timeout
	if not check(app.editor.get_viewport_rect().size == (Vector2(1600, 1000) / active_scale).floor(), "Resizing preserves the selected editor scale"): return
	if not check(app.editor.size == app.editor.get_viewport_rect().size, "Resized editor content fills its logical viewport"): return
	await capture("editor-small")
	deadline = Time.get_ticks_msec() + 20000
	if not await _artwork_input_check(): return
	app.get_window().size = home_size
	await app.get_tree().create_timer(0.5).timeout
	print("UI SCALE: editor input and dialogs passed")
	await click(app, app.computer.editor_button, 1.0)
	if not await until(func(): return app.view == "menu" and not app.busy, "editor Main Menu input"): return
	if not check(not app.editor_surface.visible and app.computer.world_view.size == home_size, "Returning home hides the editor surface and preserves computer size"): return
	if not check(app.editor_surface.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Returning home suspends the hidden editor renderer"): return
	app.match_preferences = {"human": {"name": "Scale check", "avatar": 0}, "bots": [{"name": "Scale bot", "avatar": 1, "mode": "saved", "deckId": app.selected_id}]}
	deadline = Time.get_ticks_msec() + 180000
	print("UI SCALE: starting match")
	if not await until(func(): return app.selected_deck.get("legal", false) and not app.busy, "home deck readiness"): return
	app.start_game()
	if not await until(func(): return app.view == "game" and not app.busy, "real match reveal"): return
	if not check(app.game.get_viewport_rect().size.is_equal_approx((app.game_surface.size / active_scale).floor()), "Battlefield gets the selected logical viewport size"): return
	if not check(app.game_surface.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and not app.game_surface.render_when_hidden, "The revealed table resumes continuous drawing after its live CRT preview"): return
	await capture("opening-hand")
	var opening_deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < opening_deadline:
		if app.game.modal.visible and app.game.modal_panel is CoinTossDialog:
			await app.get_tree().create_timer(0.1).timeout
			continue
		if app.game.StartingPlayerDialog.needs_selection(app.game.snapshot):
			await click(app.game_surface, app.game.modal_panel.buttons[0])
		elif app.game.opening_hand.visible and not app.game.opening_hand.keep_button.disabled:
			await click(app.game_surface, app.game.opening_hand.keep_button)
		elif not app.game.opening_hand.visible and not app.game.modal.visible:
			break
		await app.get_tree().create_timer(0.4).timeout
	if not check(not app.game.opening_hand.visible and not app.game.modal.visible, "Required startup choices complete through scaled controls"): return
	await capture("game")
	await click(app.game_surface, app.game.library_return_button)
	if not await until(func(): return is_instance_valid(app.confirm) and app.confirm.visible, "scaled game menu-button input"): return
	app.confirm.hide()
	app.confirm.queue_free()
	await app.request_leave_game()
	if not check(app.parked and not app.game_surface.visible and app.view == "menu", "Parking a game restores home input"): return
	if not check(app.game_surface.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Parking a game suspends its hidden renderer"): return
	var parked_adapter = app.game.adapter
	var parked_session: String = app.session
	app.game_surface.ui_scale = 1.5
	await app.get_tree().process_frame
	if not check(app.game.size == app.game.get_viewport_rect().size and app.game.adapter == parked_adapter and app.session == parked_session and app.parked, "Rescaling a parked table fits its viewport without replacing the engine or adapter"): return
	app.game_surface.ui_scale = active_scale
	await click(app, app.computer.quit_button, 1.0)
	if not await until(func(): return is_instance_valid(app.confirm) and app.confirm.visible, "main-menu Quit confirmation"): return
	if not check(app.confirm.get_viewport_rect().size.is_equal_approx((app.size / active_scale).floor()), "Main-menu Quit confirmation uses the selected scale"): return
	await capture("quit")
	await click(app.confirm.get_parent().get_parent(), app.confirm.cancel)
	if not await until(func(): return not is_instance_valid(app.confirm), "Keep Open dismisses Quit"): return
	if not check(app.parked and app.game != null, "Canceling Quit keeps the parked game alive"): return
	await app.resume_game()
	if not check(app.view == "game" and app.game_surface.visible, "Resume preserves scaled gameplay surface"): return
	if not check(app.game_surface.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and not app.game_surface.render_when_hidden, "Resuming restores continuous drawing and releases offscreen-preview mode"): return
	await capture("resumed")
	await app._end_confirmed_session()
	if not await until(func(): return app.game == null and not app.busy, "owned engine cleanup"): return
	if not Array(OS.get_cmdline_user_args()).any(func(argument): return argument.begins_with("--ui-scale=")):
		await app.open_match_settings()
		if not await until(func(): return app.view == "settings" and not app.busy, "display preference settings"): return
		app.match_settings.display_scale_picker.select(3)
		app.match_settings.display_scale_picker.item_selected.emit(3)
		await click(app.settings_surface, app.match_settings.save_button)
		if not await until(func(): return app.view == "menu" and not app.busy and is_equal_approx(app.computer.ui_scale, 1.5), "Save applies the local 150% preference"): return
		active_scale = 1.5
		if not check(is_equal_approx(preload("res://scripts/app/DisplayPreferences.gd").read(), 1.5), "Display choice survives a new preference read"): return
		await app.open_match_settings()
		if not await until(func(): return app.view == "settings" and not app.busy, "reopen scaled settings"): return
		if not check(app.match_settings.display_scale_picker.selected == 3 and app.settings_viewport.size_2d_override == Vector2i((app.settings_surface.size / 1.5).floor()), "Reopened settings use the saved scale and selection"): return
		await capture("saved-150-percent")
		app.match_settings.display_scale_picker.select(0)
		app.match_settings.display_scale_picker.item_selected.emit(0)
		await click(app.settings_surface, app.match_settings.save_button)
		if not await until(func(): return app.view == "menu" and not app.busy and preload("res://scripts/app/DisplayPreferences.gd").read() == 0, "Restore automatic device sizing"): return
	print("PASS: scaled editor/game sizing, real mouse input, import dialog, home, real match, park/resume and end cleanup")
	app.get_tree().quit()

func _artwork_input_check() -> bool:
	var editor: Control = app.editor
	var card: Dictionary = editor.shown_cards[0]
	editor._inspect(card)
	if not await until(func(): return editor.dialog_body.get_children().any(func(child): return child is OptionButton), "artwork variant dropdown"): return false
	var picker: OptionButton = editor.dialog_body.get_children().filter(func(child): return child is OptionButton)[0]
	# Scroll the printing dropdown into view before clicking it.
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	var scroll: ScrollContainer = editor.dialog_body.get_parent()
	scroll.ensure_control_visible(picker)
	await app.get_tree().process_frame
	await capture("artwork-before-dropdown-" + str(app.get_window().size.x))
	await click(app.editor_surface, picker)
	if not check(picker.get_popup().visible, "Variant dropdown opens with real mouse input"): return false
	await capture("artwork-variant-menu")
	var previous_key: String = editor.inspect_card.key
	var target := 1 if picker.selected == 0 else 0
	var selected := [-1]
	picker.item_selected.connect(func(index): selected[0] = index)
	var popup := picker.get_popup()
	var panel := popup.get_theme_stylebox("panel")
	var row_height: float = popup.get_theme_font("font").get_height(popup.get_theme_font_size("font_size")) + popup.get_theme_constant("v_separation")
	var point: Vector2 = app.editor_surface.global_position + (Vector2(popup.position) + Vector2(30, panel.get_margin(SIDE_TOP) + row_height * (target + 0.5))) * active_scale
	await _artwork_click_point(point)
	await app.get_tree().process_frame
	await capture("artwork-variant-selected")
	if not check(selected[0] == target and editor.inspect_card.key != previous_key, "A real variant click selects a different printing"): return false
	if not check(editor.get_viewport().get_embedded_subwindows().is_empty(), "Selecting a variant leaves no embedded popup blocking X"): return false
	var close: Button = editor.dialog.get_child(0).get_child(0).get_child(2)
	await click(app.editor_surface, close)
	if not check(not editor.overlay.visible, "X closes card details after choosing a variant without Escape"): return false
	if not await _artwork_gallery_check(): return false
	return true

func _artwork_gallery_check() -> bool:
	var editor: Control = app.editor
	# Gallery choices must change the deck and dismiss, without opening details.
	var deck_tile: Control = editor.card_grid.get_children().filter(func(value): return value is LibraryTile)[0]
	# Intermediate scales can wrap toolbars enough to scroll the outer workspace
	# too. Bring the fixture through every clipping ancestor before clicking it.
	var ancestor := deck_tile.get_parent()
	while ancestor != null and ancestor != editor:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(deck_tile)
			await app.get_tree().process_frame
			await app.get_tree().process_frame
		ancestor = ancestor.get_parent()
	await app.get_tree().process_frame
	var visible_deck_rect: Rect2 = deck_tile.get_global_rect().intersection(editor.card_scroll.get_global_rect()).intersection(editor.get_viewport_rect())
	if not check(visible_deck_rect.has_area(), "The right-click fixture uses a visible deck card"): return false
	var deck_point: Vector2 = app.editor_surface.global_position + visible_deck_rect.get_center() * active_scale
	# The short fixture clips the deck grid to a thin strip. The large
	# fixture reproduces the complete native press/release capture sequence.
	if app.get_window().size.x < 2000: editor._card_context(editor.shown_cards[0])
	else: await _artwork_click_point(deck_point, MOUSE_BUTTON_RIGHT)
	if not check(editor.context_menu.visible, "The deck card context menu opens"): return false
	var menu: PopupMenu = editor.context_menu
	if not check(app.editor_surface.full_input, "A context popup owns input across the whole editor surface"): return false
	# This menu has four actions on either side of Change artwork, with
	# matching separators. Keep it inside the physical Retina test display.
	menu.position = Vector2i(120, 120)
	await app.get_tree().process_frame
	var menu_point: Vector2 = app.editor_surface.global_position + (Vector2(menu.position) + Vector2(24, menu.size.y * 0.5)) * active_scale
	await _artwork_click_point(menu_point)
	if not check(not menu.visible, "Change artwork releases the context popup before thumbnail selection"): return false
	if not await until(func(): return not editor.artwork_cards.is_empty() and editor.dialog_body.get_child(0) is GridContainer, "artwork gallery input"): return false
	await app.get_tree().process_frame
	var tiles: Array = editor.dialog_body.get_child(0).get_children().map(func(group): return group.get_child(0))
	var tile: Control = tiles.filter(func(value): return value.card.key != editor.inspect_card.key)[0]
	var chosen_key: String = tile.card.key
	var section: String = editor.inspect_card.section
	var quantity: int = editor.inspect_card.quantity
	var gallery_parent := tile.get_parent()
	while gallery_parent != null and gallery_parent != editor:
		if gallery_parent is ScrollContainer:
			gallery_parent.ensure_control_visible(tile)
			await app.get_tree().process_frame
			await app.get_tree().process_frame
		gallery_parent = gallery_parent.get_parent()
	await capture("artwork-thumbnail-before-click")
	await _artwork_click_point(app.editor_surface.global_position + tile.get_global_rect().get_center() * active_scale, MOUSE_BUTTON_LEFT, editor)
	await app.get_tree().process_frame
	if not check(editor.draft.sections[section].any(func(value): return value.key == chosen_key and int(value.quantity) == quantity), "A thumbnail click applies the chosen artwork with its original quantity and section"): return false
	if not check(not editor.overlay.visible, "Artwork thumbnail click dismisses the gallery without opening card details"): return false
	await capture("artwork-return-to-deck")
	# The next ordinary card click and its X must work without clearing capture
	# with Escape, the original symptom after a mouse-opened artwork gallery.
	if app.get_window().size.x < 2000: editor._inspect(editor.shown_cards[0])
	else: await _artwork_click_point(deck_point)
	if not check(editor.overlay.visible and not editor.artwork_mode, "An ordinary card click works after artwork selection"): return false
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	var close: Button = editor.dialog.get_child(0).get_child(0).get_child(2)
	await click(app.editor_surface, close)
	if not check(not editor.overlay.visible, "X closes card details after the real artwork flow without Escape"): return false
	print("PASS: mouse-opened artwork gallery applies selection, preserves quantity/section and releases input for X")
	return true

func _artwork_click_point(point: Vector2, button_index: MouseButton = MOUSE_BUTTON_LEFT, gallery: Control = null) -> void:
	app.get_window().grab_focus()
	app.get_viewport().warp_mouse(point)
	await app.get_tree().create_timer(0.15).timeout
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await app.get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button_index
	event.button_mask = 1 << (button_index - 1)
	event.pressed = true
	Input.parse_input_event(event)
	await app.get_tree().process_frame
	if gallery != null:
		if not check(gallery.overlay.visible and gallery.artwork_mode, "The gallery remains modal until the thumbnail mouse release"): return
	event.pressed = false
	event.button_mask = 0
	Input.parse_input_event(event)
	await app.get_tree().process_frame
