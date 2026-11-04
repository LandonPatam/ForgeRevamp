extends Control
signal deck_selected(index: int)
signal new_deck_requested
const CREATE_ID := "__new_deck__"
const Cartridge = preload("res://scripts/app/DeckCartridge.gd")
const Copy = preload("res://scripts/app/CarouselCopy.gd")
const Appearance = preload("res://scripts/app/DeckAppearance.gd")
const P = preload("res://scripts/ui/Palette.gd")
const COLOR_NAMES := ["Yellow", "Orange", "Coral", "Pink", "Purple", "Blue", "Teal", "Mint"]
var color_menu: PopupMenu
var color_dialog: AcceptDialog
var color_picker: ColorPicker
var card_sampler: Control
var color_deck_id := ""
var darkness := 0.0
var night_visibility := 1.0
var images: Node
var decks: Array = []
var tiles: Array = []
var copies: Array = []
var copy_cycles := -1
var hit_target := 0.0
var selected_index := 0
var cursor := 0.0
var target := 0.0
var elapsed := 0.0
var dragging := false
var moved := false
var press_position := Vector2.ZERO
var press_cursor := 0.0
var enabled := true
var minimum_disk_height := 210.0
var maximum_disk_height := 315.0
var selection_lift := 0.20
var looping := true
var show_create := false
var wheel_at := 0
var pan_at := -1000
var mode_transition := false
var mode_blend := 1.0
var mode_slots: Dictionary = {}
var mode_ghosts: Array = []
var retired_tiles: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	gui_input.connect(_carousel_input)
	resized.connect(_arrange)

func set_decks(value: Array, id: String) -> void:
	var desired: Array = value.duplicate(true)
	if show_create: desired.append({"id": CREATE_ID, "name": "New deck", "cover": {}, "create": true})
	if decks == desired and tiles.size() == desired.size():
		select_id(id)
		return
	var same_order: bool = decks.map(func(deck): return str(deck.id)) == desired.map(func(deck): return str(deck.id))
	decks = desired
	_clear_copies()
	var retained := {}
	for tile in tiles:
		retained[str(tile.deck.id)] = tile
	tiles.clear()
	for deck in decks:
		var tile: Control = retained.get(str(deck.id))
		if tile == null:
			tile = Cartridge.new()
			tile.lazy_face = true
			tile.deck = deck
			tile.images = images
			tile.size = Vector2(232, 232)
			add_child(tile)
		else:
			retained.erase(str(deck.id))
			tile.update_deck(deck)
		tiles.append(tile)
	for tile in retained.values():
		if mode_transition:
			tile.hide()
			retired_tiles.append(tile)
		else:
			remove_child(tile)
			tile.queue_free()
	selected_index = 0
	for i in range(decks.size()):
		if decks[i].id == id: selected_index = i
	# Details and cover metadata arrive asynchronously on a cold deck switch.
	# Updating those must not teleport an in-flight carousel to its destination.
	if not same_order:
		cursor = selected_index
		target = cursor
	select_id(id)
	_arrange()

func configure_editor(enabled_editor: bool) -> void:
	close_color_menu()
	if looping == not enabled_editor and show_create == enabled_editor: return
	var selected_id: String = decks[selected_index].id if not decks.is_empty() else ""
	var real_decks := decks.filter(func(deck): return not deck.get("create", false))
	looping = not enabled_editor
	show_create = enabled_editor
	set_decks(real_decks, selected_id)

