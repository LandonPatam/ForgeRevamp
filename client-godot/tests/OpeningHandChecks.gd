extends RefCounted

func run(ui: Control, directory: String = "") -> void:
	var panel = preload("res://scripts/ui/OpeningHand.gd").new()
	ui.add_child(panel)
	panel.z_index = 90
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.synthetic_hover = true
	var hand: Array = []
	var originals: Array = ui.snapshot.players[0].zones.Hand
	var image_names := ["Atraxa, Praetors' Voice", "Doctor Doom, King of Latveria", "Sol Ring", "Swamp", "Arcane Signet", "Deepglow Skate", "Cathars' Crusade"]
	for i in range(7):
		var card: Dictionary = originals[i % originals.size()].duplicate(true)
		card.id = 9000 + i
		card.name = image_names[i]
		card.erase("imageKey")
		hand.append(card)
	var state := {"players": [{"name": "Your opening hand", "zones": {"Hand": hand}}], "prompt": {"inputKind": "InputConfirmMulligan", "message": "Keep these seven cards or take a mulligan.", "okEnabled": true, "cancelEnabled": true, "chosen": []}, "connectionReady": true, "asks": [], "game": {"gameOver": false}}
	var decisions: Array = []
	var selections: Array = []
	panel.decision.connect(func(action): decisions.append(action))
	panel.card_chosen.connect(func(id): selections.append(id))
	panel.present(state)
	assert(panel.visible and panel.views.size() == 7 and not panel.keep_button.disabled)
	state.prompt.mulliganReturnCount = 2
	panel.present(state)
	assert(panel.hint.visible and panel.hint.text.contains("return 2 cards"), "The return count must be visible while Keep and Mulligan are still available")
	state.prompt.mulliganReturnCount = 0
	panel.present(state)
	assert(not panel.hint.visible, "A hand with no returns needs no red warning bubble")
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("opening-hand-1600.png"))
	for i in range(7):
		panel.hover_at(panel.poses[i] * Vector2(20, 120))
		assert(panel.hovered == i, "Each overlapping opening card must be reachable")
	await ui.get_tree().create_timer(0.15).timeout
	assert(is_zero_approx(panel.views[6].rotation) and panel.views[6].z_index == 30, "Hover must expose the full card inside the fan")
	var animation: Tween = panel.views[6].animation
	panel.present(state)
	assert(panel.views[6].animation == animation, "Repeated snapshots must not restart hover")
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("opening-hover-1600.png"))
		ui.get_window().size = Vector2i(1280, 800)
		ui.capture_size = Vector2i(1280, 800)
		await ui.get_tree().process_frame
		panel.set_hover(3)
		await ui._save_frame(directory.path_join("opening-hover-1280.png"))
	panel._toggle_board()
	assert(not panel.fan.visible and panel.visible and panel.view_button.text == "View Hand")
	panel._toggle_board()
	panel.submit("cancel")
	panel.submit("cancel")
	assert(decisions == ["cancel"] and panel.keep_button.disabled, "Mulligan must submit once while Forge deals")
	hand.reverse()
	panel.present(state)
	assert(not panel.keep_button.disabled, "A new engine hand must unlock decisions")
	panel.submit("ok")
	assert(decisions == ["cancel", "ok"])
	state.prompt.inputKind = "InputLondonMulligan"
	state.connectionReady = false
	state.prompt.okEnabled = true
	state.prompt.cancelEnabled = false
	panel.present(state)
	await ui.get_tree().process_frame
	assert(decisions.size() == 2, "A zero-card confirmation must wait for the connection")
	state.connectionReady = true
	panel.present(state)
	panel.present(state)
	assert(not panel.keep_button.visible and not panel.mulligan_button.visible, "Zero-card bottoming must not ask for a click")
	await ui.get_tree().process_frame
	assert(decisions == ["cancel", "ok", "ok"], "A free mulligan must acknowledge the empty selection exactly once")
	panel.present(state)
	await ui.get_tree().process_frame
	assert(decisions.size() == 3, "Duplicate snapshots must not repeat the empty confirmation")
	state.prompt.inputKind = "InputConfirmMulligan"
	state.prompt.cancelEnabled = true
	panel.present(state)
	assert(panel.keep_button.visible and panel.mulligan_button.visible and not panel.keep_button.disabled, "The new hand must restore Keep/Mulligan")
	state.prompt.inputKind = "InputLondonMulligan"
	state.prompt.okEnabled = false
	state.prompt.message = "Choose one card to put on the bottom of your library."
	panel.present(state)
	assert(panel.keep_button.disabled and panel.mulligan_button.text == "Auto Choose")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = panel.poses[2] * Vector2(20, 120)
	panel._gui_input(click)
	assert(selections == [hand[2].id], "London mulligan must select cards through Forge")
	state.prompt.chosen = ["card:" + str(hand[2].id)]
	state.prompt.okEnabled = true
	panel.present(state)
	assert(panel.views[2].selected and not panel.keep_button.disabled)
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("opening-bottom-1280.png"))
	state.connectionReady = false
	panel.present(state)
	assert(panel.keep_button.disabled and panel.mulligan_button.disabled)
	state.prompt.inputKind = "InputPassPriority"
	panel.present(state)
	await ui.get_tree().create_timer(0.45).timeout
	assert(not panel.visible)
	state.connectionReady = true
	state.prompt.inputKind = "InputConfirmMulligan"
	state.prompt.cancelEnabled = true
	panel.present(state)
	panel.submit("ok")
	assert(panel.visible and panel.exit_tween == null, "Keep must wait for Forge rather than hide required bottom choices")
	state.prompt.inputKind = "InputPassPriority"
	panel.present(state)
	var fade: Tween = panel.exit_tween
	assert(panel.visible and fade != null and not panel.active and panel.view_button.disabled, "Accepted keep must fade with input blocked")
	fade.pause()
	fade.custom_step(0.2)
	assert(panel.modulate.a > 0.2 and panel.modulate.a < 0.8, "Opening cards and shade must fade smoothly together")
	fade.play()
	panel.present(state)
	assert(panel.exit_tween == fade, "Snapshots must not restart the exit fade")
	await ui.get_tree().create_timer(0.3).timeout
	assert(not panel.visible and is_equal_approx(panel.modulate.a, 1.0), "Fade completion must hide and restore opacity for the next game")
	state.prompt.inputKind = "InputConfirmMulligan"
	panel.present(state)
	panel.submit("ok")
	state.prompt.inputKind = "InputLockUI"
	state.openingHandComplete = true
	panel.present(state)
	assert(panel.exit_tween != null and not panel.active, "An authoritative accepted hand must close even while the seat waits for another player")
	await ui.get_tree().create_timer(0.45).timeout
	assert(not panel.visible, "An idle online seat must not remain in the opening hand until its own turn")
	state.erase("openingHandComplete")
	state.prompt.inputKind = "InputConfirmMulligan"
	panel.present(state)
	assert(panel.visible and is_equal_approx(panel.modulate.a, 1.0), "A new opening hand must be fully visible")
	panel.reset()
	panel.queue_free()
	if not directory.is_empty():
		ui._show_card_detail({"id": 9001, "name": "Doctor Doom, King of Latveria", "text": "Complete card image preview", "color": "B"})
		await ui._save_frame(directory.path_join("card-art-inspection-1280.png"))
		ui._close_modal()
		ui.get_window().size = Vector2i(1600, 1000)
		ui.capture_size = Vector2i(1600, 1000)
	await ui.get_tree().process_frame
	await _check_table_hand(ui)
	print("PASS: opening-hand fan, hover, decisions, bottom selection, deferred battlefield hand and connection guards")

