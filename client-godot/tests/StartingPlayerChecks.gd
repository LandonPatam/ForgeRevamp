extends RefCounted
const StartingPlayerDialog = preload("res://scripts/ui/StartingPlayerPanel.gd")
const CoinTossDialog = preload("res://scripts/ui/CoinTossPanel.gd")

func run(ui: Control, directory: String = "") -> void:
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var was_live: bool = ui.live
	var saved_cancel: Button = ui.cancel_button
	if saved_cancel == null:
		ui.cancel_button = Button.new()
		ui.add_child(ui.cancel_button)
		ui.cancel_button.hide()
	ui.live = true
	var state: Dictionary = saved.duplicate(true)
	state.game.turn = 0
	state.asks = []
	state.connectionReady = true
	state.pendingDraws = []
	state.prompt = {"inputKind": "InputSelectEntitiesFromList", "message": "You won the coin toss.\n\nWho would you like to start this game?", "cards": [], "chosen": [], "selMin": 1, "selMax": 1, "okEnabled": false}
	ui._apply_state(state)
	var panel: Control = ui.modal_panel
	assert(panel is StartingPlayerDialog and ui.modal.visible and ui.open_ask == -2)
	assert(panel.buttons.size() == state.players.size() and not ui.prompt_body.visible, "The startup decision belongs in a portrait popup, not the stack")
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	ui.modal.get_child(0).gui_input.emit(outside)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ui._unhandled_key_input(escape)
	assert(ui.modal.visible and ui.modal_panel == panel, "The required starting-player choice must not be dismissed")
	panel.buttons[1].mouse_entered.emit()
	await ui.get_tree().create_timer(0.16).timeout
	assert(panel.hovered == 1 and panel.portraits[1].scale.x > 1.05, "Portrait hover should animate feedback")
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("starting-player-hover.png"))
	panel.buttons[1].mouse_exited.emit()
	await ui.get_tree().create_timer(0.16).timeout
	assert(panel.hovered == -1 and panel.portraits[1].scale.is_equal_approx(Vector2.ONE))
	var chosen: Array = []
	panel.player_selected.connect(func(id): chosen.append(id))
	state.connectionReady = false
	ui._apply_state(state)
	panel._choose(2)
	assert(chosen.is_empty() and panel.buttons.all(func(button): return button.disabled), "Disconnected portraits must not submit")
	state.connectionReady = true
	ui._apply_state(state)
	ui.modal.hide()
	ui._apply_state(state)
	assert(ui.modal.visible and ui.modal_panel == panel, "A pending starting-player choice must recover after reconnect/hidden popup")
	panel.buttons[2].pressed.emit()
	panel._choose(0)
	assert(chosen == [2], "Clicking a portrait must submit that player's ID exactly once")
	state.game.turn = 1
	state.prompt.inputKind = "InputPassPriority"
	ui._apply_state(state)
	assert(not ui.modal.visible and ui.prompt_body.visible, "Forge completion should close the chooser and restore stack controls")
	await _die_variants(ui, state, directory)
	await _normalized_die_variants(ui, state)
	await _shared_toss(ui, state, directory)
	ui.live = was_live
	if saved_cancel == null:
		ui.cancel_button.queue_free()
		ui.cancel_button = saved_cancel
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	print("PASS: starting-player popup, portrait hover, exact selection, disconnect/dismissal guards and engine completion")

func _die_variants(ui: Control, state: Dictionary, directory: String) -> void:
	for count in [2, 3, 4]:
		var sample := state.duplicate(true)
		sample.players = []
		for index in range(count):
			sample.players.append({"id": 40 + index, "name": ["Alex", "Ada", "Bryn", "Cyra"][index], "life": 40})
		var panel := CoinTossDialog.new()
		ui._prepare_modal()
		ui.modal_center.add_child(panel)
		ui.modal_panel = panel
		panel.set_process(false)
		for winner in range(count):
			sample.players.sort_custom(func(a, b): return int(a.id) < int(b.id))
			sample.startingToss = {"id": 8000 + count, "winnerId": 40 + winner, "winnerSeat": winner, "winnerName": sample.players[winner].name, "choosing": true}
			panel.present(sample)
			await ui.get_tree().process_frame
			assert(Rect2(Vector2.ZERO, ui.get_viewport_rect().size).encloses(panel.get_global_rect()), "Starting rolls must fit the Mac viewport")
			assert(panel.winner_index == winner and panel.outcome_marks.size() == count)
			assert(panel.hint.text.contains("1 in %d" % count))
			# The viewer's local seat comes first, but die lettering stays fixed.
			sample.players.push_front(sample.players.pop_back())
			for seat in range(count):
				if sample.players[seat].id == 40 + winner: sample.startingToss.winnerSeat = seat
			panel.present(sample)
			assert(panel.winner_index == winner and panel.outcome_marks[0] == "A1" and panel.outcome_marks[1] == "A2")
			panel.elapsed = panel.SPIN_SECONDS + 0.1
			panel._update_text()
			assert(panel.status.text.contains(sample.startingToss.winnerName))
			panel.coin.queue_redraw()
			if not directory.is_empty(): await ui._save_frame(directory.path_join("starting-roll-%d-player-result-%d.png" % [count, winner]))
			panel.elapsed = 0.0
		panel.elapsed = 0.55
		panel._update_text()
		panel.coin.queue_redraw()
		if not directory.is_empty(): await ui._save_frame(directory.path_join("starting-roll-%d-player-motion.png" % count))
		ui._close_modal()
		panel.queue_free()
		await ui.get_tree().process_frame
	print("PASS: two/three/four-player starting rolls, every winner, stable initials across rotated seats and duplicate initials")