func begin_editor_transition(to_editor: bool) -> void:
	finish_editor_transition()
	# Keep the visible slots, including repeated disks at the loop seam. Their
	# textures are shared; this does not create or render new floppy viewports.
	var previous: Array = []
	for index in range(tiles.size()):
		if tiles[index].visible:
			previous.append({"source": tiles[index], "distance": _distance(index, cursor)})
	for copy in copies:
		if copy.visible:
			previous.append({"source": copy.source, "distance": _distance(copy.deck_index, cursor) + copy.cycle * decks.size()})
	mode_transition = true
	mode_blend = 0.0
	configure_editor(to_editor)
	# Retain disks that occupy the same physical slot in both layouts. Only
	# unmatched edge disks dissolve away or arrive, rather than popping in.
	for tile in tiles:
		_match_mode_slot(tile, _distance(tiles.find(tile), cursor), previous)
	for copy in copies:
		_match_mode_slot(copy, _distance(copy.deck_index, cursor) + copy.cycle * decks.size(), previous)
	for slot in previous:
		var ghost := Copy.new()
		ghost.source = slot.source
		ghost.set_meta("mode_distance", slot.distance)
		add_child(ghost)
		mode_ghosts.append(ghost)
	_arrange()

func _match_mode_slot(tile: Control, distance: float, previous: Array) -> void:
	var source: Control = tile.source if tile is Copy else tile
	for slot in previous:
		if str(slot.source.deck.id) == str(source.deck.id) and absf(float(slot.distance) - distance) < 0.65:
			mode_slots[tile.get_instance_id()] = {"distance": slot.distance, "matched": true}
			previous.erase(slot)
			return
	mode_slots[tile.get_instance_id()] = {"distance": distance + signf(distance) * 0.25, "matched": false}

func set_editor_transition_progress(value: float) -> void:
	mode_blend = clampf(value, 0.0, 1.0)
	_arrange()

func finish_editor_transition() -> void:
	for ghost in mode_ghosts:
		ghost.hide()
		ghost.queue_free()
	for tile in retired_tiles: tile.queue_free()
	mode_ghosts.clear()
	retired_tiles.clear()
	mode_slots.clear()
	mode_transition = false
	mode_blend = 1.0

func _place_mode_slot(tile: Control, distance: float, height: float, spacing: float) -> void:
	var slot: Dictionary = mode_slots.get(tile.get_instance_id(), {}) if mode_transition else {}
	_place(tile, lerpf(float(slot.get("distance", distance)), distance, mode_blend), height, spacing)
	if not slot.get("matched", true): tile.modulate.a = smoothstep(0.15, 0.9, mode_blend)

func _emit_index(index: int) -> void:
	if decks[index].get("create", false):
		select_id(CREATE_ID)
		new_deck_requested.emit()
	else: deck_selected.emit(index)

func select_id(id: String) -> void:
	for i in range(decks.size()):
		if decks[i].id != id: continue
		selected_index = i
		target = cursor + _distance(i, cursor)
		for index in range(tiles.size()): tiles[index].set_selected(index == i)
		return

func _distance(index: int, origin: float) -> float:
	if decks.size() < 2: return 0.0
	if not looping or decks.size() < 4: return float(index) - origin
	return wrapf(float(index) - origin, -decks.size() * 0.5, decks.size() * 0.5)

func _index_at(value: float) -> int:
	return posmod(roundi(value), decks.size()) if looping and decks.size() >= 4 else clampi(roundi(value), 0, maxi(0, decks.size() - 1))

func step(direction: int) -> void:
	if not enabled or decks.size() < 2: return
	var next_index := _index_at(selected_index + direction)
	if next_index == selected_index: return
	# Keep queued arrow presses moving in their requested direction even when
	# the animation has not caught up with the selected slot yet.
	var next_target := target + direction if looping and decks.size() >= 4 else float(next_index)
	_emit_index(next_index)
	target = next_target

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if not enabled:
		_arrange()
		return
	elapsed += delta
	if not dragging and Time.get_ticks_msec() - pan_at > 160:
		cursor = lerpf(cursor, target, 1.0 - exp(-delta * 10.0))
		if absf(cursor - target) < 0.0001: cursor = target
	_arrange()

func _arrange() -> void:
	var height := disk_height()
	var spacing := height * 1.02
	_sync_copies(spacing)
	for i in range(tiles.size()):
		_place_mode_slot(tiles[i], _distance(i, cursor), height, spacing)
	for copy in copies:
		_place_mode_slot(copy, _distance(copy.deck_index, cursor) + copy.cycle * decks.size(), height, spacing)
		copy.queue_redraw()
	for ghost in mode_ghosts:
		var distance: float = ghost.get_meta("mode_distance")
		_place(ghost, distance + signf(distance) * mode_blend * 0.25, height, spacing)
		ghost.modulate.a = 1.0 - smoothstep(0.0, 0.75, mode_blend)
		ghost.queue_redraw()

