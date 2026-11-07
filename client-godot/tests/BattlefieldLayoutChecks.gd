extends RefCounted
const Layout = preload("res://scripts/ui/BattlefieldLayout.gd")

func _right_button(pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	event.global_position = at
	return event

## Right-dragging an untapped pile moves every card; a plain right-click still inspects.
func _check_pile_drag(ui: Control, pile: Dictionary, directory: String) -> void:
	var view: Control = ui.cards[9192]
	var other: Control = ui.cards[9191]
	var resting: Array = [view.resting_position, other.resting_position]
	var one_tapped: Dictionary = pile.duplicate(true)
	one_tapped.players[0].zones.Battlefield[1].tapped = true
	ui._apply_state(one_tapped)
	assert(view.data.tapped and view.data.stackCount == 2, "Tapping a card keeps it in its pile and keeps the count")
	var tap_offset: Vector2 = Layout.pile_tap_offset(view.data, 2, ui.TABLE_CARD_SIZE)
	assert(view.resting_position == resting[0] + tap_offset and other.resting_position == resting[1], "Only the tapped card shifts down to expose the card behind")
	var neighbors := [{"id": 9901, "name": "Soldier", "typeLine": "Creature", "stats": "1 / 1"}, {"id": 9902, "name": "Soldier", "typeLine": "Creature", "stats": "1 / 1"}, {"id": 9903, "name": "Knight", "typeLine": "Creature", "stats": "2 / 2"}]
	var before: Dictionary = Layout.arrange(neighbors, Vector2(900, 320), ui.TABLE_CARD_SIZE, 14, true)
	neighbors[1].tapped = true
	var after: Dictionary = Layout.arrange(neighbors, Vector2(900, 320), ui.TABLE_CARD_SIZE, 14, true)
	assert(after.positions[9902] == before.positions[9902] + tap_offset and before.positions[9901] == after.positions[9901] and before.positions[9903] == after.positions[9903] and after.counts[9902] == 2, "Tapping offsets only that card, preserving its pile and neighbors")
	await ui.get_tree().create_timer(0.3).timeout
	var exposed: Vector2 = other.get_global_transform() * Vector2(other.size.x * 0.5, 8)
	assert(not Rect2(Vector2.ZERO, view.size).has_point(view.get_global_transform().affine_inverse() * exposed), "The card behind has an exposed clickable top edge")
	if not directory.is_empty():
		await ui.get_tree().create_timer(0.3).timeout
		await ui._save_frame(directory.path_join("pile-one-tapped.png"))
	ui._apply_state(pile)
	await ui.get_tree().create_timer(0.25).timeout
	var inspected := [0]
	var count_inspection := func(_data): inspected[0] += 1
	view.inspect_requested.connect(count_inspection)
	var start: Vector2 = view.get_global_transform() * (view.size * 0.5)
	view._gui_input(_right_button(true, start))
	assert(inspected[0] == 0 and view.press_pending, "Right-pressing an untapped pile waits to see if it is a drag")
	view._process(0.5)
	assert(not view.drag_active, "Holding the right button alone must not pull a pile out")
	view._input(_right_button(false, start))
	assert(inspected[0] == 1, "A plain right-click on a pile still opens its details")
	ui._close_modal()
	view._gui_input(_right_button(true, start))
	var motion := InputEventMouseMotion.new()
	motion.global_position = start + Vector2(160, -40)
	view._input(motion)
	assert(view.drag_active and ui.dragged_source == view and ui.pile_drag_ids.size() == 2, "Right-dragging takes the whole pile")
	assert(not other.visible and view.data.stackCount == 2, "The dragged card stands in for its pile and keeps the count")
	view._input(_right_button(false, motion.global_position))
	assert(inspected[0] == 1 and ui.dragged_source == null and ui.pile_drag_ids.is_empty() and ui.pile_anchors.size() == 1, "Dropping a pile records its spot without inspecting")
	assert(other.visible and view.data.stackCount == 2 and other.data.stackCount == 1, "The moved pile stays one pile")
	assert(view.get_parent() == ui.free_cards and other.get_parent() == ui.free_cards, "Both cards move off the automatic row")
	if not directory.is_empty():
		await ui.get_tree().create_timer(0.3).timeout
		await ui._save_frame(directory.path_join("pile-moved.png"))
	var spot: Vector2 = ui.manual_positions[9191]
	var tapped: Dictionary = pile.duplicate(true)
	for card in tapped.players[0].zones.Battlefield: card.tapped = true
	ui._apply_state(tapped)
	assert(ui.pile_anchors.size() == 1 and view.data.stackCount == 2 and ui.manual_positions[9191].y == spot.y + tap_offset.y, "Tapping a moved pile adds the same offset without moving its anchor")
	var tapped_at: Vector2 = view.get_global_transform() * (view.size * 0.5)
	view._gui_input(_right_button(true, tapped_at))
	assert(inspected[0] == 2 and not view.press_pending, "Only an untapped pile moves together")
	ui._close_modal()
	ui._apply_state(pile)
	await ui.get_tree().create_timer(0.25).timeout
	# Shift + left-drag moves the whole pile too, without inspecting.
	var shift_start: Vector2 = view.get_global_transform() * (view.size * 0.5)
	var shift_press := InputEventMouseButton.new()
	shift_press.button_index = MOUSE_BUTTON_LEFT
	shift_press.pressed = true
	shift_press.shift_pressed = true
	shift_press.global_position = shift_start
	view._gui_input(shift_press)
	var shift_motion := InputEventMouseMotion.new()
	shift_motion.global_position = shift_start + Vector2(-120, 30)
	view._input(shift_motion)
	assert(view.drag_active and ui.pile_drag_ids.size() == 2, "Shift-dragging takes the whole pile")
	var shift_release := InputEventMouseButton.new()
	shift_release.button_index = MOUSE_BUTTON_LEFT
	shift_release.global_position = shift_motion.global_position
	view._input(shift_release)
	assert(inspected[0] == 2 and ui.dragged_source == null and view.data.stackCount == 2 and other.visible, "A Shift-dragged pile drops as one pile without inspecting")
	ui._apply_state(pile)
	view.inspect_requested.disconnect(count_inspection)

## The hand and library follow the player's offsets, stay on the table and survive a save.
func _check_ui_layout(ui: Control, directory: String) -> void:
	ui._layout_hand()
	var hand: Vector2 = ui.hand_root.position
	var library: Vector2 = ui.library_pile.position
	ui._show_table_settings()
	assert(ui.modal.visible, "Table settings opens over the table")
	var left: HSlider = ui.modal_center.find_child("hand_x", true, false)
	left.value = -80
	assert(is_equal_approx(ui.hand_root.position.x, hand.x - 80), "The hand slides left")
	ui._set_ui_layout("hand_show", 40.0)
	assert(is_equal_approx(ui.hand_root.position.y, hand.y - 40), "The hand can show more")
	ui._set_ui_layout("library_x", -60.0)
	assert(is_equal_approx(ui.library_pile.position.x, library.x - 60), "The library slides left")
	ui._set_ui_layout("library_show", 1.0)
	assert(is_equal_approx(ui.library_pile.position.y, ui.size.y - ui.library_pile.size.y), "The whole library can show")
	assert(ui.library_count.position.y < ui.library_pile.position.y, "The library count stays above the pile")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("table-settings.png"))
	var saved := ConfigFile.new()
	for key in ui.ui_layout: saved.set_value("ui", key, ui.ui_layout[key])
	var written: Dictionary = ui.ui_layout.duplicate()
	for slider_key in ["hand_x", "hand_show", "library_x", "library_show"]: ui.ui_layout[slider_key] = 0.5
	ui._read_ui_layout(saved)
	assert(ui.ui_layout == written, "A saved layout reads back unchanged")
	saved.set_value("ui", "hand_x", 99999.0)
	ui._read_ui_layout(saved)
	assert(ui.ui_layout.hand_x == 800.0, "An edited file cannot push a setting out of range")
	ui._set_ui_layout("hand_x", 800.0)
	ui._set_ui_layout("library_x", 800.0)
	var table_right: float = ui.board_scroller.global_position.x + ui.board_scroller.size.x
	assert(ui.hand_root.get_rect().end.x <= table_right and ui.library_pile.get_rect().end.x <= table_right, "Neither can slide off the table")
	for setting in ui.UI_LAYOUT_SETTINGS: ui._set_ui_layout(setting.key, setting.default)
	assert(ui.hand_root.position.is_equal_approx(hand) and ui.library_pile.position.is_equal_approx(library), "The defaults restore the original layout")
	var hud: Vector2 = ui.hud[0].position
	ui._set_ui_layout("hud_x", -300.0)
	ui._set_ui_layout("hud_y", 200.0)
	assert(ui.hud[0].position.x < hud.x and ui.hud[0].position.y < hud.y, "The health panel moves left and up")
	ui._set_ui_layout("hud_x", -1600.0)
	ui._set_ui_layout("hud_y", 900.0)
	assert(ui.hud[0].position.x >= ui.board_scroller.global_position.x and ui.hud[0].position.y >= ui.board_scroller.global_position.y, "The health panel stays on the table")
	ui._set_ui_layout("hud_x", 0.0)
	ui._set_ui_layout("hud_y", 0.0)
	assert(ui.hud[0].position.is_equal_approx(hud), "The health panel defaults to its original spot")
	ui._close_modal()
	await ui.get_tree().process_frame