func _shared_toss(ui: Control, state: Dictionary, directory: String) -> void:
	state.game.turn = 0
	state.prompt = {"inputKind": "InputLockUI", "okEnabled": false, "cancelEnabled": false, "cards": [], "chosen": []}
	state.startingToss = {"id": 9001, "winnerId": 77, "winnerSeat": 1, "winnerName": state.players[1].name, "heads": true, "choosing": true}
	ui.coin_toss_seen.erase(9001)
	ui._apply_state(state)
	var panel: Control = ui.modal_panel
	assert(panel is CoinTossDialog and ui.modal.visible, "A nonwinning seat must see the shared coin toss instead of an unexplained wait")
	panel.set_process(false)
	panel.elapsed = 0.55
	panel.coin.queue_redraw()
	if not directory.is_empty(): await ui._save_frame(directory.path_join("coin-toss-flipping.png"))
	panel.elapsed = 1.95
	panel._update_text()
	panel.coin.queue_redraw()
	if not directory.is_empty(): await ui._save_frame(directory.path_join("coin-toss-waiting.png"))
	assert(panel.status.text.contains(state.players[1].name) and panel.hint.text.contains("is choosing who starts"), "Every waiting player must see who won and whose decision is pending")
	panel._process(2.0)
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	ui._apply_state(state)
	assert(ui.modal_panel == panel and panel.complete, "Repeated snapshots must not restart a settled toss while another player chooses")
	state.connectionReady = false
	ui._apply_state(state)
	assert(panel.hint.text.contains("Reconnecting"), "The shared waiting screen must reflect connection loss")
	state.connectionReady = true
	state.startingToss.choosing = false
	state.startingToss.firstName = state.players[0].name
	ui._apply_state(state)
	assert(not ui.modal.visible, "The waiting screen closes when Forge accepts the starting player")
	state.startingToss.merge({"id": 9002, "winnerSeat": 0, "winnerName": state.players[0].name, "choosing": true}, true)
	state.prompt = {"inputKind": "InputSelectEntitiesFromList", "cards": [], "chosen": [], "selMin": 1, "selMax": 1, "okEnabled": false}
	ui.coin_toss_seen.erase(9002)
	ui._apply_state(state)
	assert(ui.modal_panel is CoinTossDialog, "The winner also sees the coin animation before the actual choice")
	ui.modal_panel._process(3.0)
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	assert(ui.modal_panel is StartingPlayerDialog, "Only the winning seat proceeds to the real Forge starting-player controls")
	state.startingToss.merge({"id": 9003, "winnerSeat": 1}, true)
	ui.coin_toss_seen.erase(9003)
	ui._apply_state(state)
	panel = ui.modal_panel
	ui._clear_live_session()
	assert(not panel.is_processing() and ui.coin_toss_seen.is_empty(), "Session cleanup cancels an unfinished coin without marking the next session's toss seen")
	print("PASS: shared coin animation, named winner/waiting state, seat-specific controls, snapshot/reconnect stability and session cleanup")

func _normalized_die_variants(ui: Control, state: Dictionary) -> void:
	# Exercise LiveAdapter's real engine-ID to viewer-local seat conversion.
	for count in [3, 4]:
		var raw := {"type": "state", "protocolVersion": 2, "sessionId": "roll-fixture", "revision": 1, "me": 40, "game": {"activePlayer": 40, "turn": 0}, "players": [], "stack": [], "combat": [], "asks": [], "prompt": {}, "log": []}
		for index in range(count):
			raw.players.append({"id": 40 + index, "name": ["Alex", "Ada", "Bryn", "Cyra"][index], "life": 40, "mana": {}, "zones": {"Battlefield": [], "Hand": [], "Command": [], "Graveyard": [], "Exile": []}})
		var panel := CoinTossDialog.new()
		ui._prepare_modal()
		ui.modal_center.add_child(panel)
		ui.modal_panel = panel
		panel.set_process(false)
		for winner in range(count):
			raw.startingToss = {"id": 8100 + count, "winnerId": 40 + winner, "winnerName": raw.players[winner].name, "choosing": true}
			for viewer in range(count):
				raw.me = 40 + viewer
				var adapter = load("res://scripts/bridge/LiveAdapter.gd").new()
				var normalized: Dictionary = adapter.normalize(raw)
				normalized.connectionReady = true
				panel.present(normalized)
				assert(panel.winner_index == winner, "Normalized viewer seats must preserve the authoritative winning die face")
				assert(panel.outcome_marks == ["A1", "A2", "B", "C"].slice(0, count), "Initials must follow stable engine IDs on every device")
				assert(panel.local_winner == (viewer == winner), "Only the winner may choose the starting player")
		ui._close_modal()
		panel.queue_free()
		await ui.get_tree().process_frame
	print("PASS: starting-roll identity across real normalized snapshots for every winner and viewer")
