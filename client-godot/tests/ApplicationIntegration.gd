extends RefCounted
const Driver = preload("res://tests/LiveIntegration.gd")
const Starting = preload("res://scripts/ui/StartingPlayerPanel.gd")
const CoinToss = preload("res://scripts/ui/CoinTossPanel.gd")
var app: Control
var deadline := 0
var artwork_fixtures: Dictionary = {}

func _fixture_match_artwork(_id: int, operation: String, result: Dictionary) -> void:
	if operation not in ["match.start", "match.status"] or not result.has("artwork"): return
	var match_session: String = result.get("session", "")
	if artwork_fixtures.has(match_session): return
	artwork_fixtures[match_session] = true
	# Internet downloads stay disabled: missing bot faces must never gate play.
	var faces: Array = app.Images.deck_faces(result.artwork)
	for card in faces:
		if not check(app.images.game_faces.has(card.imageKey), "Every actual deck face must enter background warmup"): return
	if not check(app.computer.phase != "preparing_images" and (not is_instance_valid(app.computer.loading) or not app.computer.loading.is_visible_in_tree()), "Deck artwork never opens a loading screen"): return
	print("PASS: background artwork manifest (", faces.size(), " exact faces; unavailable artwork does not block play)")
var responses: Dictionary = {}
var errors: Dictionary = {}
var capture_root := ""
var quitting := false
var initial_dark_mode := false