func _place(tile: Control, distance: float, height: float, spacing: float) -> void:
	var closeness := exp(-distance * distance * 2.1)
	var depth := lerpf(0.62, 1.0, closeness)
	var bob := sin(elapsed * 1.35 + 0.4) * 4.0 * closeness
	var center := Vector2(size.x * 0.5 + distance * spacing, size.y * 0.64 - closeness * size.y * selection_lift + bob)
	tile.position = center - tile.size * 0.5
	tile.scale = Vector2.ONE * depth * (height / tile.size.y)
	tile.rotation = clampf(distance, -2, 2) * -0.055 + sin(elapsed * 0.9) * 0.016 * closeness
	tile.z_index = 10 + int(closeness * 20)
	tile.modulate = Color.WHITE.lerp(Color(0.83, 0.87, 0.9), 1.0 - closeness)
	tile.visible = center.x > -height and center.x < size.x + height
	tile.set_night_lighting(darkness * night_visibility, exp(-distance * distance * 0.65))

func _clear_copies() -> void:
	for copy in copies:
		remove_child(copy)
		copy.queue_free()
	copies.clear()
	copy_cycles = -1

func _sync_copies(spacing: float) -> void:
	var cycles := ceili((size.x * 0.5 + disk_height()) / (spacing * decks.size())) if looping and decks.size() >= 4 else 0
	if cycles == copy_cycles: return
	_clear_copies()
	copy_cycles = cycles
	# Repeat visible slots so a deck crossing the loop seam exchanges identical
	# off-centre instances instead of teleporting its only face across the screen.
	for cycle in range(-cycles, cycles + 1):
		if cycle == 0: continue
		for i in range(tiles.size()):
			var copy := Copy.new()
			copy.source = tiles[i]
			copy.deck_index = i
			copy.cycle = cycle
			add_child(copy)
			copies.append(copy)

func disk_height() -> float:
	return clampf(size.y * 0.80, minimum_disk_height, maximum_disk_height)

func close_color_menu() -> void:
	if color_menu != null: color_menu.hide()
	if color_dialog != null: color_dialog.hide()

func _open_color_menu(index: int) -> void:
	if index < 0 or decks[index].get("create", false): return
	color_deck_id = decks[index].id
	if color_menu == null:
		color_menu = PopupMenu.new()
		color_menu.id_pressed.connect(_color_action)
		add_child(color_menu)
	color_menu.clear()
	color_menu.theme = P.make_theme()
	var ink := Color("304a55").lerp(Color("d5e6e3"), darkness)
	color_menu.add_theme_color_override("font_color", ink)
	color_menu.add_theme_color_override("font_hover_color", ink)
	color_menu.add_theme_color_override("font_separator_color", ink)
	color_menu.add_theme_stylebox_override("panel", P.box(Color("e4e9ea").lerp(Color("3a4447"), darkness), Color("58707a"), 8, 10))
	color_menu.add_separator("FLOPPY COLOR")
	for i in range(Appearance.COLORS.size()):
		var swatch := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		swatch.fill(Appearance.COLORS[i])
		color_menu.add_icon_item(ImageTexture.create_from_image(swatch), COLOR_NAMES[i], i)
	color_menu.add_separator()
	color_menu.add_item("Custom color…", 8)
	color_menu.add_item("Reset to default", 9)
	color_menu.add_item("Pick color from card…", 10)
	color_menu.position = Vector2i(get_viewport().get_mouse_position())
	color_menu.popup()