func _check_table_hand(ui: Control) -> void:
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var was_live: bool = ui.live
	var released: bool = ui.opening_hand_released
	var saved_cancel = ui.cancel_button
	if saved_cancel == null:
		ui.cancel_button = Button.new()
		ui.add_child(ui.cancel_button)
		ui.cancel_button.hide()
	var state: Dictionary = saved.duplicate(true)
	state.game.turn = 0
	state.asks = []
	state.connectionReady = true
	state.prompt.merge({"inputKind": "InputLockUI", "chosen": [], "okEnabled": false, "cancelEnabled": false}, true)
	ui.live = true
	ui.opening_hand_released = false
	ui._apply_state(state)
	assert(not ui.hand_root.visible and state.players[0].zones.Hand.all(func(card): return not ui.cards.has(card.id)), "An early dealt-hand snapshot must not create battlefield cards before the mulligan prompt")
	state.prompt.merge({"inputKind": "InputConfirmMulligan", "okEnabled": true, "cancelEnabled": true}, true)
	ui._apply_state(state)
	ui.opening_hand._toggle_board()
	assert(ui.opening_hand.visible and not ui.hand_root.visible, "View Battlefield must not expose an unconfirmed hand")
	ui.opening_hand._toggle_board()
	ui.opening_hand.keep_requested = true
	state.prompt.merge({"inputKind": "InputLondonMulligan", "chosen": ["card:" + str(state.players[0].zones.Hand[0].id)]}, true)
	ui._apply_state(state)
	assert(not ui.opening_hand_released and not ui.hand_root.visible, "Keep must still wait for required London bottom-card confirmation")
	ui.opening_hand.keep_requested = true
	state.prompt.inputKind = "InputLockUI"
	ui._apply_state(state)
	assert(not ui.hand_root.visible, "A pending engine response cannot release the hand")
	state.openingHandComplete = true
	ui._apply_state(state)
	assert(ui.opening_hand_released and ui.hand_root.visible and state.players[0].zones.Hand.all(func(card): return ui.cards.has(card.id)), "The accepted final hand appears while waiting, after Keep and all bottom choices complete")
	ui.opening_hand.reset()
	ui.live = was_live
	ui.opening_hand_released = released
	ui._apply_state(saved)
	if saved_cancel == null:
		ui.cancel_button.queue_free()
		ui.cancel_button = null
	await ui.get_tree().process_frame
