extends RefCounted

func run(ui: Control, directory: String = "") -> void:
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var fixture: Dictionary = saved.duplicate(true)
	# Use existing faces as fixtures without duplicating a battlefield/hand instance.
	var commander: Dictionary = fixture.players[0].zones.Hand.pop_front()
	commander.merge({"name": "Atraxa, Praetors' Voice", "commander": true, "commanderCasts": 2, "commanderTax": 4}, true)
	fixture.players[0].zones.Command = [commander]
	fixture.players[0].zones.Graveyard = [fixture.players[0].zones.Hand.pop_front()]
	fixture.players[0].zones.Exile = [fixture.players[0].zones.Hand.pop_front()]
	ui._apply_state(fixture)
	ui.hud_values[0].zones.Command.pressed.emit()
	assert(ui.zone_expansion < 1, "A zone menu starts expanding from its own bubble")
	await ui.get_tree().create_timer(0.22).timeout
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	assert(not ui.modal.visible and ui.zone_panel.visible, "Browsing a zone must leave the battlefield interactive")
	var view: Control = ui.zone_views[commander.id]
	assert(view.face.data.commanderTax == 4 and view.tooltip_text.contains("+{4}"), "Command zone must show the engine's increased generic cost")
	view._on_enter()
	assert(view.visual.visible and view.can_drag(), "Hovering a commander must keep its face visible and draggable")
	ui._sync_raised_card()
	assert(view.hover_active and ui.inspection.visible and ui.inspection_card.data.id == commander.id, "Command-zone hover must display the full-size preview")
	assert(ui.zone_panel.get_global_rect().end.x <= ui.board_scroller.get_global_rect().end.x, "The browser must fit on the board")
	var center: Vector2 = view.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = center
	view._gui_input(press)
	view._process(0.2)
	assert(ui.dragged_source == view, "Holding the commander must capture that card for dragging")
	ui._apply_state(fixture)
	assert(ui.dragged_source == view and view.get_parent() == ui, "Refreshing a zone during dragging must preserve the held instance")
	view._finish_press(true)
	assert(ui.dragged_source == null and view.get_parent() == ui.zone_content, "Canceling must return the card to its zone")
	if not directory.is_empty():
		await ui.get_tree().process_frame
		await ui.get_tree().process_frame
		ui.get_viewport().get_texture().get_image().save_png(directory.path_join("command-zone.png"))
	for zone in ["Graveyard", "Exile"]:
		ui.hud_values[0].zones[zone].pressed.emit()
		assert(ui.zone_name == zone and ui.zone_views.size() == 1 and not ui.modal.visible)
		ui._apply_state(fixture)
		assert(ui.zone_views.size() == 1, "Zone refreshes must not duplicate cards")
	ui._close_zone_browser()
	fixture.players[1].zones.Command = [commander]
	ui._apply_state(fixture)
	ui._show_zone(1, "Command")
	assert(not ui.zone_views[commander.id].can_drag(), "Opponent commanders must remain read-only for dragging")
	await ui.get_tree().create_timer(0.22).timeout
	assert(ui.player_areas[1].get_global_rect().encloses(ui.zone_panel.get_global_rect()), "Opponent zones open inside that opponent's own board")
	assert(ui.zone_panel.pivot_offset.is_equal_approx(ui.hud_values[1].zones.Command.get_global_rect().get_center() - ui.zone_panel.position), "The expansion pivots around the clicked zone icon")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("opponent-zone-menu.png"))
	ui._show_zone(1, "Command")
	assert(not ui.zone_panel.visible, "Clicking the same zone must toggle its browser closed")
	var previous_size: Vector2i = ui.get_window().size
	var previous_capture: Vector2i = ui.capture_size
	ui.capture_size = Vector2i(1280, 800)
	ui.get_window().size = Vector2i(1280, 800)
	var extra: Dictionary = fixture.players[2].duplicate(true)
	extra.id = 3
	extra.name = "Fourth player"
	extra.zones.Command = [commander]
	fixture.players.append(extra)
	ui._apply_state(fixture)
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	for owner in range(1, 4):
		for zone in ["Command", "Graveyard", "Exile"]:
			ui._show_zone(owner, zone)
			await ui.get_tree().create_timer(0.22).timeout
			assert(ui.player_areas[owner].get_global_rect().encloses(ui.zone_panel.get_global_rect()), "Every zone menu stays within its owner's board at 1280x800, including empty zones")
			if ui.zone_views.is_empty(): assert(ui.zone_empty.visible and ui.zone_scroll.custom_minimum_size.y < 80, "Empty zones use a compact message instead of an empty card-sized menu")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("opponent-zone-four-players-1280.png"))
	ui._close_zone_browser()
	ui.get_window().size = previous_size
	ui.capture_size = previous_capture
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	print("PASS: nonmodal zone browsing, visible commander hover, drag cancellation, snapshot continuity and opponent guards")
