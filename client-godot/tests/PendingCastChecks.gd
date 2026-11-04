extends RefCounted

func run(ui: Control) -> void:
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var fixture: Dictionary = saved.duplicate(true)
	var card: Dictionary = fixture.players[0].zones.Hand.pop_front()
	var id: int = card.id
	fixture.stack = [{"id": 9908, "sourceId": id, "text": "Pending cast", "card": card}]
	ui.play_positions[id] = {"position": Vector2(0.25, 380), "age": 0.0}
	ui._apply_state(fixture)
	var view: Control = ui.cards[id]
	assert(view.data.zone == "Stack" and view.can_drag(), "A local pending cast must remain draggable")
	for resolves_while_held in [false, true]:
		var center: Vector2 = view.get_global_transform() * (view.size * 0.5)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.global_position = center
		view._gui_input(press)
		view._process(0.2)
		assert(view.drag_active)
		var motion := InputEventMouseMotion.new()
		motion.global_position = center + Vector2(70, 15)
		view._input(motion)
		var held_pose: Transform2D = view.get_global_transform()
		if resolves_while_held:
			fixture.stack.clear()
			fixture.players[0].zones.Battlefield.append(card)
		ui._apply_state(fixture)
		assert(view.get_global_transform().is_equal_approx(held_pose), "A stack refresh/resolution must not pull the card out of the player's hand")
		press.pressed = false
		press.global_position = motion.global_position
		view._input(press)
		var released_pose: Transform2D = view.get_global_transform()
		ui._apply_state(fixture)
		assert(view.get_global_transform().is_equal_approx(released_pose), "Moving the pending card must persist through the next snapshot")
	ui.play_positions.erase(id)
	ui.manual_positions.erase(id)
	ui.selected = {}
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	print("PASS: pending-cast movement, snapshot persistence and resolution during dragging")