func run(ui: Control, directory: String = "") -> void:
	var values: Array = []
	for i in range(28):
		values.append({"id": 8000 + i, "name": "Island" if i > 7 else "Creature %s" % i, "typeLine": "Land" if i > 7 else "Creature", "tapped": i % 3 == 0})
	for dimensions in [Vector2(320, 314), Vector2(480, 330), Vector2(620, 640)]:
		var fitted: Vector2 = Layout.fit_card_size(values, dimensions, ui.TABLE_CARD_SIZE, 14)
		assert(fitted.x >= ui.TABLE_CARD_SIZE.x * 0.5 and fitted.x <= ui.TABLE_CARD_SIZE.x)
		assert(is_equal_approx(fitted.x / fitted.y, ui.TABLE_CARD_SIZE.x / ui.TABLE_CARD_SIZE.y), "Adaptive cards must preserve their aspect ratio")
		var packed: Dictionary = Layout.arrange(values, dimensions, ui.TABLE_CARD_SIZE, 14, true)
		assert(packed.positions.size() == values.size(), "Packing cannot hide or drop a permanent")
		for card in values:
			var footprint: Vector2 = Vector2(ui.TABLE_CARD_SIZE.y, ui.TABLE_CARD_SIZE.x) if card.tapped else ui.TABLE_CARD_SIZE
			var top_left: Vector2 = packed.positions[card.id] + (ui.TABLE_CARD_SIZE - footprint) * 0.5
			assert(Rect2(Vector2.ZERO, dimensions).grow(0.1).encloses(Rect2(top_left, footprint)), "Every full-size card must remain inside its assigned field")
	var saved: Dictionary = ui.snapshot.duplicate(true)
	await _check_ui_layout(ui, directory)
	var duplicates := [{"id": 91, "name": "Soldier", "typeLine": "Token Creature", "stats": "1 / 1", "counters": {"P1P1": 1}}, {"id": 92, "name": "Soldier", "typeLine": "Token Creature", "stats": "1 / 1", "counters": {"P1P1": 1}}]
	assert(Layout.groups(duplicates, true).size() == 1, "Matching creatures with matching counters should stack")
	duplicates[1].counters = {"P1P1": 2}
	assert(Layout.groups(duplicates, true).size() == 2, "Different game counters must keep duplicate creatures separate")
	duplicates[1].counters = {"P1P1": 1}
	duplicates[1].separate = true
	assert(Layout.groups(duplicates, true).size() == 2, "Combatants and attachment hosts must stay individually accessible")
	var fixture: Dictionary = saved.duplicate(true)
	var local_pile: Dictionary = saved.duplicate(true)
	local_pile.players[0].zones.Battlefield = [
		{"id": 9191, "name": "Soldier", "typeLine": "Token Creature", "stats": "1 / 1", "counters": {"P1P1": 1}},
		{"id": 9192, "name": "Soldier", "typeLine": "Token Creature", "stats": "1 / 1", "counters": {"P1P1": 1}}]
	ui.manual_positions[9191] = Vector2(0.3, 600)
	ui.manual_positions[9192] = Vector2(0.6, 600)
	ui._apply_state(local_pile)
	assert(ui.cards[9191].data.stackCount == 1 and ui.cards[9192].data.stackCount == 1 and ui.manual_positions.has(9191) and ui.manual_positions.has(9192), "Local duplicates must retain their manual placements without unsolicited stacking")
	ui._clean_up_board()
	assert(ui.cards.has(9191) and ui.cards.has(9192) and ui.cards[9192].data.stackCount == 2, "Explicit cleanup keeps both creature instances and adds a quantity badge")
	assert(ui.pile_anchors.size() == 1 and is_equal_approx(ui.pile_anchors.values()[0].x, 0.3) and abs(ui.manual_positions[9191].x - 0.3) < 0.05 and abs(ui.manual_positions[9192].x - 0.3) < 0.05, "Explicit cleanup forms the pile where its first card was, not in the automatic rows")
	var added_card: Dictionary = local_pile.duplicate(true)
	var newcomer: Dictionary = added_card.players[0].zones.Battlefield[0].duplicate(true)
	newcomer.id = 9193
	added_card.players[0].zones.Battlefield.append(newcomer)
	ui.manual_positions[9193] = Vector2(0.7, 600)
	ui._apply_state(added_card)
	assert(ui.cards[9193].data.stackCount == 1 and ui.manual_positions.has(9193) and ui.cards[9192].data.stackCount == 2, "A newly played matching card must stay separate from a previously cleaned-up pile")
	ui._apply_state(local_pile)
	await ui.get_tree().create_timer(0.25).timeout
	# Dropping one card onto its identical twin forms the pile at the twin's spot.
	ui.pile_anchors.clear()
	ui.local_pile_members.clear()
	ui.manual_positions[9191] = Vector2(0.25, 600)
	ui.manual_positions[9192] = Vector2(0.65, 600)
	ui.manual_positions.erase(9193)
	ui._apply_state(local_pile)
	await ui.get_tree().create_timer(0.4).timeout
	var twin: Control = ui.cards[9192]
	ui._drag_card(9191, twin.get_global_transform() * (twin.size * 0.5) - ui.cards[9191].get_global_transform() * (ui.cards[9191].size * 0.5))
	assert(ui.cards[9192].data.stackCount == 2 or ui.cards[9191].data.stackCount == 2, "Dropping a card onto an identical one forms a pile")
	assert(abs(ui.manual_positions[9191].x - 0.65) < 0.05 and abs(ui.manual_positions[9192].x - 0.65) < 0.05, "A pile formed by dropping stays where the target card was, not in the middle rows: %s %s" % [ui.manual_positions.get(9191), ui.manual_positions.get(9192)])
	ui._apply_state(local_pile)
	await ui.get_tree().create_timer(0.25).timeout
	await _check_pile_drag(ui, local_pile, directory)
	ui._clean_up_board()
	await ui.get_tree().create_timer(0.25).timeout
	ui._drag_card(9192, Vector2(240, 0))
	assert(ui.cards[9191].data.stackCount == 1 and ui.cards[9192].data.stackCount == 1, "Dragging one card out of a pair must immediately clear both quantity badges")
	ui._apply_state(local_pile)
	assert(ui.cards[9191].data.stackCount == 1 and ui.cards[9192].data.stackCount == 1 and ui.manual_positions.has(9192), "Snapshots must retain an explicitly separated card without stale counts or automatic regrouping")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("split-pile-quantity.png"))
	var hand_pile: Dictionary = local_pile.duplicate(true)
	hand_pile.players[0].zones.Hand = hand_pile.players[0].zones.Battlefield
	hand_pile.players[0].zones.Battlefield = []
	for card in hand_pile.players[0].zones.Hand: card.stackCount = 2
	ui._apply_state(hand_pile)
	assert(ui.cards[9191].data.stackCount == 1 and ui.cards[9192].data.stackCount == 1 and not ui.split_pile_cards.has(9192), "Matching cards moved into hand must be individual, clear old battlefield counts and forget pile splits")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("hand-duplicates-no-quantity.png"))
	ui._apply_state(saved)
	for owner in [1, 2]:
		fixture.players[owner].zones.Battlefield.clear()
		for i in range(15):
			var card: Dictionary = saved.players[owner].zones.Battlefield[0].duplicate(true)
			card.id = 8100 + owner * 100 + i
			if i >= 6:
				card.name = "Island" if i < 12 else "Forest"
				card.typeLine = "Basic Land"
			card.tapped = i % 4 == 0
			fixture.players[owner].zones.Battlefield.append(card)
	ui._apply_state(fixture)
	await ui.get_tree().create_timer(0.35).timeout
	for owner in [1, 2]:
		assert(not ui.rows["enemy" + str(owner)].scroll.get_h_scroll_bar().visible)
		assert(ui.cards[fixture.players[owner].zones.Battlefield[0].id].size.x < ui.TABLE_CARD_SIZE.x, "Crowded opponent fields should reduce card size")
	assert(not ui.board_scroller.get_v_scroll_bar().visible)
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("opponents-packed-adaptive.png"))
	ui._apply_state(saved)
	await ui.get_tree().create_timer(0.35).timeout
	var card: Control = ui.cards[1]
	var playable: Rect2 = ui.player_areas[0].get_global_rect()
	assert(ui.mana_pool.get_global_rect().end.x < playable.position.x, "Mana controls must sit outside the playable boundary")
	assert(ui.step_panels[0].panel.get_global_rect().end.x < playable.position.x, "Phase controls must sit outside the playable boundary")
	_check_control_spacing(ui)
	var lane_point := Vector2(playable.position.x - 20, playable.position.y + 100)
	assert(not ui._is_hand_play_drop(lane_point), "The control lane must reject hand-to-board plays")
	var center: Vector2 = card.get_global_transform() * (card.size * 0.5)
	var outside: Vector2 = ui.board.global_position + Vector2(180, 200)
	ui._drag_card(1, outside - center)
	assert(card.get_parent() == ui.free_cards and ui.free_cards.get_parent() == ui, "A moved card must render outside field/scroll clipping")
	assert(ui.player_areas[0].get_global_rect().grow(-7).encloses(card.get_global_rect()), "Dragging toward an opponent must keep the whole permanent in its owner's field")
	var saved_position: Vector2 = ui.manual_positions[1]
	ui._apply_state(saved)
	assert(ui.manual_positions[1] == saved_position, "Snapshots must preserve a bounded manual placement")
	ui._resize_fields(ui.board.global_position + Vector2(100, 550), true)
	await ui.get_tree().create_timer(0.35).timeout
	var field: Rect2 = ui.player_areas[0].get_global_rect().grow(-7)
	assert(field.encloses(card.get_global_rect()), "Resizing must bring a manual card back into its owner's section")
	ui.manual_positions.erase(1)
	ui._resize_fields(Vector2.INF, true)
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	# All four seats must retain a clear player display and three reachable
	# zone buttons at the smallest supported table size.
	var window_size: Vector2i = ui.get_window().size
	var previous_capture: Vector2i = ui.capture_size
	ui.capture_size = Vector2i(1280, 800)
	ui.get_window().size = Vector2i(1280, 800)
	var four_seats: Dictionary = saved.duplicate(true)
	var extra: Dictionary = saved.players[2].duplicate(true)
	extra.id = 3
	extra.name = "Fourth player"
	for zone in extra.zones: extra.zones[zone] = []
	four_seats.players.append(extra)
	ui._apply_state(four_seats)
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	ui._layout_board()
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	_check_control_spacing(ui)
	for owner in range(1, 4):
		var tray: Control = ui.hud_values[owner].zone_tray
		assert(not tray.get_global_rect().intersects(ui.hud[owner].get_global_rect()), "Zone bubbles must not overlap the player name, portrait or health")
		assert(ui.player_areas[owner].get_global_rect().encloses(tray.get_global_rect()), "Every opponent's zone bubbles must stay inside their board")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("retro-hud-four-players-1280.png"))
	ui.get_window().size = window_size
	ui.capture_size = previous_capture
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	print("PASS: adaptive opponent sizes, packing, hidden bars, owner-bound dragging and resize containment")