func check(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		app.get_tree().quit(1)
	return value

func until(condition: Callable, message: String) -> bool:
	while Time.get_ticks_msec() < deadline:
		await app.get_tree().create_timer(0.1).timeout
		if condition.call(): return true
	return check(false, "Timed out: " + message)

func call_api(operation: String, args: Dictionary = {}) -> Dictionary:
	var request := args.duplicate(true)
	if operation.begins_with("match."): request.owner = app.client_owner
	var id: int = app.api.request(operation, request)
	if not await until(func(): return responses.has(id) or errors.has(id), operation): return {}
	return {"error": errors[id]} if errors.has(id) else responses[id]

func capture(name: String) -> void:
	if capture_root.is_empty(): return
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	await RenderingServer.frame_post_draw
	app.get_viewport().get_texture().get_image().save_png(capture_root.path_join(name + ".png"))
	if "--app-night-cinematics" in OS.get_cmdline_user_args() and name in ["app-main-menu", "app-play-button-press", "app-deck-insertion", "app-match-boot-rules", "app-match-boot-ready", "app-settings-zoom", "app-settings-zoom-late", "app-editor-scroll", "app-editor-return-scroll", "app-deck-editor", "app-deck-editor-1280"]:
		app.get_viewport().get_texture().get_image().save_png(capture_root.path_join("night-" + name + ".png"))

func click_control(control: Control) -> void:
	# Dummy headless windows clip native pointer delivery to 64px. Rendered
	# checks use real viewport hit testing; headless checks exercise the handlers.
	if DisplayServer.get_name() == "headless" and control is Button:
		if not control.disabled: control.pressed.emit()
		await app.get_tree().process_frame
		return
	var point := control.get_global_transform() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	_pointer_input(motion)
	await app.get_tree().process_frame
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	_pointer_input(press)
	await app.get_tree().process_frame
	press.pressed = false
	press.button_mask = 0
	_pointer_input(press)
	await app.get_tree().process_frame

func _pointer_input(event: InputEventMouse) -> void:
	if DisplayServer.get_name() == "headless":
		var local: InputEventMouse = event.duplicate()
		local.position = app.computer.shelf.get_global_transform().affine_inverse() * event.position
		app.computer.shelf._carousel_input(local)
	else: app.get_viewport().push_input(event, true)

func swipe_carousel(shift: float) -> void:
	var shelf: Control = app.computer.shelf
	var origin := shelf.global_position + Vector2(shelf.size.x * 0.5, shelf.size.y * 0.5)
	var press := InputEventMouseButton.new()
	press.position = origin
	press.global_position = origin
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	_pointer_input(press)
	await app.get_tree().process_frame
	for i in range(1, 7):
		var motion := InputEventMouseMotion.new()
		motion.position = origin + Vector2(shift * i / 6.0, 0)
		motion.global_position = motion.position
		motion.relative = Vector2(shift / 6.0, 0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		_pointer_input(motion)
		await app.get_tree().create_timer(0.02).timeout
	press.position = origin + Vector2(shift, 0)
	press.global_position = press.position
	press.button_mask = 0
	press.pressed = false
	_pointer_input(press)
	await app.get_tree().process_frame

func carousel_slots(shelf: Control) -> Dictionary:
	var result := {}
	for i in range(shelf.tiles.size()):
		result[i] = []
		var tile: Control = shelf.tiles[i]
		var x: float = tile.position.x + tile.size.x * 0.5
		if tile.visible and x > 0 and x < shelf.size.x: result[i].append(x)
	for copy in shelf.copies:
		var x: float = copy.position.x + copy.size.x * 0.5
		if copy.visible and x > 0 and x < shelf.size.x: result[copy.deck_index].append(x)
	return result

func check_carousel_seams() -> bool:
	var shelf := preload("res://scripts/app/DeckCarousel.gd").new()
	shelf.images = app.images
	shelf.hide()
	app.add_child(shelf)
	shelf.size = Vector2(2560, 550)
	shelf.deck_selected.connect(func(index): shelf.select_id(shelf.decks[index].id))
	for count in [4, 5, 6]:
		shelf.set_decks(app.decks.slice(0, count), app.decks[0].id)
		for seam in [-3.0, -2.5, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]:
			shelf.cursor = seam - 0.0001
			shelf._arrange()
			var before := carousel_slots(shelf)
			shelf.cursor = seam + 0.0001
			shelf._arrange()
			var after := carousel_slots(shelf)
			for index in before:
				for x in before[index]:
					var continuous := false
					for next_x in after[index]:
						if absf(next_x - x) < 1.0: continuous = true
					if not check(continuous, "Visible carousel slot stays continuous across wrapping with %d decks at cursor %.1f" % [count, seam]): return false
		for copy in shelf.copies:
			var point: Vector2 = copy.position + copy.size * 0.5
			if copy.visible and point.x > 0 and point.x < shelf.size.x:
				if not check(shelf._tile_at(point) == copy.deck_index, "Repeated visible slot selects its source deck"): return false
		shelf.cursor = 0.0
		shelf.select_id(shelf.decks[0].id)
		for press in range(1, count * 2 + 1):
			shelf.step(-1)
			if not check(is_equal_approx(shelf.target, -float(press)), "Rapid left presses keep their direction before settling"): return false
		for press in range(count * 2): shelf.step(1)
		if not check(is_zero_approx(shelf.target), "Rapid reverse presses return to the same logical slot"): return false
	shelf.queue_free()
	return true

func carousel_key(code: Key) -> void:
	app.computer.shelf.grab_focus()
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await app.get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = code
	Input.parse_input_event(event)
	await app.get_tree().process_frame

func _room_above_editor() -> bool:
	for x in [-1.7, 1.7]:
		for z in [-1.2, 0.95]:
			var bottom: Vector2 = app.computer.world.camera.unproject_position(Vector3(x, -1.1, z))
			if bottom.y + app.computer.world_container.position.y >= 0: return false
	return true

func deck_filter_check() -> bool:
	var computer: Control = app.computer
	var saved_filter: String = computer.saved_deck_filter
	if not check(Rect2(Vector2.ZERO, app.size).encloses(computer.filter_buttons.precon.get_global_rect()) and not computer.filter_buttons.precon.get_global_rect().intersects(computer.editor_button.get_global_rect()), "Deck filters fit the header beside the Forge badge"): return false
	await click_control(computer.filter_buttons.precon)
	if not await until(func(): return computer.deck_filter == "precon" and computer.decks.size() > 150 and computer.decks.all(func(deck): return deck.source == "precon") and computer.shelf.decks.size() == computer.decks.size(), "PRECONS shows only Forge's bundled precons"): return false
	if not await until(func(): return app.selected_id == computer.decks[0].id and app.selected_deck.get("id", "") == app.selected_id and app.selected_deck.get("readOnly", false) and app.selected_deck.get("legal", false), "Filtering away the selected disk opens the first visible precon for Play"): return false
	if not check(computer.console.disk_name == app.selected_deck.name, "The monitor shows the selected precon"): return false
	var appearance := ConfigFile.new()
	if not check(appearance.load(computer.APPEARANCE_PATH) == OK and appearance.get_value("library", "filter") == "precon", "The deck filter persists across launches"): return false
	await app.get_tree().create_timer(0.4).timeout
	await capture("app-main-menu-precons")
	var precon_id: String = app.selected_id
	await click_control(computer.filter_buttons.all)
	if not await until(func(): return computer.decks.size() == app.decks.size() and app.selected_id == precon_id, "ALL shows saved decks and precons and keeps a visible selection"): return false
	var started := Time.get_ticks_usec()
	computer.set_deck_filter("custom", false)
	computer.set_deck_filter("precon", false)
	print("[timing] deck filter custom -> precon: ", (Time.get_ticks_usec()-started)/1000.0, " ms")
	await click_control(computer.filter_buttons.custom)
	if not await until(func(): return computer.decks.size() == 18 and app.selected_id == app.decks[0].id and app.selected_deck.get("id", "") == app.decks[0].id, "CUSTOM shows only saved decks and selects the first one"): return false
	computer.saved_deck_filter = saved_filter
	computer._save_appearance()
	print("PASS: home deck filter (all/custom/precons), precon selection, persistence")
	return true

func press_key(keycode: Key, unicode: int = 0, ctrl: bool = false) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.unicode = unicode
	key.ctrl_pressed = ctrl
	key.pressed = true
	app.get_viewport().push_input(key)
	var release := key.duplicate()
	release.pressed = false
	app.get_viewport().push_input(release)
	await app.get_tree().process_frame

func type_text(text: String) -> void:
	for character in text: await press_key(KEY_NONE, character.unicode_at(0))

func deck_search_check() -> bool:
	var computer: Control = app.computer
	var console: Control = computer.console
	if not check(not console.search_focused and console.search_query.is_empty() and computer.decks.size() == 18, "The search bar starts empty"): return false
	# Typing goes to the search bar even while a header button kept focus after a click.
	computer.filter_buttons.custom.grab_focus()
	var target: Dictionary = computer.decks[3]
	await type_text(target.name.to_lower())
	if not await until(func(): return computer.decks.size() >= 1 and computer.decks.all(func(deck): return deck.name.to_lower().contains(target.name.to_lower())) and app.selected_id == computer.decks[0].id, "Typing a deck name narrows the carousel and selects the first match"): return false
	if not check(console.search_focused and console.search_query == target.name.to_lower() and console.search_matches == computer.decks.size() and computer.deck_filter == "custom", "The CRT search bar shows the query and match count without changing the source filter"): return false
	await app.get_tree().create_timer(0.3).timeout
	await capture("app-main-menu-search")
	await press_key(KEY_BACKSPACE, 0, true)
	await type_text("zzqx")
	if not await until(func(): return computer.decks.is_empty() and console.empty_library and app.selected_deck.is_empty(), "A query with no matches empties the carousel"): return false
	await capture("app-main-menu-search-empty")
	for i in range(4): await press_key(KEY_BACKSPACE)
	if not check(computer.search_query.is_empty() and computer.decks.size() == 18, "Backspace removes typed characters"): return false
	await type_text("commander")
	await press_key(KEY_ESCAPE)
	if not await until(func(): return computer.search_query.is_empty() and not console.search_focused and computer.decks.size() == 18 and not app.selected_deck.is_empty(), "Escape clears the search and restores every deck"): return false
	var bar_center: Vector2 = console.get_global_transform() * ((console.SEARCH_RECT.get_center()) * console.size / console.DESIGN_SIZE)
	var on_screen: Vector2 = computer.world.camera.unproject_position(computer.world.screen_point(bar_center / Vector2(computer.DISPLAY_SIZE))) + computer.world_container.position + computer.get_global_rect().position
	var press := InputEventMouseButton.new()
	press.position = on_screen
	press.global_position = on_screen
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	_pointer_input(press)
	await app.get_tree().process_frame
	var release := press.duplicate()
	release.pressed = false
	release.button_mask = 0
	_pointer_input(release)
	await app.get_tree().process_frame
	if not check(console.search_focused, "Clicking the search bar on the monitor focuses it"): return false
	await press_key(KEY_ESCAPE)
	# Later checks expect the first deck, with wrapped neighbors on both sides.
	computer.select_id(app.decks[0].id)
	app._select_deck(0)
	if not await until(func(): return app.selected_deck.get("id", "") == app.decks[0].id and app.selected_deck.get("legal", false) and absf(computer.shelf.cursor - computer.shelf.target) < 0.01, "selection is ready again after search"): return false
	print("PASS: main-menu deck search (typing, focus safety, matches, empty result, backspace, escape)")
	return true

func editor_precon_check() -> bool:
	var computer: Control = app.computer
	var custom_id: String = app.editor.draft.id
	computer.set_deck_filter("precon", false)
	if not await until(func(): return app.editor.draft.get("readOnly", false) and app.editor.draft.id == computer.decks[0].id and not app.editor.loading_deck, "Editor PRECONS filter opens a precon"): return false
	app.editor._controls()
	if not check(app.editor.save_button.text == "Save as copy" and not app.editor.save_button.disabled and not app.editor.dirty, "A precon offers Save as copy instead of overwriting"): return false
	if not check(computer.shelf.decks.back().get("create", false) and computer.shelf.decks.size() == computer.decks.size() + 1, "The editor keeps its plus floppy under the precon filter"): return false
	app.editor._show_actions()
	if not check(app.editor.delete_button.disabled, "Forge precons cannot be deleted"): return false
	app.editor.overlay.hide()
	await app.get_tree().create_timer(0.3).timeout
	await capture("app-editor-precon")
	computer.set_deck_filter("custom", false)
	if not await until(func(): return app.editor.draft.id == custom_id and not app.editor.loading_deck and not app.editor.draft.get("readOnly", false), "Returning to CUSTOM reopens the saved deck"): return false
	print("PASS: editor precons are read-only with Save as copy and no delete")
	return true

func console_check() -> bool:
	var console: Control = app.computer.console
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	if not check(console.mouse_filter == Control.MOUSE_FILTER_IGNORE and app.computer.monitor_root.find_children("*", "OptionButton", true, false).is_empty(), "The monitor is read-only; the floppy carousel is the sole deck selector"): return false
	if not check(console.disk_name == app.selected_deck.name and console.stats.total == app.selected_deck.count and console.stats.types.LANDS == app.selected_deck.lands, "The terminal displays the selected deck's actual card and land counts"): return false
	if not check(is_equal_approx(console.stats.average, float(app.selected_deck.averageMana)) and int(console.stats.identity) == 23, "Average mana and Atraxa's W/U/B/G identity come from the deck"): return false
	for index in range(8):
		if not check(console.stats.curve[index] == int(app.selected_deck.curve[index]), "Every nonland mana-curve bin agrees with Forge"): return false
	if not _console_safe(console): return false
	var long_deck: Dictionary = app.selected_deck.duplicate(true)
	long_deck.name = "A commander deck with a very long disk label to exercise the rounded CRT safe area ".repeat(2).left(120)
	var partner: Dictionary = long_deck.sections.Commander[0].duplicate(true)
	partner.name = "A second commander with an exceptionally long partner name to read on the tube"
	long_deck.sections.Commander[0].name = "First commander with another exceptionally long name for terminal layout"
	long_deck.sections.Commander.append(partner)
	console.present(long_deck, 4, false)
	await capture("app-monitor-long-deck-label")
	if not _console_safe(console): return false
	app.computer.render_selection(app.selected_deck, 1 + app.match_preferences.bots.size())
	await app.get_tree().process_frame
	return true

func _console_safe(console: Control) -> bool:
	if DisplayServer.get_name() == "headless": return true
	if not check(not console.text_bounds.is_empty(), "The CRT dashboard renders deck information"): return false
	for rect in console.text_bounds:
		if not check(console.SAFE_RECT.grow(0.5).encloses(rect), "All terminal text stays within the rounded tube's safe area: " + str(rect)): return false
		for point in [rect.position, rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y)]:
			var uv: Vector2 = point / console.DESIGN_SIZE - Vector2(0.5, 0.5)
			var bow := uv * Vector2(1.0 + 0.018 * pow(uv.y * 2.0, 2), 1.0 + 0.032 * pow(uv.x * 2.0, 2))
			var q := bow.abs() - Vector2.ONE * 0.435
			var distance := q.max(Vector2.ZERO).length() + minf(maxf(q.x, q.y), 0) - 0.065
			if not check(distance < -0.025, "Printed content clears the curved glass clipping and edge fade"): return false
	return true

func hardware_controls_check() -> bool:
	var world: Node3D = app.computer.world
	var play_bounds: AABB = world.play_cap.mesh.get_aabb()
	var settings_bounds: AABB = world.settings_cap.mesh.get_aabb()
	if not check(is_equal_approx(play_bounds.size.y, settings_bounds.size.y) and is_equal_approx(play_bounds.size.z, settings_bounds.size.z), "Both molded keys share the same height and depth"): return false
	if not check(is_equal_approx(world.PLAY_CENTER.y, world.DRIVE_CENTER.y) and is_equal_approx(world.SETTINGS_CENTER.y, world.DRIVE_CENTER.y) and world.PLAY_CENTER.z + play_bounds.end.z - 0.88 < 0.006, "Keys align with the drive and sit only slightly proud of the fascia"): return false
	var case_plastic: StandardMaterial3D = world._case_material()
	for material in [world.play_cap_material, world.settings_cap_material]:
		if not check(material != case_plastic and is_equal_approx(material.roughness, case_plastic.roughness) and is_equal_approx(material.normal_scale, case_plastic.normal_scale) and is_zero_approx(material.metallic) and not material.emission_enabled, "Keycaps match the case's matte plastic finish while keeping independent hover materials"): return false
	for glyph in [world.play_arrow, world.settings_icon]:
		if not check(glyph.material_override.albedo_color.is_equal_approx(world.KEY_INK) and not glyph.material_override.emission_enabled, "Pad-printed glyphs use charcoal without emission"): return false
	if not check(world.play_legend.outline_size == 0 and world.play_legend.modulate.is_equal_approx(world.KEY_INK) and not world.play_activity_led.material_override.emission_enabled, "PLAY has no glow and its activity LED is unlit at rest"): return false
	if not await until(func(): return not app.computer.start_button.disabled and world.play_enabled, "PLAY is ready for hover verification"): return false
	app.computer.start_button.mouse_exited.emit()
	await app.get_tree().create_timer(0.12).timeout
	var base: Color = world.play_cap_material.albedo_color
	app.computer.start_button.mouse_entered.emit()
	await app.get_tree().create_timer(0.12).timeout
	if not check(world.play_cap_material.albedo_color.r > base.r and world.play_arrow.material_override.albedo_color.is_equal_approx(world.KEY_INK), "Hover brightens only the plastic, preserving printed ink: " + str([base, world.play_cap_material.albedo_color, world.play_enabled])): return false
	app.computer.start_button.mouse_exited.emit()
	await app.get_tree().create_timer(0.12).timeout
	# Exercise real mouse-down/hold/cancel through the native hit regions, not
	# just the world's programmatic pulse helper.
	for play in [true, false]:
		var control: Button = app.computer.start_button if play else app.computer.settings_button
		var key: Node3D = world.play_key if play else world.settings_key
		var rest: Vector3 = world.PLAY_CENTER if play else world.SETTINGS_CENTER
		var point: Vector2 = control.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		if DisplayServer.get_name() != "headless": _pointer_input(motion)
		await app.get_tree().create_timer(0.10).timeout
		var sample := Vector3(0.04 if play else 0.08, 0.075, world.KEY_DEPTH * 0.5 + 0.0005)
		var rest_luminance := 0.0
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var pixels := app.get_viewport().get_texture().get_image()
			rest_luminance = pixels.get_pixelv(Vector2i(world.camera.unproject_position(key.position + sample))).get_luminance()
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.button_mask = MOUSE_BUTTON_MASK_LEFT
		press.pressed = true
		press.position = point
		press.global_position = point
		if DisplayServer.get_name() == "headless": control.button_down.emit()
		else: _pointer_input(press)
		await app.get_tree().create_timer(0.18).timeout
		if not check(not app.busy and key.position.z < rest.z - 0.024 and (world.play_held if play else world.settings_held), "Native mouse-down visibly depresses and holds the key before its action runs"): return false
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var pixels := app.get_viewport().get_texture().get_image()
			var held_luminance := pixels.get_pixelv(Vector2i(world.camera.unproject_position(key.position + sample))).get_luminance()
			if not check(held_luminance < rest_luminance - 0.025, "The rendered held key is visibly shaded rather than relying on a subpixel depth shift"): return false
		await capture("app-play-key-held" if play else "app-settings-key-held")
		motion.position = Vector2(20, app.size.y * 0.45)
		motion.global_position = motion.position
		if DisplayServer.get_name() == "headless": control.mouse_exited.emit()
		else: _pointer_input(motion)
		await app.get_tree().process_frame
		press.position = motion.position
		press.global_position = motion.position
		press.pressed = false
		press.button_mask = 0
		if DisplayServer.get_name() == "headless": control.button_up.emit()
		else: _pointer_input(press)
		var release: Tween = world.play_animation if play else world.settings_animation
		while release.is_running() and release.get_total_elapsed_time() < 0.025: await app.get_tree().process_frame
		if not check(key.position.z > rest.z - world.KEY_TRAVEL * 0.75, "Release immediately springs outward instead of dipping farther into the pocket: " + str([play, key.position.z, rest.z, world.play_held, world.settings_held, world.play_animation.is_running(), world.settings_animation.is_running() if world.settings_animation != null else false])): return false
		await app.get_tree().create_timer(0.18).timeout
		if not check(not app.busy and app.view == "menu" and key.position.is_equal_approx(rest), "Dragging off and releasing springs the key back without opening a menu or launching a match"): return false
	for play in [true, false]:
		var key: Node3D = world.play_key if play else world.settings_key
		var rest: Vector3 = world.PLAY_CENTER if play else world.SETTINGS_CENTER
		if play: world.click_play()
		else: world.click_settings()
		var animation: Tween = world.play_animation if play else world.settings_animation
		var deepest := rest.z
		var captured := false
		while animation.is_running():
			deepest = minf(deepest, key.position.z)
			if not captured and key.position.z < rest.z - 0.015:
				captured = true
				if play and not check(world.play_activity_led.material_override.emission_enabled, "PLAY briefly lights its teal activity dot while pressed"): return false
				await capture("app-play-key-depressed" if play else "app-settings-key-depressed")
			await app.get_tree().process_frame
		if not check(deepest < rest.z - 0.018 and key.position.is_equal_approx(rest), "Each key visibly depresses and springs back to its pocket"): return false
	await app.get_tree().process_frame
	if not check(not world.play_activity_led.material_override.emission_enabled, "The activity dot switches off after the press"): return false
	if not capture_root.is_empty():
		var home: Transform3D = world.camera.transform
		var fov: float = world.camera.fov
		world.camera.position = Vector3(-0.10, 0.20, 3.7)
		world.camera.fov = 35.0
		world.camera.look_at(Vector3(-0.03, -0.40, 0.86))
		app.computer.header.hide()
		app.computer.shelf.hide()
		app.computer.atmosphere.hide()
		await capture("app-molded-hardware-closeup")
		world.camera.transform = home
		world.camera.fov = fov
		app.computer.header.show()
		app.computer.shelf.show()
		app.computer.atmosphere.show()
		app.computer._position_play_button()
		await app.get_tree().process_frame
	return true

func settings_check() -> bool:
	if not check(app.computer.settings_button.get_global_rect().get_center().x > app.start_button.get_global_rect().get_center().x, "The physical cog sits to the right of Play"): return false
	await click_control(app.computer.settings_button)
	await app.get_tree().create_timer(0.03).timeout
	if not check(app.busy and app.computer.world.camera.transform.is_equal_approx(app.computer.world.home_transform) and app.computer.world.settings_key.position.z < app.computer.world.SETTINGS_CENTER.z - 0.005, "Settings waits at the home camera while the physical key completes its stroke"): return false
	if not await until(func(): return app.computer.world.camera.position.distance_to(app.computer.world.home_transform.origin) > 0.01, "Settings zoom starts after key release"): return false
	if not check(app.computer.world.settings_key.position.is_equal_approx(app.computer.world.SETTINGS_CENTER) and not app.computer.world.settings_animation.is_running(), "The settings key is fully raised before camera motion"): return false
	if not check(app.computer.world.screen.scale.is_equal_approx(Vector3.ONE) and app.computer.world.screen.material_override == app.computer.world.crt_material, "Settings zoom keeps the glass inside the depth-tested physical monitor"): return false
	await app.get_tree().create_timer(0.3).timeout
	if not check(app.computer.world.animation.is_running() and float(app.computer.world.screen_material.get_shader_parameter("channel_progress")) > 0.0, "Settings zoom-in and CRT retune run together"): return false
	await capture("app-settings-zoom")
	if not check(app.computer.world.screen.scale.is_equal_approx(Vector3.ONE), "The monitor never stretches during the settings camera move"): return false
	await app.get_tree().create_timer(0.25).timeout
	await capture("app-settings-zoom-late")
	if not await until(func(): return app.view == "settings" and not app.busy, "zoom into Commander match settings"): return false
	var settings: Control = app.match_settings
	if not check(not app.computer.visible and settings.get_parent() == app.content and settings.value.bots.size() == 2, "Zoom hands off to an interactive settings screen"): return false
	if not check(settings.grid.columns == 1 and settings.rows[0].get_global_rect().position.x == settings.rows[1].get_global_rect().position.x, "The terminal uses aligned roster rows instead of player cards"): return false
	settings.add_button.pressed.emit()
	if not check(settings.value.bots.size() == 3 and settings.add_button.disabled, "Add bot supports a four-player Commander table"): return false
	await capture("app-settings-full-roster")
	settings.remove_buttons.back().pressed.emit()
	if not check(settings.value.bots.size() == 2, "Remove bot updates the player list"): return false
	if not check(settings.online_body.get_parent() == settings.roster.get_parent() and settings.online_body.get_index() > settings.roster.get_index(), "The online section sits below the roster"): return false
	if not check(settings.host_button != null and settings.join_button != null and settings.server_field != null and not settings.host_button.disabled, "An idle terminal offers host, join and a server address"): return false
	var parse: Script = settings.net.get_script()
	if not check(parse.parse_address("203.0.113.7").port == 36743 and parse.parse_address(" 203.0.113.7:5000 ").port == 5000 and parse.parse_address("").is_empty() and parse.parse_address("a b").is_empty() and parse.parse_address("h:99999").is_empty(), "Server addresses accept a bare IP or IP:port and refuse anything else"): return false
	await capture("app-settings-online-idle")
	# Hosting is shown from a stubbed status: the real path is covered by bridge/tools/online-check.mjs,
	# and these checks must neither open a port nor contact a router or address service.
	settings.net.role = "hosting"
	settings.net.host_status = {"hosting": true, "port": 36743, "defaultPort": true, "lan": "192.168.1.20", "public": "203.0.113.7", "upnp": "open", "players": [{"id": 1, "kind": "player", "name": "Remote friend", "avatar": 4, "portrait": "", "deck": "Dragon's Fury", "commander": "Scion of the Ur-Dragon"}]}
	settings._net_changed()
	if not check(settings.net.share_address() == "203.0.113.7", "The host is given the public IP to share, with the default port left out"): return false
	if not check(settings.kick_buttons.size() == 1 and settings.rows.size() == 4, "A joined player takes a seat, and the seat that is left stays open"): return false
	await capture("app-settings-online-hosting")
	settings.value.bots.remove_at(1)
	settings.value.bots.remove_at(0)
	settings._render()
	if not check(settings.rows.size() == 4 and settings.value.bots.is_empty() and settings.add_button != null, "A host with a joined player needs no bots, and every free seat is open"): return false
	settings.value.bots.append(settings.Preferences.bot(1))
	settings.value.bots.append(settings.Preferences.bot(2))
	settings.net.role = "joined"
	settings.net.host_status = {}
	settings.net.address = "203.0.113.7"
	settings.net.you = 1
	settings.net.open_seats = 1
	settings.net.roster = [{"kind": "host", "name": "The host", "avatar": 1, "portrait": ""}, {"kind": "player", "id": 1, "name": "Me", "avatar": 2, "portrait": "", "deck": "Dragon's Fury", "commander": "Scion of the Ur-Dragon"}]
	settings._net_changed()
	if not check(settings.rows.size() == 3 and settings.names.is_empty() and settings.deck_choices.is_empty(), "A joined player sees the host's roster and cannot edit it"): return false
	await capture("app-settings-online-joined")
	settings.net.role = ""
	settings.net.roster = []
	settings._net_changed()
	if not check(settings.value.bots.size() == 2 and settings.names.size() == 3 and settings.host_button != null, "Leaving a session restores the local roster"): return false
	var shortcut := InputEventKey.new()
	shortcut.pressed = true
	shortcut.keycode = KEY_F2
	settings._unhandled_key_input(shortcut)
	if not check(settings.value.bots.size() == 3, "F2 adds a bot from the terminal roster"): return false
	settings.get_viewport().gui_release_focus()
	settings._select_row(3)
	shortcut.keycode = KEY_DELETE
	settings._unhandled_key_input(shortcut)
	if not check(settings.value.bots.size() == 2, "Delete removes the selected bot from the terminal roster"): return false
	settings.names[0].text = "Commander pilot"
	settings.names[0].text_changed.emit(settings.names[0].text)
	settings.names[1].text = "Green machine"
	settings.names[1].text_changed.emit(settings.names[1].text)
	settings.deck_choices[0].select(4)
	settings.deck_choices[0].item_selected.emit(4)
	settings.deck_choices[1].select(1)
	settings.deck_choices[1].item_selected.emit(1)
	if not check(settings.value.bots[0].deckId == app.decks[1].id and settings.value.bots[1].mode == "generated", "Bots can choose saved decks or Forge-generated random decks"): return false
	settings.portrait_buttons[1].pressed.emit()
	if not check(settings.avatar_choices.size() == 126, "The profile picker offers Forge's complete default avatar selection"): return false
	await capture("app-forge-avatar-picker")
	settings.avatar_choices[125].pressed.emit()
	settings.portrait_buttons[0].pressed.emit()
	settings._import_portrait("res://assets/forge-avatars.png")
	if not check(not str(settings.value.human.portrait).is_empty() and settings.value.bots[0].avatar == 125, "Human custom pictures and Forge bot portrait presets are editable"): return false
	await capture("app-match-settings")
	app.get_window().size = Vector2i(1280, 800)
	await app.get_tree().create_timer(0.3).timeout
	await capture("app-match-settings-1280")
	if not check(settings.grid.get_global_rect().end.x <= app.size.x - 20 and settings.save_button.get_global_rect().end.y < app.size.y, "Settings remain usable at 1280 by 800"): return false
	for index in range(settings.deck_choices.size()):
		if not check(settings.names[index + 1].get_global_rect().end.x < settings.deck_choices[index].get_global_rect().position.x and settings.deck_choices[index].get_global_rect().end.x <= settings.remove_buttons[index].get_global_rect().position.x, "Name, deck and remove columns do not overlap at the smaller size"): return false
	if not await until(func(): return settings.deck_catalog.has("precon") and settings.deck_catalog.has("commander"), "Forge's bot deck catalogs"): return false
	if not check(settings.deck_catalog.precon.size() > 50 and settings.deck_catalog.commander.size() > 500, "Bot choices expose Forge's full precon and random-commander lists"): return false
	print("BOT DECKS: %d precons; %d commanders" % [settings.deck_catalog.precon.size(), settings.deck_catalog.commander.size()])
	for index in range(2):
		var mode: String = ["precon", "commander"][index]
		var choice: OptionButton = settings.deck_choices[index]
		for option in range(choice.item_count):
			if choice.get_item_metadata(option).mode == mode:
				choice.select(option)
				choice.item_selected.emit(option)
				break
		settings.deck_search.text = "Adaptive Enchantment" if index == 0 else "Talrand, Sky Summoner"
		settings.deck_search.text_changed.emit(settings.deck_search.text)
		if not check(settings.browser_entries.size() == 1 and settings.browser_entries[0].get("legal", true), "Search finds the selected Forge deck or commander"): return false
		await capture("app-bot-precon-picker" if index == 0 else "app-bot-commander-picker")
		if not check(settings.deck_browser.size.x <= app.size.x and settings.deck_browser.size.y <= app.size.y - 40 and settings.deck_browser.get_ok_button().get_global_rect().end.y < settings.deck_browser.size.y, "Forge deck picker and confirmation fit the smaller viewport"): return false
		settings.deck_list.select(0)
		settings.deck_list.item_selected.emit(0)
		settings.deck_browser.confirmed.emit()
		if not check(not settings.deck_browser.visible and settings.value.bots[index].mode == mode and settings.value.bots[index].deckId == settings.browser_entries[0].id, "Choosing a listed deck stores its source and exact identity"): return false
	if not check(settings._valid(), "Both selected Forge deck sources are valid match settings"): return false
	await capture("app-forge-bot-decks-selected")
	var chosen_precon_id: String = settings.value.bots[0].deckId
	settings.save_button.pressed.emit()
	if not await until(func(): return app.busy and app.computer.phase == "settings_exit" and float(app.computer.world.screen_material.get_shader_parameter("channel_progress")) > 0.0, "settings exit retunes the fullscreen CRT"): return false
	if not check(app.view == "settings_transition" and app.computer.visible and app.settings_viewport != null and not app.computer.shelf.enabled, "Exit animation retains the settings frame and locks menu input until returning"): return false
	if not check(app.computer.world.animation.is_running() and float(app.computer.world.screen_material.get_shader_parameter("clean_view")) < 1.0, "Exit CRT retune runs during the camera pullback"): return false
	if not check(app.computer.world.screen.scale.is_equal_approx(Vector3.ONE) and app.computer.world.screen.material_override == app.computer.world.crt_material, "Settings exit retains the fixed physical glass and depth-tested bezel"): return false
	await capture("app-match-settings-exit")
	if not await until(func(): return app.view == "menu" and not app.busy, "save settings and zoom back out"): return false
	var stored: Dictionary = preload("res://scripts/app/MatchPreferences.gd").read()
	if not check(stored.human.name == "Commander pilot" and app.match_preferences.human.portrait == stored.human.portrait and stored.bots[0].avatar == 125, "Profiles and deck choices persist for the next match"): return false
	if not check(stored.bots[0].mode == "precon" and stored.bots[1].mode == "commander" and stored.bots[0].deckId == chosen_precon_id, "Selected Forge deck identities persist with player profiles"): return false
	app.get_window().size = Vector2i(1600, 900)
	await app.get_tree().create_timer(0.2).timeout
	await app.open_match_settings()
	var world: Node3D = app.computer.world
	var half: Vector2 = world.SCREEN_SIZE * 0.5
	var top_left: Vector2 = world.camera.unproject_position(world.SCREEN_CENTER + Vector3(-half.x, half.y, 0))
	var bottom_right: Vector2 = world.camera.unproject_position(world.SCREEN_CENTER + Vector3(half.x, -half.y, 0))
	if not check(top_left.x < 0 and top_left.y < 0 and bottom_right.x > app.size.x and bottom_right.y > app.size.y and world.screen.scale.is_equal_approx(Vector3.ONE), "Fixed monitor glass covers a widescreen viewport at the fullscreen handoff"): return false
	await capture("app-match-settings-16x9")
	if not check(app.match_settings.deck_catalog.has("precon") and app.match_settings.catalog_request == -1 and app.match_settings.deck_pick_buttons[1].text == "Talrand, Sky Summoner", "Reopening settings reuses the catalog and shows the saved commander choice"): return false
	app.match_settings.names[0].text_changed.emit("Discard this change")
	app.match_settings.canceled.emit()
	if not await until(func(): return app.view == "menu" and not app.busy, "cancel settings and return to the PC"): return false
	if not check(app.match_preferences.human.name == "Commander pilot", "Cancel preserves the last saved match settings"): return false
	app.get_window().size = Vector2i(1600, 1000)
	await app.get_tree().create_timer(0.2).timeout
	return true

func enter_game(keyboard: bool = false) -> bool:
	if "--app-night-cinematics" in OS.get_cmdline_user_args():
		app.computer.set_dark_mode(true, false, false)
		await app.get_tree().process_frame
		await app.get_tree().process_frame
	# Click the projected hit area of the real key on the case, outside the CRT.
	if keyboard:
		var event := InputEventKey.new()
		event.keycode = KEY_ENTER
		event.pressed = true
		if DisplayServer.get_name() == "headless": app.computer._unhandled_key_input(event)
		else: app.get_viewport().push_input(event, true)
		await app.get_tree().process_frame
	else: await click_control(app.start_button)
	if not check(app.busy and app.computer.phase == "play_press", "Physical Play starts the key press before preparing artwork or loading the floppy"): return false
	await app.get_tree().create_timer(0.03).timeout
	if not check(app.computer.world.play_key.position.z < app.computer.world.PLAY_CENTER.z - 0.01 and not app.computer.world.disk.visible, "Play key visibly depresses before the floppy lifts"): return false
	app._render_deck()
	if not check(app.computer.phase == "play_press", "Background deck refresh cannot reset the PLAY release before a launch key exists"): return false
	await capture("app-play-button-press")
	var press_started_at: int = app.computer.world.play_down_at
	if not check(app.computer.normal_body.visible and not app.computer.boot_body.visible, "The deck console stays visible while the disk approaches, without an intermediate inserting screen"): return false
	await capture("app-game-loading")
	if not await until(func(): return app.computer.phase == "inserting" or (is_instance_valid(app.confirm) and app.confirm.visible), "The PLAY rebound completes before disk insertion without waiting for artwork"): return false
	if is_instance_valid(app.confirm) and app.confirm.visible:
		await capture("app-artwork-gate-failure")
		return check(false, "Artwork gate blocked launch: " + app.confirm.dialog_text)
	if not check(app.computer.world.play_key.position.is_equal_approx(app.computer.world.PLAY_CENTER) and not app.computer.world.play_animation.is_running(), "PLAY is fully raised before the floppy moves"): return false
	var key: String = app.launch_key
	await app.get_tree().create_timer(0.6).timeout
	await capture("app-deck-insertion")
	if not await until(func(): return is_instance_valid(app.computer.boot_log) and app.computer.boot_log.active, "Inserted disk starts its terminal boot log"): return false
	var boot: Control = app.computer.boot_log
	if not check(app.computer.phase == "inserting" and not app.computer.inserted, "The new boot log starts as the floppy enters the drive, before insertion finishes"): return false
	if not check(boot.disk_name == app.match_deck.name.to_upper() and boot.card_count == 100 and boot.commander.contains("ATRAXA"), "The monitor boot log identifies the actual inserted disk"): return false
	if not check(app.computer.world.drive_log_active and app.computer.world.drive_pulses > 0, "Boot printing drives physical LED activity"): return false
	await capture("app-match-boot-log")
	app.start_game() # the busy guard must ignore a second click
	if not check(app.busy and app.launch_key == key, "Starting twice must not create another launch request"): return false
	if not await until(func(): return boot.done_count >= 3, "Disk metadata prints before the engine stage"): return false
	await capture("app-match-boot-rules")
	if not _console_safe(boot): return false
	if not await until(func(): return boot.complete and boot.value == 1, "Real table readiness completes the boot log"): return false
	await capture("app-match-boot-ready")
	if not _console_safe(boot): return false
	if not await until(func(): return app.computer.phase == "materializing", "completed loading bar reveals the board before camera movement"): return false
	if not check(app.computer.world.play_down_at == press_started_at, "Launch waits for the original press instead of replaying the feedback after loading"): return false
	if not check(boot.complete and boot.done_count == 6 and boot.value == 1 and boot.ready_age >= 0.65 and app.computer.world.camera.transform.is_equal_approx(app.computer.world.home_transform), "All boot stages complete and READY holds before the camera moves"): return false
	await app.get_tree().create_timer(0.4).timeout
	await capture("app-board-materializing")
	if not check(app.game.transition_preview and is_zero_approx(app.game.modal.modulate.a) and is_zero_approx(app.game.opening_hand.modulate.a), "Materialization shows the board grid instead of the pending hand/decision overlay"): return false
	if not check(is_equal_approx(app.game.table_backdrop.cinematic_tint, 1.0), "The initial board grid is teal"): return false
	for layer in app.game.get_children():
		if layer is CanvasItem and layer != app.game.table_backdrop and layer != app.game.toast:
			if not check(is_zero_approx(layer.modulate.a), "Only the grid is visible during materialization: " + str(layer.name)): return false
	if not check(app.computer.phase == "materializing" and app.computer.world.camera.transform.is_equal_approx(app.computer.world.home_transform), "The board materializes on the stationary monitor"): return false
	if not await until(func(): return app.computer.phase == "zooming", "camera zoom starts after the board settles"): return false
	if not await until(func(): return app.game.transition_reveal, "cards and UI begin fading only after the monitor zoom"): return false
	if not check(not app.computer.visible and app.busy and app.game.get_parent() == app.content and is_zero_approx(app.game.table_backdrop.cinematic_tint), "UI fades over the gray grid after the fullscreen handoff"): return false
	await app.get_tree().create_timer(0.2).timeout
	if not check(app.game.presentation_alpha > 0.0 and app.game.presentation_alpha < 1.0, "Foreground UI uses a gradual fade"): return false
	await capture("app-ui-fade-in")
	if not await until(func(): return app.game != null and app.view == "game", "monitor zoom completes into the playable Commander scene"): return false
	if not check(app.computer.inserted and app.game.get_parent() == app.content and not app.computer.visible, "The inserted deck transitions from monitor rendering to native fullscreen input"): return false
	if not check(app.game.token_artwork.shared_images == app.images, "Visible gameplay artwork must use the same bounded queue and textures as deck warmup"): return false
	if not check(not app.game.transition_preview and app.game.modal.modulate.a > 0.0 and app.game.opening_hand.modulate.a > 0.0, "Pending game decisions become visible only after the camera zoom completes"): return false
	var disk: Node3D = app.computer.world.disk
	if not check((disk.quaternion * Vector3.LEFT).dot(Vector3.FORWARD) > 0.999 and (disk.quaternion * Vector3.BACK).dot(Vector3.UP) > 0.999, "Floppy enters shutter-first with its label facing up"): return false
	var drive: Node3D = app.computer.world
	if not check(disk.position.x - disk.scale.y * 0.5 >= drive.DRIVE_OUTLINE[1].x + drive.DRIVE_INSET and disk.position.x + disk.scale.y * 0.5 <= drive.DRIVE_OUTLINE[0].x - drive.DRIVE_INSET and disk.scale.z * 0.04 < 0.08, "Floppy fits the centered drive mouth"): return false
	print("APP MATCH PID: ", app.match_pid)
	var driver := Driver.new()
	driver.ui = app.game
	driver.deadline = deadline
	for index in range(100):
		if not await driver.wait_ready(): return false
		var state: Dictionary = app.game.snapshot
		if is_instance_valid(app.game.modal_panel) and app.game.modal_panel is CoinToss:
			await app.get_tree().create_timer(0.1).timeout
			continue
		if state.prompt.get("inputKind", "") == "InputPassPriority":
			if not check(state.players.size() == app.match_preferences.bots.size() + 1 and state.players[0].zones.Command.any(func(card): return card.name == "Atraxa, Praetors' Voice"), "Load the selected saved Commander deck and configured number of bots"): return false
			if not check(state.players[0].name == app.match_preferences.human.name and state.players[0].get("portrait", "") == app.match_preferences.human.portrait and app.game.hud_values[0].portrait.portrait != null, "Names and custom portraits reach the actual match"): return false
			for bot_index in range(app.match_preferences.bots.size()):
				if not check(state.players[bot_index + 1].name == app.match_preferences.bots[bot_index].name, "Configured bot names reach Forge"): return false
				var bot: Dictionary = app.match_preferences.bots[bot_index]
				if bot.mode in ["precon", "commander"]:
					var entry: Dictionary = app.bot_deck_catalog[bot.mode].filter(func(deck): return deck.id == bot.deckId)[0]
					var expected: String = entry.name if bot.mode == "commander" else entry.commander
					var commanders: Array = state.players[bot_index + 1].zones.Command
					if not check(not commanders.is_empty() and commanders.all(func(card): return expected.contains(card.name)), "The running bot has the commander from its selected Forge source"): return false
			return await until(func(): return not app.game.opening_hand.visible, "opening hand finishes revealing the playable table")
		if not state.asks.is_empty(): driver.submit_choice()
		elif state.prompt.get("inputKind", "") == "InputConfirmMulligan":
			if not check(not app.game.hand_root.visible and state.players[0].zones.Hand.all(func(card): return not app.game.cards.has(card.id)), "The opening hand has no battlefield cards before Keep"): return false
			await capture("app-opening-hand-before-keep")
			app.game.opening_hand.submit("ok")
		elif Starting.needs_selection(state):
			if app.game.modal_panel is Starting: app.game.modal_panel.buttons[0].pressed.emit()
			else: await app.get_tree().create_timer(0.1).timeout
		elif state.prompt.okEnabled: app.game._primary_action()
		elif state.prompt.get("inputKind", "") in ["", "InputLockUI"]:
			await app.get_tree().create_timer(0.1).timeout
		else: return check(false, "Unexpected startup decision: " + str(state.prompt))
	return check(false, "Opening hand did not reach the table")

func leave_game() -> bool:
	var retained: Control = app.game
	var board_frame: Image
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		board_frame = app.get_viewport().get_texture().get_image()
	app.game.library_return_button.pressed.emit()
	if not check(app.confirm.visible and app.confirm.dialog_text.contains("stay running"), "Styled Main menu confirmation explains retained game state"): return false
	await app.get_tree().create_timer(0.2).timeout
	await capture("app-leave-confirmation")
	app.confirm.confirmed.emit()
	if not await until(func(): return app.computer.phase == "returning", "leaving pulls back into the computer before ejection"): return false
	await app.get_tree().create_timer(1.65).timeout
	for tile in app.computer.tiles:
		if tile.deck.id == app.computer.selected_id:
			if not check(tile.cover_hidden and not tile.cover.visible, "Returning deck reserves an empty carousel slot, including after a resumed game"): return false
	var held_board: Texture2D = app.computer.world.crt_material.get_shader_parameter("display_texture")
	if not check(held_board != app.computer.monitor_view.get_texture(), "The game board stays on the CRT during deck ejection"): return false
	if board_frame != null:
		var captured := held_board.get_image()
		if not check(captured.get_size() == board_frame.get_size(), "The returning CRT captures the full game viewport"): return false
		var difference := 0.0
		var samples := 0
		for y in range(0, captured.get_height(), 16):
			for x in range(0, captured.get_width(), 16):
				var actual := captured.get_pixel(x, y)
				var expected := board_frame.get_pixel(x, y)
				difference += (absf(actual.r - expected.r) + absf(actual.g - expected.g) + absf(actual.b - expected.b)) / 3.0
				samples += 1
		if not check(difference / samples < 0.035, "The CRT must show the uncovered board, without the leave popup or its shade: " + str(difference / samples)): return false
	await capture("app-disk-ejection")
	await app.get_tree().create_timer(1.45).timeout
	await capture("app-session-disk-ejection")
	var tuning: float = app.computer.world.crt_material.get_shader_parameter("channel_progress")
	if not check(app.computer.phase == "session_ejecting" and app.computer.world.disk.visible and app.computer.session_disk.disk.cover_hidden and tuning > 0.0 and tuning < 1.0, "The monitor loses its signal while the session disk is physically ejecting"): return false
	await capture("app-monitor-channel-change")
	if not await until(func(): return app.game == retained and app.parked and app.view == "menu" and not app.busy, "live game set aside with its session disk"): return false
	for tile in app.computer.tiles:
		if tile.deck.id == app.computer.selected_id:
			if not check(not tile.cover_hidden and tile.cover.visible and absf((tile.get_global_transform() * (tile.size * 0.5)).x - app.size.x * 0.5) < 1.0, "The landed deck becomes the single centered carousel disk"): return false
	return check(app.game.process_mode == Node.PROCESS_MODE_DISABLED and not app.game.visible and app.computer.session_disk != null, "Parked table cannot intercept menu input and keeps its session disk")

func _silent_tree(node: Node) -> bool:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D: return false
	for child in node.get_children():
		if not _silent_tree(child): return false
	return true

## The whole joining path through the real application: a second lobby client hosts on the same library
## service, this app joins over the online port, and the host's start runs the normal disk insertion.
func online_join_check() -> bool:
	deadline += 240000
	var hosting: Node = preload("res://scripts/app/OnlineSession.gd").new()
	hosting.api = app.api
	app.add_child(hosting)
	var table := {"human": {"name": "Online host", "avatar": 1, "portrait": ""}, "bots": []}
	hosting.host(table, false)
	if not await until(func(): return hosting.is_hosting(), "the lobby opens"): return false
	app.net.join("127.0.0.1", {"name": "Joining player", "avatar": 2, "portrait": ""}, app.selected_id)
	if not await until(func(): return app.net.is_joined(), "this app takes a seat"): return false
	if not await until(func(): return hosting.players().size() == 1, "the host sees the player"): return false
	if not check(hosting.players()[0].name == "Joining player" and app.net.roster.size() == 2 and app.net.open_seats == 2, "The joined player and the open seats reach both sides"): return false
	if not check(not app.start_button.disabled and app.start_button.tooltip_text == "Press PLAY to ready up", "Joined players can press PLAY to ready up"): return false
	hosting.set_ready(true)
	if not await until(func(): return hosting.is_ready(), "host readies first"): return false
	if not check(not app.remote_game and not app.busy, "Host readiness alone never starts a joined player"): return false
	await click_control(app.start_button)
	if not await until(func(): return app.net.is_ready(), "PLAY marks the joined player ready"): return false
	if not check(app.start_button.disabled and app.start_button.tooltip_text == "Ready - waiting for the other players", "A ready player sees their waiting state"): return false
	if not check(app.computer.console.lobby_status == "[READY] WAITING FOR PLAYERS", "Readiness is visible on the CRT"): return false
	if not await until(func(): return hosting.all_ready(), "both sides are ready"): return false
	await capture("app-online-ready")
	var started: Dictionary = await call_api("match.start", {"id": app.selected_id, "launchKey": "online-join-check-launch-key", "setup": table})
	if not check(not started.has("error"), "The host starts a table of two people"): return false
	if not await until(func(): return app.remote_game, "the host's start reaches this app"): return false
	# The host's own seat has to be connected for Forge to tell the joined player who it waits for after a lost coin toss.
	var status: Dictionary = {}
	while status.get("state", "") != "ready" and Time.get_ticks_msec() < deadline:
		status = await call_api("match.status")
		await app.get_tree().create_timer(0.3).timeout
	var host_seat := WebSocketPeer.new()
	if not check(host_seat.connect_to_url(status.get("url", "")) == OK, "The host's own seat connects"): return false
	if not await until(func(): host_seat.poll(); return app.view == "game" and not app.busy and app.game != null, "the joined player's table is revealed through the disk insertion"): return false
	host_seat.close()
	if not check(not app.game.adapter.seat_token.is_empty() and app.game.adapter.url.ends_with(":36743/ws"), "The seat connects to the host with its token"): return false
	var state: Dictionary = app.game.snapshot
	if not check(state.players.size() == 2 and state.players[0].name == "Joining player" and state.players[1].name == "Online host", "The joined player sits at their own seat, facing the host"): return false
	await capture("app-online-joined-table")
	var saved: Dictionary = app.remote_store.read()
	var engine_session: String = app.game.adapter.session
	if not check(saved.get("session_id", "") == engine_session and not saved.get("token", "").is_empty(), "Joined seat credentials persist before a crash"): return false
	# Drop the client scene and all reconnect memory without sending Leave. The
	# host stays alive, just as it does when a joining player's process crashes.
	await app.request_leave_game()
	app.game.adapter.socket.close()
	app.game.adapter.socket.poll()
	app.game.get_parent().remove_child(app.game)
	app.game.queue_free()
	app.game = null
	app.remote_resume = {}
	app.remote_token = ""
	app.remote_game = false
	app.parked = false
	app.match_deck = {}
	app._restore_remote_session()
	app.show_menu()
	if not check(app.parked and app.game == null and app.remote_game and app.computer.session_disk != null and app.start_button.disabled, "A fresh client restores only a Resume disk and reserves the saved seat"): return false
	await capture("app-online-recovered-session")
	app.resume_game()
	if not await until(func(): return app.view == "game" and not app.busy and app.game != null, "the recovered disk reconnects and reveals the host's table"): return false
	if not check(app.game.adapter.session == engine_session and app.game.snapshot.players[0].name == "Joining player", "Crash recovery rejoins the same match and seat from a fresh authoritative snapshot"): return false
	if not check(app.game.adapter.pending.is_empty() and app.game.adapter.pending_answer == -1, "Recovered clients never replay a pending action or answer"): return false
	await capture("app-online-recovered-table")
	app.request_end_game()
	if not check(app.confirm.title == "Leave online game?", "A joined player leaves rather than ends the game"): return false
	var remote_adapter = app.game.adapter
	var stopped: Dictionary = await call_api("match.stop", {"session": started.get("session", "")})
	if not check(not stopped.has("error"), "The host's engine stops"): return false
	if not await until(func(): return app.game == null and not app.busy and not app.ending_session and app.computer.session_disk == null, "host stop automatically returns the joined app home"): return false
	if not check(remote_adapter.ended and remote_adapter.seat_token.is_empty() and not app.remote_game and app.remote_token.is_empty() and app.net.is_idle(), "Host stop clears the joined table, token and lobby without a confirmation"): return false
	if not check(app.remote_store.read().is_empty(), "Host stop removes persisted reconnect credentials"): return false
	if not await until(func(): return app.computer.world.play_enabled, "Play ready after the host ends an online game"): return false
	await capture("app-online-host-ended-home")
	# Reverse the roles: the real application hosts and must launch itself when
	# the other player's final PLAY arrives, without a second host click.
	var original_preferences: Dictionary = app.match_preferences.duplicate(true)
	app.match_preferences = {"human": original_preferences.human, "bots": []}
	app.net.host(app.match_preferences, false)
	if not await until(func(): return app.net.is_hosting(), "this application hosts"): return false
	var remote_start := {}
	hosting.match_started.connect(func(url, token): remote_start.merge({"url": url, "token": token}))
	hosting.join("127.0.0.1", {"name": "Ready friend", "avatar": 2, "portrait": ""}, app.selected_id)
	if not await until(func(): return hosting.is_joined() and app.net.players().size() == 1, "the friend joins the application host"): return false
	await click_control(app.start_button)
	if not await until(func(): return app.net.is_ready(), "the application host presses PLAY"): return false
	if not check(app.game == null and not app.busy and app.computer.phase == "idle", "Host PLAY rebounds and waits without inserting a disk"): return false
	hosting.set_ready(true)
	if not await until(func(): return not remote_start.is_empty(), "the last ready player automatically launches the host"): return false
	var hosted_status: Dictionary = {}
	while hosted_status.get("state", "") != "ready" and Time.get_ticks_msec() < deadline:
		hosted_status = await call_api("match.status")
		if not check(hosted_status.get("state", "") != "failed", "the automatic host match starts successfully"): return false
		await app.get_tree().create_timer(0.3).timeout
	var remote_seat := WebSocketPeer.new()
	var connected := [false]
	if not check(remote_seat.connect_to_url(remote_start.url) == OK, "the friend's seat connects to the automatic launch"): return false
	var host_revealed := func():
		remote_seat.poll()
		if remote_seat.get_ready_state() == WebSocketPeer.STATE_OPEN and not connected[0]:
			remote_seat.send_text(JSON.stringify({"type": "auth", "token": remote_start.token}))
			connected[0] = true
		return app.view == "game" and not app.busy and app.game != null
	if not await until(host_revealed, "the automatically launched host table is revealed"): return false
	if not check(not app.remote_game and app.online_table, "Automatic start preserves the host's own seat"): return false
	await capture("app-online-host-ready-table")
	app.request_end_game()
	app.confirm.confirmed.emit()
	if not await until(func(): return app.game == null and not app.busy and not app.ending_session, "the application host ends its test match"): return false
	remote_seat.close()
	app.match_preferences = original_preferences
	hosting.queue_free()
	return true

func end_with_format(from_game: bool) -> bool:
	var info: Dictionary = app._session_info()
	var deck_faces: Array = app.computer.tiles.map(func(tile): return tile.cover.texture)
	var stop_requests := [0]
	var count_stop := func(_id, op, _result):
		if op == "match.stop": stop_requests[0] += 1
	app.api.response.connect(count_stop)
	app.request_end_game()
	if not check(app.confirm.visible and not app.busy and app.game != null, "End Game requires confirmation at both entry points"): return false
	app.confirm.confirmed.emit()
	if not await until(func(): return app.computer.phase == "formatting", "session returns home before formatting"): return false
	var prefix := "app-format-active" if from_game else "app-format-parked"
	if not check(app.busy and not app.computer.shelf.enabled and app.computer.settings_button.disabled and app.computer.editor_button.disabled, "Format locks all home and session interactions"): return false
	if not await until(func(): return is_instance_valid(app.computer.format_log), "FORMAT A: plays on the screen"): return false
	if not check(not app.computer.world.disk.visible, "No floppy moves during the screen-only wipe"): return false
	await capture(prefix + "-approach")
	var log: Control = app.computer.format_log
	if not check(app.computer.world.drive_format_active, "Amber drive activity accompanies the on-screen wipe"): return false
	await capture(prefix + "-entering")
	if not await until(func(): return log.done_count >= 2, "format prints its session metadata"): return false
	if not check(log.rows[0] == "FORMAT A: " + str(info.name).to_upper() and log.rows[1].contains("LIFE %d" % info.life), "Format uses real session data"): return false
	if not _console_safe(log): return false
	if not check(app.game == null and app.session.is_empty() and app.end_cleanup_done, "Real engine acknowledgment clears the match before the animation finishes"): return false
	if not check(_silent_tree(app.computer), "Format creates no audio players"): return false
	await capture(prefix + "-progress")
	if not await until(func(): return log.complete and log.value == 1.0, "SESSION ERASED and a full block meter"): return false
	if not check(not app.computer.world.disk.visible, "The formatted disk stays inside the drive"): return false
	await capture(prefix + "-erased")
	if not await until(func(): return not app.busy and app.computer.session_disk == null, "session disk is removed and input restored"): return false
	if not check(app.computer.format_log == null and not app.computer.world.disk.visible and not app.computer.world.drive_format_active and not app.computer.world.working, "Format leaves the drive empty and LED idle"): return false
	if not check(app.computer.shelf.enabled and not app.computer.settings_button.disabled and not app.computer.editor_button.disabled and not app.computer.light_switch.disabled, "All home controls are restored"): return false
	if not await until(func(): return app.computer.world.play_enabled, "Play ready after format"): return false
	for index in range(app.computer.tiles.size()):
		if not check(not app.computer.tiles[index].cover_hidden and app.computer.tiles[index].cover.texture == deck_faces[index], "Formatting preserves every saved deck face"): return false
	if not check(stop_requests[0] == 1, "Confirmed end stops the owned match exactly once"): return false
	app.api.response.disconnect(count_stop)
	await capture(prefix + "-empty")
	return true

func run(root: Control) -> void:
	app = root
	preload("res://tests/RemoteSessionChecks.gd").new().run(app.remote_store.path + ".checks")
	app.api.response.connect(_fixture_match_artwork)
	await preload("res://tests/MatchBootLogChecks.gd").new().run(app)
	await preload("res://tests/FormatLogChecks.gd").new().run(app)
	if not check(preload("res://tests/CardAccentChecks.gd").run(), "Card accent handles artwork, borders, neutral cards, minor highlights and hue wrap"): return
	deadline = Time.get_ticks_msec() + 215000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--app-capture="): capture_root = arg.trim_prefix("--app-capture=")
	app.api.response.connect(func(id, _op, result): responses[id] = result)
	app.api.response.connect(func(_id, operation, result):
		if quitting and operation == "match.stop":
			if check(result.state == "stopped", "Quitting must stop the owned match"):
				print("PASS: application navigation (match settings, profiles, saved/generated decks, two/three/four-player Commander, retained draft, session ownership, resume/end and quit cleanup)"))
	app.api.failed.connect(func(id, error): errors[id] = error)
	if not check(app.view == "loading" and not app.startup_done and app.startup_progress.visible, "Show startup progress before the backend exists"): return
	await capture("app-startup-loading")
	if not check(is_zero_approx(app.startup_progress.target), "Startup percentage waits for a real service milestone"): return
	var initial_elapsed: float = app.startup_progress.elapsed
	await app.get_tree().create_timer(0.35).timeout
	if not check(is_zero_approx(app.startup_progress.progress.value) and app.startup_progress.elapsed > initial_elapsed, "Diagnostic terminal stays active while progress waits for real services"): return
	app.startup_progress.verification_started.connect(func():
		if not check(app.startup_progress.stage_index == 6 and is_equal_approx(app.startup_progress.progress.value, 1.0) and not app.startup_done, "Verification reaches 100% after deck data arrives and before the menu opens"): return
		await capture("app-startup-verified"))
	var startup_seen := [false]
	# The computer is created after verification; observe its real transition
	# while keeping startup_done false until the console is ready for input.
	app.startup_progress.verification_started.connect(func():
		if not await until(func(): return app.computer != null and app.computer.phase == "startup_pullback", "startup pulls back onto PC monitor"): return
		startup_seen[0] = true
		if not check(app.busy and not app.startup_done and app.startup_progress.get_parent() is SubViewport, "Startup remains live on an input-disabled viewport during the pullback"): return
		await app.get_tree().create_timer(0.65).timeout
		await capture("app-startup-pullback")
		if not await until(func(): return app.computer.phase == "startup_console", "diagnostic terminal tunes into deck console on the PC"): return
		await capture("app-startup-on-monitor"))
	print("APP STARTUP VISIBLE") # runner starts Forge only after this screen is visible
	if "--app-startup-failure" in OS.get_cmdline_user_args():
		if not await until(func(): return app.startup_progress.failed, "actual backend startup failure displayed"): return
		if not check(not app.startup_progress.progress.visible and app.view == "loading", "Startup errors keep the screen open without an endless progress bar"): return
		await capture("app-startup-error")
		print("PASS: startup failure screen (visible before backend start, actual initialization failure, readable error and Quit)")
		app._request_quit()
		return
	if not await until(func(): return app.online and app.decks.filter(func(deck): return deck.get("source", "") == "custom").size() == 18, "menu deck list"): return
	if not check(app.decks.size() > 150 and app.decks.slice(0, 18).all(func(deck): return deck.source == "custom") and app.decks.slice(18).all(func(deck): return deck.source == "precon" and deck.readOnly), "Forge's bundled precons are listed after the saved decks"): return
	if not await until(func(): return app.startup_done, "system check and CRT transition into the menu"): return
	# The navigation checks below index the fixture decks; precons get their own checks.
	app.computer.set_deck_filter("custom", false)
	if not check(startup_seen[0] and app.computer.world.camera.transform.is_equal_approx(app.computer.world.home_transform) and app.computer.phase == "idle" and app.startup_progress.process_mode == Node.PROCESS_MODE_DISABLED, "Startup reaches the home camera and restores controls only after the monitor transition"): return
	if not check(app.view == "menu" and app.game == null, "Opening the menu must not start a game"): return
	if not check_carousel_seams(): return
	var placement = preload("res://scripts/app/WindowPlacement.gd")
	# A second monitor above the chosen monitor must never receive the title bar.
	for origin in [Vector2i.ZERO, Vector2i(0, -1440), Vector2i(-2560, 120)]:
		var usable := Rect2i(origin, Vector2i(2560, 1400))
		var client: Rect2i = placement.client_rect(Vector2i(2560, 1440), usable, Vector2i(16, 39), Vector2i(8, 31))
		var decorated := Rect2i(client.position - Vector2i(8, 31), client.size + Vector2i(16, 39))
		if not check(usable.encloses(decorated) and absf(float(client.size.x) / client.size.y - 16.0 / 9.0) < 0.002, "Window including title bar fits one monitor and retains 16:9"): return
	var roomy := Rect2i(Vector2i.ZERO, Vector2i(3840, 2120))
	if not check(placement.client_rect(Vector2i(2560, 1440), roomy, Vector2i(16, 39), Vector2i(8, 31)).size == Vector2i(2560, 1440), "Keep the requested resolution when the decorated window fits"): return
	if not check(app.computer.forge_badge.tooltip_text == "Forge connected and running", "Menu connection badge reflects the live Forge connection"): return
	if not await until(func(): return app.selected_deck.get("legal", false), "main menu validates the selected disk for physical Play"): return
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	if "--app-night-baseline" in OS.get_cmdline_user_args() or "--app-night-review" in OS.get_cmdline_user_args():
		await preload("res://tests/NightLightingChecks.gd").new().run(app, self, "--app-night-baseline" in OS.get_cmdline_user_args())
		return
	if not check(app.computer.monitor_root.get_combined_minimum_size().y <= app.computer.DISPLAY_SIZE.y and app.computer.normal_body.get_global_rect().end.y <= app.computer.DISPLAY_SIZE.y, "The diagnostic deck console must fit inside the physical monitor"): return
	if not await console_check(): return
	initial_dark_mode = app.computer.dark_mode
	if "--app-night-cinematics" in OS.get_cmdline_user_args(): app.computer.set_dark_mode(true, false, false)
	if not await hardware_controls_check(): return
	if not await settings_check(): return
	app.computer.zoom_started.connect(func():
		await app.get_tree().create_timer(0.5).timeout
		if not check(app.game.transition_preview and app.game.table_backdrop.cinematic_tint > 0.0 and app.game.table_backdrop.cinematic_tint < 1.0, "The hidden-UI grid blends from teal to gray during camera zoom"): return
		await capture("app-monitor-zoom"))
	await capture("app-main-menu")
	var original_dark_mode: bool = initial_dark_mode
	app.computer.set_dark_mode(false, false, false)
	# Mid-fade frame: the floor, backdrop and environment must blend without a horizon seam.
	app.computer._apply_darkness(0.5)
	await capture("app-main-menu-lighting-midpoint")
	app.computer._apply_darkness(0.0)
	await click_control(app.computer.light_switch)
	await app.get_tree().create_timer(0.02).timeout
	if not check(app.computer.dark_mode and app.computer.darkness > 0.0 and app.computer.darkness < 1.0, "Light switch animates room lighting rather than snapping"): return
	await app.get_tree().create_timer(app.computer.LIGHTING_SECONDS + 0.2).timeout
	if not check(is_equal_approx(app.computer.darkness, 1.0) and app.computer.world.monitor_light.light_energy > 0.0 and app.computer.world.room_environment.background_color.is_equal_approx(Color("111719")) and app.computer.room_backdrop.color.is_equal_approx(Color("111719")), "Dark room reaches deep charcoal with matching backdrop and physical monitor light"): return
	var appearance := ConfigFile.new()
	if not check(appearance.load(app.computer.APPEARANCE_PATH) == OK and appearance.get_value("room", "dark_mode") == true, "Lighting preference persists across launches"): return
	await capture("app-main-menu-dark")
	app.get_window().size = Vector2i(1280, 800)
	await app.get_tree().create_timer(0.2).timeout
	await capture("app-main-menu-dark-1280")
	if not check(Rect2(Vector2.ZERO, app.size).encloses(app.computer.light_switch.get_global_rect()), "Light switch fits the smaller window"): return
	app.get_window().size = Vector2i(1600, 1000)
	await click_control(app.computer.light_switch)
	await app.get_tree().create_timer(app.computer.LIGHTING_SECONDS + 0.2).timeout
	if not check(not app.computer.dark_mode and is_zero_approx(app.computer.darkness) and is_zero_approx(app.computer.world.monitor_light.light_energy), "Switching back restores daylight and removes monitor spill"): return
	app.computer.set_dark_mode(original_dark_mode, false, true)
	if not capture_root.is_empty():
		app.computer.tiles[app.computer.shelf.selected_index].cover.texture.get_image().save_png(capture_root.path_join("app-floppy-detail.png"))
	await click_control(app.computer.tiles[1])
	if not await until(func(): return app.selected_id == app.decks[1].id and absf(app.computer.shelf.cursor - app.computer.shelf.target) < 0.01, "click neighboring deck and smoothly center it"): return
	if not check(app.computer.console.disk_name == app.decks[1].name, "Carousel selection updates the monitor's selected deck name"): return
	if not check(app.computer.tiles[1].scale.y > app.computer.tiles[0].scale.y, "Selected deck rises above smaller neighbors"): return
	if "--app-night-cinematics" in OS.get_cmdline_user_args(): await capture("night-deck-selected")
	await swipe_carousel(-app.computer.shelf.disk_height() * 1.02)
	if not await until(func(): return app.selected_id == app.decks[2].id and absf(app.computer.shelf.cursor - app.computer.shelf.target) < 0.01, "native mouse swipe selects the next deck"): return
	app.computer.select_id(app.decks[0].id)
	app._select_deck(0)
	if not await until(func(): return absf(app.computer.shelf.cursor - app.computer.shelf.target) < 0.01, "return to first deck"): return
	await carousel_key(KEY_LEFT)
	if not await until(func(): return app.selected_id == app.computer.decks[-1].id, "carousel wraps to the last deck"): return
	await carousel_key(KEY_RIGHT)
	if not await until(func(): return app.selected_id == app.decks[0].id and absf(app.computer.shelf.cursor - app.computer.shelf.target) < 0.01, "carousel wraps back to the first deck"): return
	if not await deck_filter_check(): return
	if not await deck_search_check(): return
	if not await online_join_check(): return
	print("PASS: online join (seat, host start, disk insertion, table reveal, leave)")
	app.show_menu()
	app.get_window().size = Vector2i(1280, 800)
	await app.get_tree().create_timer(0.4).timeout
	await capture("app-main-menu-1280")
	if not check(app.computer.shelf.get_global_rect().end.y <= app.size.y, "Computer and shelf fit at 1280x800: " + str(app.computer.shelf.get_global_rect())): return
	app.get_window().size = Vector2i(1600, 1000)
	if "--app-menu-preview" in OS.get_cmdline_user_args():
		print("PASS: computer menu preview (native materials, two window sizes, carousel clicks, swipe, depth and wrapping)")
		app.get_tree().quit()
		return
	# A genuine lookup failure stays in the background and cannot open a modal.
	var unavailable := {"key": "Missing artwork regression " + str(Time.get_ticks_usec()), "name": "Unavailable card face", "imageKey": "c:Unavailable card face"}
	app.images.warm_deck({"sections": {"Main": [unavailable]}})
	if not await until(func(): return app.images.failures.has(unavailable.key), "background missing-face lookup finishes"): return
	if not check(not app.busy and app.computer.phase == "idle" and (not is_instance_valid(app.confirm) or not app.confirm.visible), "Missing artwork stays nonblocking without a retry popup"): return
	var home_shelf_y: float = app.computer.shelf.position.y
	var home_disk_height: float = app.computer.shelf.disk_height()
	var editor_click_start := Time.get_ticks_usec()
	if "--app-night-cinematics" in OS.get_cmdline_user_args(): app.computer.set_dark_mode(true, false, false)
	await click_control(app.computer.editor_button)
	print("EDITOR CLICK HANDLER: ", (Time.get_ticks_usec()-editor_click_start)/1000.0, " ms including input frames")
	await app.get_tree().create_timer(0.18).timeout
	if not check(app.computer.editor_progress > 0 and app.computer.editor_progress < 1 and app.computer.shelf.position.y < home_shelf_y, "Deck Editor scrolls the existing home carousel upward"): return
	if not check(app.computer.atmosphere.position.y == app.computer.world_container.position.y, "Home speckles travel with the room instead of remaining over the editor"): return
	if not check(app.computer.shelf.mode_transition and app.computer.shelf.mode_ghosts.any(func(ghost): return ghost.visible and ghost.modulate.a > 0 and ghost.modulate.a < 1), "Entering the finite editor fades visible wrapped edge disks instead of deleting them instantly"): return
	if not check(is_equal_approx(app.computer.shelf.tiles[app.computer.shelf.selected_index].modulate.a, 1.0), "The shared selected floppy stays opaque during the layout change"): return
	if not check(app.editor == null, "The first editor scroll begins before constructing or loading the editor"): return
	await capture("app-editor-scroll")
	if not await until(func(): return app.editor != null and not app.editor.draft.is_empty() and not app.busy, "carousel deck editor"): return
	if not check(not app.computer.shelf.mode_transition and app.computer.shelf.mode_ghosts.is_empty() and app.computer.shelf.retired_tiles.is_empty(), "Completed layout transitions release their temporary edge disks"): return
	if not check(app.computer.shelf.position.y == 70 and app.computer.world_container.position.y < 0 and app.editor.draft.id == app.computer.selected_id, "The shared carousel selects the deck above its editor cards"): return
	if not check(app.computer.atmosphere.get_global_rect().end.y < app.editor.card_scroll.get_global_rect().position.y, "The home speckle layer must clear the editor's card grid"): return
	if not check(not app.computer.atmosphere.visible, "The completed editor transition clears speckles from the whole editor"): return
	if not check(_room_above_editor(), "The closer-framed computer clears the editor header completely"): return
	print("EDITOR SETUP: ", app.last_editor_setup_ms, " ms; GRID: ", app.editor.last_card_render_ms, " ms")
	if not check(app.editor.file_dialog == null and app.editor.images == app.images and app.editor.api == app.api, "First entry reuses shared services and defers filesystem UI"): return
	var editor_shelf: Control = app.computer.shelf
	if not await editor_precon_check(): return
	if not check(is_equal_approx(editor_shelf.disk_height(), home_disk_height), "Editor floppies retain their main menu size"): return
	var color_index: int = editor_shelf.selected_index
	var colored_id: String = editor_shelf.decks[color_index].id
	var selected_before_color: String = app.editor.draft.id
	var context_click := InputEventMouseButton.new()
	context_click.button_index = MOUSE_BUTTON_RIGHT
	context_click.pressed = true
	context_click.position = editor_shelf.tiles[color_index].get_transform() * (editor_shelf.tiles[color_index].size * 0.5)
	editor_shelf._carousel_input(context_click)
	if not check(editor_shelf.color_menu.visible and editor_shelf.color_deck_id == colored_id and app.editor.draft.id == selected_before_color, "Right-click opens the hit floppy's color menu without switching the deck"): return
	await capture("app-floppy-color-menu")
	editor_shelf.color_menu.id_pressed.emit(5)
	editor_shelf.color_menu.hide()
	if not check(editor_shelf.tiles[color_index].shell_color == editor_shelf.Appearance.COLORS[5], "A preset recolors the floppy shader immediately"): return
	var appearance_file := ConfigFile.new()
	if not check(appearance_file.load(editor_shelf.Appearance.settings_path()) == OK and appearance_file.get_value("colors", colored_id) == editor_shelf.Appearance.COLORS[5], "Floppy colors persist to the isolated preference file"): return
	editor_shelf._open_color_menu(color_index)
	editor_shelf.color_menu.hide()
	editor_shelf._color_action(8)
	if not check(editor_shelf.color_dialog.visible and not editor_shelf.color_picker.edit_alpha, "Custom colors have an opaque color picker"): return
	await app.get_tree().process_frame
	var sampler: Control = editor_shelf.card_sampler
	if not check(sampler.pixels != null, "The eyedropper shows this deck's original card artwork"): return
	var hover := InputEventMouseMotion.new()
	hover.position = sampler.preview.size * 0.5
	var previous_color: Color = editor_shelf.color_picker.color
	sampler.preview.gui_input.emit(hover)
	var center_pixel := Vector2i(sampler.pixels.get_size() / 2)
	var expected_color: Color = sampler.pixels.get_pixel(center_pixel.x, center_pixel.y)
	expected_color.a = 1.0
	if not check(sampler.sampled_color.is_equal_approx(expected_color) and editor_shelf.color_picker.color == previous_color, "Hover previews the exact artwork pixel without changing the selected color"): return
	var sample_click := InputEventMouseButton.new()
	sample_click.position = hover.position
	sample_click.button_index = MOUSE_BUTTON_LEFT
	sample_click.pressed = true
	sampler.preview.gui_input.emit(sample_click)
	if not check(editor_shelf.color_picker.color.is_equal_approx(expected_color) and editor_shelf.tiles[color_index].shell_color == editor_shelf.Appearance.COLORS[5], "Click selects the sampled shade and keeps the floppy unchanged until Apply"): return
	await capture("app-floppy-custom-color")
	editor_shelf.color_picker.color = Color("b04474")
	editor_shelf.color_dialog.confirmed.emit()
	editor_shelf.color_dialog.hide()
	editor_shelf.Appearance.settings = null
	if not check(editor_shelf.Appearance.color_for(editor_shelf.decks[color_index]) == Color("b04474"), "Custom colors reload from disk"): return
	var original_tile: Control = editor_shelf.tiles[color_index]
	editor_shelf.set_decks(app.decks, colored_id)
	if not check(editor_shelf.tiles[editor_shelf.selected_index] == original_tile and original_tile.shell_color == Color("b04474"), "Refreshing the library preserves the chosen floppy color"): return
	app.editor.select_deck("Deck-16.dck")
	if not await until(func(): return not app.editor.loading_deck and app.editor.draft.id == "Deck-16.dck", "select a saved deck for deletion"): return
	app.editor._show_delete()
	app.editor.delete_button.pressed.emit()
	if not await until(func(): return not app.editor.busy and not app.editor.loading_deck and not app.editor.draft.is_empty() and not app.decks.any(func(deck): return deck.id == "Deck-16.dck"), "deletion updates the shared home/editor library"): return
	var deleted_probe: Dictionary = await call_api("open", {"id": "Deck-16.dck"})
	if not check(not editor_shelf.decks.any(func(deck): return deck.id == "Deck-16.dck") and deleted_probe.has("error"), "Deleting in the embedded editor removes the floppy and its saved deck"): return
	if not check(not editor_shelf.looping and editor_shelf.copies.is_empty() and editor_shelf.decks.back().get("create", false), "The editor has finite ends and one plus floppy"): return
	var selected_editor_id: String = app.editor.draft.id
	editor_shelf.select_id(editor_shelf.decks[0].id)
	editor_shelf.step(-1)
	if not check(editor_shelf.selected_index == 0 and editor_shelf.target == 0, "The first editor deck cannot wrap backwards"): return
	editor_shelf.select_id(editor_shelf.CREATE_ID)
	editor_shelf.step(1)
	if not check(editor_shelf.selected_index == editor_shelf.decks.size()-1 and not app.editor.overlay.visible, "The final plus floppy cannot wrap forwards"): return
	if not await until(func(): return absf(editor_shelf.cursor-editor_shelf.target) < 0.05, "the last blank floppy is centered"): return
	await capture("app-editor-new-floppy")
	editor_shelf._emit_index(editor_shelf.decks.size()-1)
	if not check(app.editor.overlay.visible and app.editor.new_slot_active and app.editor.draft.id == selected_editor_id, "Clicking the plus opens create/import without replacing the current deck"): return
	await capture("app-editor-plus-floppy")
	app.editor.close_transient_ui()
	app.editor.density_slider.value = 7
	if not check(app.editor.card_grid.columns == 7, "The embedded editor responds immediately to its density slider"): return
	app.editor.density_slider.value = 0
	var first_editor_id: String = app.editor.draft.id
	var other_index: int = app.decks.find(app.decks.filter(func(deck): return deck.id != first_editor_id and deck.name.begins_with("Commander"))[0])
	app.computer.deck_selected.emit(other_index)
	if not await until(func(): return app.editor.draft.id == app.decks[other_index].id, "selecting a carousel floppy changes the editor deck"): return
	if not check(app.computer.selected_id == app.editor.draft.id and app.selected_id == app.editor.draft.id, "Editor and carousel selection remain synchronized"): return
	app.editor.name_edit.text = "Unsaved editor draft"
	app.editor.name_edit.text_changed.emit("Unsaved editor draft")
	app.computer.deck_selected.emit(app.decks.find(app.decks.filter(func(deck): return deck.id == first_editor_id)[0]))
	if not check(app.editor.pending_switch and app.editor.overlay.visible, "Switching carousel decks protects unsaved edits"): return
	app.editor.switch_cancel_button.pressed.emit()
	await app.get_tree().process_frame
	if not check(app.editor.draft.name == "Unsaved editor draft" and app.editor.dirty and app.computer.selected_id == app.editor.draft.id, "Canceling a deck switch restores the selected floppy and retains the draft"): return
	app.get_window().size = Vector2i(1280, 800)
	await app.get_tree().create_timer(0.3).timeout
	await capture("app-deck-editor-1280")
	if not check(_room_above_editor(), "The enlarged computer also clears the editor at 1280x800"): return
	if not check(app.editor.card_scroll.size.x > 900 and app.editor.card_scroll.size.y > 240, "The editor keeps cards readable below the carousel at 1280x800"): return
	app.computer.set_dark_mode(true, true, false)
	await app.get_tree().process_frame
	if not check(app.editor.styled_darkness == 1.0, "Editor palette is applied once at the target darkness during the room fade"): return
	await app.get_tree().create_timer(app.computer.LIGHTING_SECONDS + 0.15).timeout
	await capture("app-deck-editor-dark-1280")
	if not check(app.editor.darkness == 1.0, "Editor controls follow the home room's dark preference"): return
	app.computer.set_dark_mode(false, false, false)
	app.get_window().size = Vector2i(1600, 1000)
	await app.get_tree().create_timer(0.3).timeout
	await click_control(app.computer.editor_button)
	await app.get_tree().create_timer(0.18).timeout
	if not check(app.computer.shelf.mode_transition and not app.computer.shelf.enabled, "Returning home animates the carousel's layout while input remains locked"): return
	await capture("app-editor-return-scroll")
	if not await until(func(): return app.view == "menu" and not app.busy, "scroll back to the PC home screen"): return
	var home_color_tiles: Array = app.computer.shelf.tiles.filter(func(tile): return tile.deck.id == colored_id)
	if not check(home_color_tiles.size() == 1 and home_color_tiles[0].shell_color == Color("b04474"), "Returning home retains the editor's chosen floppy color"): return
	app.computer.shelf._open_color_menu(app.computer.shelf.tiles.find(home_color_tiles[0]))
	app.computer.shelf.color_menu.hide()
	app.computer.shelf._color_action(9)
	if not check(home_color_tiles[0].shell_color == app.computer.shelf.Appearance.default_color(colored_id), "Reset restores that deck's default shell color"): return
	if not check(app.view == "menu" and not app.editor.visible and app.computer.visible, "Clicking the editor Main menu button returns to the computer menu"): return
	if not check(app.computer.shelf.looping and not app.computer.shelf.show_create and app.computer.shelf.decks.size() == app.computer.decks.size(), "Returning home restores its looping carousel without a plus floppy"): return
	await app.open_editor()
	if not check(app.editor.draft.name == "Unsaved editor draft" and app.editor.dirty, "Editor navigation retains unsaved changes"): return
	await capture("app-deck-editor")
	await app.show_menu()
	if "--app-editor-preview" in OS.get_cmdline_user_args():
		if not check(app.computer.editor_progress == 0 and app.editor.dirty and not app.editor.visible, "Closing the editor returns home and retains its working draft"): return
		print("PASS: carousel editor preview (shared shelf transition, deck synchronization, unsaved switch guard, responsive light/dark layout and retained draft)")
		app.get_tree().quit()
		return
	app.show_commander()
	if not await until(func(): return app.selected_deck.get("legal", false), "valid Commander deck"): return
	await capture("app-commander-setup")
	app.get_window().size = Vector2i(1280, 800)
	await app.get_tree().create_timer(0.4).timeout
	if not check(app.computer.size.x <= app.size.x, "Computer setup fits at 1280x800"): return
	await capture("app-commander-setup-1280")
	app.get_window().size = Vector2i(1600, 1000)
	var invalid_index := -1
	for index in range(app.decks.size()):
		if app.decks[index].id == "Unfinished.dck": invalid_index = index
	app.computer.shelf.select_id(app.decks[invalid_index].id)
	app.computer.deck_selected.emit(invalid_index)
	if not await until(func(): return not app.selected_deck.is_empty() and app.selected_deck.id == "Unfinished.dck", "unfinished deck validation"): return
	if not check(app.start_button.disabled, "An unfinished Commander deck cannot start a game"): return
	await click_control(app.start_button)
	if not check(not app.busy and app.computer.phase == "idle" and not app.computer.world.disk.visible, "Physical Play ignores an invalid deck without a press or insertion"): return
	var invalid: Dictionary = await call_api("match.start", {"id": "Unfinished.dck", "launchKey": "invalid-deck-start-request"})
	if not check(invalid.has("error"), "The backend also validates the selected deck"): return
	app.computer.shelf.select_id(app.decks[0].id)
	app.computer.deck_selected.emit(0)
	if not await until(func(): return app.selected_deck.get("legal", false), "reselect saved deck"): return
	for mode in ["precon", "commander"]:
		var invalid_setup: Dictionary = app.match_preferences.duplicate(true)
		invalid_setup.bots[0].mode = mode
		invalid_setup.bots[0].deckId = "../not-a-Forge-deck"
		var rejected_source: Dictionary = await call_api("match.start", {"id": app.selected_id, "launchKey": "invalid-source-start-request", "setup": invalid_setup})
		if not check(rejected_source.has("error"), "The backend rejects unknown Forge deck identities before starting a match"): return
	var cancel_key := "cancel-owned-preparation-before-session-ack"
	var preparation: Dictionary = await call_api("match.start", {"id": app.selected_id, "launchKey": cancel_key})
	if not check(preparation.get("state", "") == "starting", "A prepared child waits for real Forge/deck readiness only"): return
	print("APP MATCH PID: ", preparation.pid)
	var wrong_cancel: Dictionary = await call_api("match.stop", {"launchKey": "a-different-preparation-key"})
	if not check(wrong_cancel.has("error"), "A different launch key cannot cancel a pending preparation"): return
	var canceled: Dictionary = await call_api("match.stop", {"launchKey": cancel_key})
	if not check(canceled.get("state", "") == "stopped", "The owner can cancel pending Start without waiting for its session acknowledgment"): return
	if not await enter_game(): return
	await capture("app-commander-game")
	var first_session: String = app.session
	var first_pid: int = app.match_pid
	var first_key: String = app.launch_key
	var retry: Dictionary = await call_api("match.start", {"id": app.selected_id, "launchKey": app.launch_key})
	if not check(retry.session == first_session and int(retry.pid) == first_pid, "Retrying a launch must return the same owned game"): return
	var wrong: Dictionary = await call_api("match.stop", {"session": "another-session"})
	if not check(wrong.has("error"), "A mismatched session must not stop a game"): return
	if not await leave_game(): return
	var retained: Control = app.game
	var decision: String = app.game.snapshot.prompt.get("inputKind", "")
	var running: Dictionary = await call_api("match.status")
	if not check(running.state == "ready" and int(running.pid) == first_pid and running.session == first_session, "Returning home keeps the same owned engine alive"): return
	if not check(app.start_button.disabled and app.computer.session_disk.info.name == app.match_deck.name, "Session disk identifies the live match and prevents replacing it accidentally"): return
	app.start_game()
	if not check(app.game == retained and app.session == first_session and not app.busy, "New-deck Play must not replace a parked match"): return
	await app.open_editor()
	if not check(app.view == "editor" and app.editor.dirty and app.game == retained, "The editor remains usable while a live match is parked"): return
	await app.show_menu()
	app.game.adapter.send_intent({"action": "refresh"})
	if not await until(func(): return app.game.snapshot.get("connectionReady", false), "background connection continues pumping while home"): return
	if not check(app.game.snapshot.prompt.get("inputKind", "") == decision, "The same pending decision survives navigation"): return
	await capture("app-menu-session-disk")
	app.get_window().size = Vector2i(1280, 800)
	await app.get_tree().create_timer(0.3).timeout
	await capture("app-menu-session-disk-1280")
	await click_control(app.computer.session_disk.resume_button)
	if not await until(func(): return is_instance_valid(app.computer.boot_log) and app.computer.boot_log.active and app.computer.boot_log.resuming and app.computer.boot_log.done_count >= 3, "Session resume uses its own live-engine boot log"): return
	await capture("app-session-boot-log-1280")
	if not _console_safe(app.computer.boot_log): return
	if not await until(func(): return app.view == "game" and not app.busy, "session floppy inserts and resumes the retained game"): return
	if not check(app.game == retained and not app.parked and app.session == first_session and app.match_pid == first_pid and app.game.snapshot.prompt.get("inputKind", "") == decision, "Resume preserves the exact game, engine and pending decision"): return
	await capture("app-resumed-game")
	if not await leave_game(): return
	await click_control(app.computer.session_disk.end_button)
	if not check(app.confirm.visible, "Ending a parked session requires confirmation"): return
	app.confirm.canceled.emit()
	if not check(app.game == retained and app.parked, "Cancel End Game preserves the live session"): return
	if not await end_with_format(false): return
	var stopped: Dictionary = await call_api("match.status")
	if not check(stopped.state == "stopped", "End Game must stop the owned match process"): return
	app.get_window().size = Vector2i(1600, 900)
	app.show_menu()
	if not await until(func(): return app.selected_deck.get("legal", false), "physical Play ready directly on the 16:9 main menu"): return
	app.match_preferences.bots = [app.match_preferences.bots[0].duplicate(true)]
	if not await enter_game(true): return
	await capture("app-commander-game-16x9")
	if not check(app.session != first_session and app.match_pid != first_pid, "A new game must have a fresh session and engine"): return
	var new_session: String = app.session
	app.requests[987654] = "match.status"
	app.match_keys[987654] = first_key
	app._response(987654, "match.status", {"state": "ready", "session": first_session, "pid": first_pid, "url": "ws://127.0.0.1:1/ws"})
	if not check(app.session == new_session and app.view == "game" and not app.busy, "A delayed status from the ended match cannot replace the new session"): return
	app.requests[987655] = "match.stop"
	app.match_keys[987655] = first_key
	app._response(987655, "match.stop", {"state": "stopped"})
	if not check(app.session == new_session and app.game != null and app.view == "game", "A late stop acknowledgment cannot clear a newer match"): return
	if not await end_with_format(true): return
	if not await preload("res://tests/FormatSequenceChecks.gd").new().run(self): return
	if not await until(func(): return app.selected_deck.get("legal", false), "the deck can start again after destroying its save"): return
	app.match_preferences.bots.append(preload("res://scripts/app/MatchPreferences.gd").bot(2))
	var generated_bot: Dictionary = preload("res://scripts/app/MatchPreferences.gd").bot(3)
	generated_bot.mode = "generated"
	app.match_preferences.bots.append(generated_bot)
	if not await enter_game(true): return
	if not await leave_game(): return
	quitting = true
	app._request_quit()
	if not check(app.confirm.visible and app.confirm.dialog_text.contains("unsaved"), "Quit warns about the retained unsaved draft and active game"): return
	app.confirm.confirmed.emit()
