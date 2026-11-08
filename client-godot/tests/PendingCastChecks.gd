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
	await _check_cast_choices(ui, saved)
	await _check_hover_under_popup(ui, saved)
	print("PASS: pending-cast movement, snapshot persistence and resolution during dragging")

## Presentation only: a dropped card stays where it was dropped through a cost/mode
## popup and any follow-up cast step, instead of flicking back to hand or vanishing.
func _check_cast_choices(ui: Control, saved: Dictionary) -> void:
	var was_live: bool = ui.live
	var saved_cancel: Button = ui.cancel_button
	if saved_cancel == null:
		ui.cancel_button = Button.new()
		ui.add_child(ui.cancel_button)
		ui.cancel_button.hide()
	ui.live = true
	var fixture: Dictionary = saved.duplicate(true)
	fixture.connectionReady = true
	fixture.prompt = {"inputKind": "InputPassPriority", "okEnabled": true}
	fixture.stack = []
	fixture.asks = [{"id": 77, "kind": "choice", "title": "Choose a cost", "options": [{"label": "Pay {2}"}, {"label": "Alternative cost"}]}]
	var card: Dictionary = fixture.players[0].zones.Hand[0]
	var id: int = card.id
	ui.play_positions[id] = {"position": Vector2(0.4, 300), "age": 0.0}
	ui._apply_state(fixture)
	ui._process(1.0)
	ui._close_modal()
	assert(ui.play_positions.has(id) and ui.cards[id].get_parent() == ui.free_cards, "A cost choice popup must not return the dropped card to hand")
	fixture.players[0].zones.Hand.remove_at(0)
	fixture.asks = []
	fixture.prompt = {"inputKind": "InputSelectTargets", "cancelEnabled": true}
	ui._apply_state(fixture)
	var view: Control = ui.cards.get(id)
	assert(view != null and not view.is_queued_for_deletion() and view.visible and view.visual.visible and view.data.zone == "Stack", "A cast mid-way through its choices stays visible on the table")
	fixture.prompt = {"inputKind": "InputPassPriority", "okEnabled": true}
	fixture.stack = [{"id": 9920, "sourceId": id, "text": "Cast", "card": card}]
	ui._apply_state(fixture)
	assert(ui.cards.get(id) == view and view.visible, "The same card view carries through to the committed stack item")
	ui.play_positions.erase(id)
	ui.manual_positions.erase(id)
	ui.live = was_live
	ui._apply_state(saved)
	if saved_cancel == null:
		ui.cancel_button.queue_free()
		ui.cancel_button = null
	await ui.get_tree().process_frame

## A hovered table card hands its face to the raised copy; a popup hiding that copy must show the card again.
func _check_hover_under_popup(ui: Control, saved: Dictionary) -> void:
	var view: Control = null
	for candidate in ui.cards.values():
		if candidate.data.get("zone", "") == "Battlefield" and candidate.is_visible_in_tree(): view = candidate
	assert(view != null)
	view._on_enter()
	ui.hovered_source = view
	ui._sync_raised_card()
	assert(ui.raised_card.visible and not view.visual.visible)
	ui.modal.show()
	ui._sync_raised_card()
	assert(not ui.raised_card.visible and view.visual.visible, "A popup must never leave a hovered card blank")
	ui.modal.hide()
	ui._sync_raised_card()
	assert(ui.raised_card.visible and not view.visual.visible, "Closing the popup restores the raised copy")
	view._on_exit()
	ui._card_unhovered(view)
	ui._apply_state(saved)