func _color_action(id: int) -> void:
	if id in [8, 10]:
		if color_dialog == null:
			color_dialog = AcceptDialog.new()
			color_dialog.theme = P.make_theme()
			color_dialog.ok_button_text = "Apply color"
			color_picker = ColorPicker.new()
			color_picker.edit_alpha = false
			color_picker.sliders_visible = false
			color_picker.color_modes_visible = false
			color_picker.presets_visible = false
			color_picker.sampler_visible = false
			for color in Appearance.COLORS: color_picker.add_preset(color)
			var tools := HBoxContainer.new()
			tools.add_theme_constant_override("separation", 20)
			color_dialog.add_child(tools)
			tools.add_child(color_picker)
			card_sampler = preload("res://scripts/app/CardColorSampler.gd").new()
			tools.add_child(card_sampler)
			card_sampler.color_picked.connect(func(color: Color): color_picker.color = color)
			color_dialog.confirmed.connect(func(): _apply_disk_color(color_picker.color))
			add_child(color_dialog)
		color_dialog.title = "Floppy color"
		var matching: Array = decks.filter(func(deck): return deck.id == color_deck_id)
		if matching.is_empty(): return
		var descriptor: Dictionary = matching[0]
		color_picker.color = Appearance.color_for(descriptor)
		var artwork: Dictionary = descriptor.get("cover", {})
		card_sampler.set_artwork(images.request_texture(artwork) if images != null and not artwork.is_empty() else null)
		color_dialog.popup_centered()
	else:
		_apply_disk_color(Appearance.default_color(color_deck_id) if id == 9 else Appearance.COLORS[id], id == 9)

func _apply_disk_color(color: Color, reset: bool = false) -> void:
	if Appearance.save_color(color_deck_id, color, reset) != OK:
		push_warning("The floppy color changed, but its preference could not be saved.")
	for tile in tiles:
		if tile.deck.id == color_deck_id: tile.refresh_color()
	for copy in copies: copy.queue_redraw()

func _tile_at(point: Vector2) -> int:
	var found := -1
	var top := -1
	for i in range(tiles.size()):
		var tile: Control = tiles[i]
		if not tile.visible or tile.z_index < top: continue
		if Rect2(Vector2.ZERO, tile.size).has_point(tile.get_transform().affine_inverse() * point):
			found = i
			top = tile.z_index
			hit_target = cursor + _distance(i, cursor)
	for copy in copies:
		if not copy.visible or copy.z_index < top: continue
		if Rect2(Vector2.ZERO, copy.size).has_point(copy.get_transform().affine_inverse() * point):
			found = copy.deck_index
			top = copy.z_index
			hit_target = cursor + _distance(copy.deck_index, cursor) + copy.cycle * decks.size()
	return found

func _carousel_input(event: InputEvent) -> void:
	if not enabled: return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = false
			_open_color_menu(_tile_at(event.position))
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			if Time.get_ticks_msec() - wheel_at > 140:
				wheel_at = Time.get_ticks_msec()
				step(1 if event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT] else -1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus()
				dragging = true
				moved = false
				press_position = event.position
				press_cursor = cursor
			else:
				if not dragging: return
				dragging = false
				var clicked_target := INF
				if moved:
					if not decks.is_empty(): _emit_index(_index_at(cursor))
				else:
					var index := _tile_at(event.position)
					if index >= 0:
						clicked_target = hit_target
						_emit_index(index)
				target = cursor + _distance(selected_index, cursor) if is_inf(clicked_target) else clicked_target
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		var shift: float = event.position.x - press_position.x
		moved = moved or absf(shift) > 8
		if moved:
			cursor = press_cursor - shift / (disk_height() * 1.02)
			if not looping or decks.size() < 4: cursor = clampf(cursor, 0, maxi(0, decks.size() - 1))
		accept_event()
	elif event is InputEventPanGesture:
		pan_at = Time.get_ticks_msec()
		cursor += (event.delta.x + event.delta.y) * 0.09
		if not looping or decks.size() < 4: cursor = clampf(cursor, 0, maxi(0, decks.size() - 1))
		if not decks.is_empty(): _emit_index(_index_at(cursor))
		target = cursor + _distance(selected_index, cursor)
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		step(1 if event.keycode == KEY_RIGHT else -1)
		accept_event()