func _check_control_spacing(ui: Control) -> void:
	var field: Rect2 = ui.player_areas[0].get_global_rect().intersection(ui.board_scroller.get_global_rect())
	var mana: Rect2 = ui.mana_pool.get_global_rect()
	var phases: Rect2 = ui.step_panels[0].panel.get_global_rect()
	var gap: float = ui.LOCAL_CONTROL_GAP
	assert(absf(mana.position.x - phases.position.x) < 0.5 and absf(mana.size.x - phases.size.x) < 0.5, "Mana and phase sections share their left edge and full lane width")
	var left_space := mana.position.x - ui.get_global_rect().position.x
	assert(absf(left_space - (field.position.x - mana.end.x)) < 1.0, "Space left of the controls equals the space to the battlefield")
	assert(absf(mana.position.y - field.position.y - ui.LOCAL_CONTROL_TOP_GAP) < 0.5 and absf(phases.position.y - mana.end.y - ui.LOCAL_CONTROL_GROUP_GAP) < 0.5 and field.end.y - phases.end.y >= gap - 0.5, "Both groups keep a clear outer margin and an intentional larger gap between them")
	assert(mana.size.x <= 64.5 and ui.mana_pool.scale.x <= 0.9, "Left controls are slightly smaller with breathing room in their lane")
	var first: Rect2 = ui.mana_buttons[0].get_global_rect()
	var second: Rect2 = ui.mana_buttons[1].get_global_rect()
	var phase_first: Rect2 = ui.phase_labels[0][ui.TURN_STEPS[0]].get_global_rect()
	var phase_second: Rect2 = ui.phase_labels[0][ui.TURN_STEPS[1]].get_global_rect()
	assert(absf(phase_first.size.x - mana.size.x) < 1.0, "The phase selectors fill the lane within container pixel rounding: " + str([phase_first.size.x, mana.size.x]))
	if field.size.y >= 400:
		assert(36 * ui.mana_pool.scale.y >= 19 and ui.mana_buttons[0].count_font_size * ui.mana_pool.scale.y >= 13, "Mana symbols and ordinary counts stay larger at the smaller supported table size")
