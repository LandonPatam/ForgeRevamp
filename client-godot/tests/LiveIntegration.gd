extends RefCounted
const StartingPlayerDialog = preload("res://scripts/ui/StartingPlayerPanel.gd")
## Drives real table callbacks against a fresh, deterministic Forge match.
var ui: Control
var deadline := 0
var choices := 0
var manual_draws := 0
var captured_draw := false

func drag_commander(id: int, target: Vector2) -> void:
	if ui.zone_owner != 0 or ui.zone_name != "Command":
		ui._show_zone(0, "Command")
	var view: Control = ui.zone_views[id]
	var center: Vector2 = view.get_global_transform() * (view.size * 0.5)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = center
	view._gui_input(press)
	view._process(0.2)
	var motion := InputEventMouseMotion.new()
	motion.global_position = target
	view._input(motion)
	press.pressed = false
	press.global_position = target
	view._input(press)

func check(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		ui.get_tree().quit(1)
	return value

func wait_ready() -> bool:
	while Time.get_ticks_msec() < deadline:
		await ui.get_tree().create_timer(0.1).timeout
		if not ui.snapshot.is_empty() and ui.snapshot.get("connectionReady", false):
			await ui.get_tree().create_timer(0.2).timeout
			if not ui.snapshot.get("connectionReady", false):
				continue
			if not ui.snapshot.get("pendingDraws", []).is_empty() and ui.snapshot.asks.is_empty():
				var count_before: int = ui.snapshot.players[0].handCount
				var sent_before: int = ui.adapter.request_counter
				ui._intent("ok")
				if not check(ui.library_pile.draw_cue and ui.adapter.request_counter == sent_before, "A premature action must light the library without advancing Forge"): return false
				if not captured_draw:
					for arg in OS.get_cmdline_user_args():
						if arg.begins_with("--live-capture="):
							await ui._save_frame(arg.trim_prefix("--live-capture=").replace("live-table-1600", "live-draw-cue"))
					captured_draw = true
				ui._drag_library(Vector2(ui.hand_root.global_position.x + ui.hand_root.size.x * 0.5, ui.size.y - 40))
				manual_draws += 1
				while not ui.snapshot.get("connectionReady", false) and Time.get_ticks_msec() < deadline:
					await ui.get_tree().create_timer(0.1).timeout
				if not ui.snapshot.get("pendingDraws", []).is_empty():
					continue # A newer engine revision can reject the test gesture; review the new snapshot.
				if not check(ui.snapshot.players[0].handCount == count_before + 1, "The manual draw gesture must reveal exactly one engine-drawn card (before=%s after=%s)" % [count_before, ui.snapshot.players[0].handCount]): return false
				continue
			await ui.get_tree().create_timer(0.15).timeout
			if ui.snapshot.get("connectionReady", false) and ui.snapshot.get("pendingDraws", []).is_empty():
				return true
	return check(false, "Timed out waiting for Forge: " + ui.status_label.text)

func submit_choice() -> void:
	var ask: Dictionary = ui.snapshot.asks[0]
	print("Forge decision: ", ask.kind, " ", ask.get("title", ""))
	var panel: Control = ui.modal_panel
	if ask.kind in ["choose", "order"]:
		panel.chosen.clear()
		for i in range(int(ask.min)):
			panel._toggle(i)
		panel._submit()
	elif ask.kind == "message":
		panel._submit()
	elif ask.kind == "distribute":
		panel.amounts.fill(1 if ask.get("atLeastOne", false) else 0)
		if not panel.amounts.is_empty():
			panel.amounts[0] += int(ask.amount) - panel.amounts.reduce(func(a, b): return a + b, 0)
		panel._validate()
		panel._submit()
	else:
		check(false, "Unexpected integration-fixture decision: " + ask.kind)
	choices += 1

func run(table: Control) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--expect-scenario="):
			await load("res://tests/ScenarioIntegration.gd").new().run_scenario(table, arg.trim_prefix("--expect-scenario="))
			return
	if Array(OS.get_cmdline_user_args()).has("--expect-interactions"):
		await load("res://tests/InteractionIntegration.gd").new().run(table)
		return
	if Array(OS.get_cmdline_user_args()).has("--expect-mulligan"):
		await load("res://tests/MulliganIntegration.gd").new().run(table)
		return
	if Array(OS.get_cmdline_user_args()).has("--expect-colorless-payment"):
		await load("res://tests/ColorlessPaymentIntegration.gd").new().run(table)
		return
	if Array(OS.get_cmdline_user_args()).has("--expect-land-return"):
		await load("res://tests/LandReturnIntegration.gd").new().run(table)
		return
	if Array(OS.get_cmdline_user_args()).has("--expect-takeback"):
		await load("res://tests/TakebackIntegration.gd").new().run(table)
		return
	if Array(OS.get_cmdline_user_args()).has("--expect-mana-choices"):
		await load("res://tests/ManaChoiceIntegration.gd").new().run(table)
		return
	if Array(OS.get_cmdline_user_args()).has("--expect-decisions"):
		await load("res://tests/DecisionIntegration.gd").new().run(table)
		return
	ui = table
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 1000)
	deadline = Time.get_ticks_msec() + 110000
	if not await wait_ready(): return
	var session: String = ui.adapter.session
	if not check(ui.snapshot.players.size() == 3 and ui.snapshot.players[0].engineId == ui.adapter.seats[0], "Live seat mapping failed"): return
	if not check(not ui.return_button.visible, "Live mode must not offer mock returns"): return
	# Disconnect during an engine decision, then recover the same pending ask.
	if not ui.snapshot.asks.is_empty():
		var ask_id: int = ui.snapshot.asks[0].id
		ui.adapter.socket.close()
		await ui.get_tree().create_timer(0.4).timeout
		if not check(not ui.snapshot.connectionReady and ui.primary.disabled, "Disconnected controls must be disabled"): return
		if not await wait_ready(): return
		if not check(ui.adapter.session == session and ui.open_ask == ask_id, "Reconnect must restore the outstanding decision"): return
	# Startup notices, who starts, coin toss, keep, then priority in our main phase.
	var mulligans := 0
	var bottom_selected := false
	var opening_captured := false
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return
		if not ui.snapshot.asks.is_empty():
			submit_choice()
			continue
		var state: Dictionary = ui.snapshot
		print("Forge prompt: ", state.game.phase, " / ", state.prompt.message)
		if state.game.activePlayer == 0 and state.game.phase == "Main 1" and not state.game.get("mulligan", false) and str(state.prompt.message).contains("Priority:"):
			break
		if state.prompt.get("inputKind", "") == "InputConfirmMulligan":
			if not check(ui.opening_hand.visible and ui.opening_hand.views.size() == state.players[0].zones.Hand.size(), "Forge's opening hand must appear in the mulligan fan"): return
			if not opening_captured:
				for arg in OS.get_cmdline_user_args():
					if arg.begins_with("--live-capture="):
						await ui._save_frame(arg.trim_prefix("--live-capture=").replace("live-table-1600", "live-opening-hand"))
						ui.opening_hand.synthetic_hover = true
						ui.opening_hand.set_hover(3)
						await ui._save_frame(arg.trim_prefix("--live-capture=").replace("live-table-1600", "live-opening-hover"))
						ui.opening_hand.set_hover(-1)
						ui.opening_hand.synthetic_hover = false
				opening_captured = true
			if mulligans < 2:
				ui.opening_hand.submit("cancel")
				mulligans += 1
			else:
				ui.opening_hand.submit("ok")
		elif state.prompt.get("inputKind", "") == "InputLondonMulligan":
			if not check(ui.opening_hand.visible, "London bottom selection must remain in the opening fan"): return
			if state.prompt.okEnabled:
				if not check(not state.prompt.get("chosen", []).is_empty(), "Zero-card bottom selection must advance automatically without an integration-test click"): return
				# The payment suite drives the authoritative completed selection;
				# an earlier submitted opening-hand button may still be latched.
				ui._intent("ok")
			elif not bottom_selected:
				ui.opening_hand.card_chosen.emit(state.players[0].zones.Hand[0].id)
				bottom_selected = true
		elif StartingPlayerDialog.needs_selection(state):
			if not check(ui.modal.visible and ui.modal_panel is StartingPlayerDialog and ui.modal_panel.buttons.size() == state.players.size(), "Starting-player selection must open the portrait chooser"): return
			ui.modal_panel.buttons[0].pressed.emit()
		elif state.prompt.okEnabled:
			ui._primary_action()
		else:
			await ui.get_tree().create_timer(0.2).timeout
	if not check(ui.snapshot.game.phase == "Main 1", "Did not reach local main phase"): return
	if not check(mulligans == 2 and bottom_selected and not ui.opening_hand.visible, "Keep and both free/paid mulligans must finish through Forge"): return
	var original_stops: Dictionary = ui.snapshot.phaseStops.duplicate(true)
	for seat in [0, 1, 2]:
		for step in ui.TURN_STEPS:
			if not check(original_stops[seat][step] == (step in ["Main 1", "Declare attackers", "Declare blockers", "Main 2"]), "Every player's initial Forge stops must be M1/DA/DB/M2 only: seat=%s step=%s" % [seat, step]): return
	for seat in [0, 1, 2]:
		var original: bool = ui.phase_labels[seat]["Main 2"].button_pressed
		var before_color: Color = ui.phase_labels[seat]["Main 2"].get_theme_stylebox("normal").bg_color
		await ui._click_phase_button(seat, "Main 2")
		if not check(ui.phase_labels[seat]["Main 2"].button_pressed != original and ui.phase_labels[seat]["Main 2"].get_theme_stylebox("normal").bg_color != before_color, "Clicking any player's phase stop must update its visual state immediately"): return
		if not await wait_ready(): return
		if not check(ui.snapshot.phaseStops[seat]["Main 2"] != original and ui.phase_labels[seat]["Main 2"].button_pressed != original, "Forge must confirm the phase stop on the selected player's row"): return
		for other in [0, 1, 2]:
			if other != seat and not check(ui.snapshot.phaseStops[other]["Main 2"] == original_stops[other]["Main 2"], "Changing one player's stop must not change another player's row"): return
		await ui._click_phase_button(seat, "Main 2")
		if not await wait_ready(): return
		if not check(ui.snapshot.phaseStops[seat]["Main 2"] == original, "The second click must restore the same player's phase stop"): return
	var hand: Array = ui.snapshot.players[0].zones.Hand
	if not check(hand.size() >= 2, "Fixture opening hand missing"): return
	for player in ui.snapshot.players.slice(1):
		if not check(player.zones.Hand.all(func(c): return c.get("hidden", false) and not c.has("name") and not c.has("text")), "Opponent hand privacy lost"): return
	var land_id: int = hand[0].id
	var second_id: int = hand[1].id
	var original_card_size: Vector2 = ui.cards[land_id].size
	var play_target: Vector2 = ui.player_areas[0].get_global_rect().position + Vector2(220, 160)
	var hand_center: Vector2 = ui.cards[land_id].get_global_transform() * (ui.cards[land_id].size * 0.5)
	var before_cancel: int = ui.adapter.request_counter
	ui._drag_card(land_id, play_target - hand_center, true)
	if not check(ui.adapter.request_counter == before_cancel, "Canceling drag-to-play must not submit an action"): return
	hand_center = ui.cards[land_id].get_global_transform() * (ui.cards[land_id].size * 0.5)
	ui._drag_card(land_id, play_target - hand_center)
	if not check(ui.cards[land_id].size.is_equal_approx(original_card_size) and ui.cards[land_id].scale.is_equal_approx(Vector2.ONE), "Dropping a hand card must preserve its full dimensions before Forge responds"): return
	var submitted: int = ui.adapter.request_counter
	ui._pick(ui.cards[second_id].data, false)
	if not check(ui.adapter.request_counter == submitted, "Two clicks against one revision must not both submit"): return
	if not await wait_ready(): return
	if not check(ui.cards[land_id].data.zone == "Battlefield", "Forge did not play the land"): return
	if not check(ui.cards[land_id].size.is_equal_approx(original_card_size), "The engine-confirmed battlefield card must retain its hand size"): return
	var placed_center: Vector2 = ui.cards[land_id].get_global_transform() * (ui.cards[land_id].size * 0.5)
	if not check(placed_center.distance_to(play_target) < 1, "The played land must remain at the release position"): return
	if not check(ui.cards[land_id].data.availableActions.returnToHand, "Forge did not advertise undo for the immediate unused land play"): return
	ui._intent("attack", {"id": land_id, "target": 1})
	if not await wait_ready(): return
	if not check(ui.snapshot.combat.is_empty() and not ui.cards[land_id].data.tapped and ui.cards[land_id].data.availableActions.returnToHand, "Out-of-phase attack requests must be rejected without changing the land or combat"): return
	ui.cards[land_id]._on_enter()
	await ui.get_tree().create_timer(0.08).timeout
	if not check((ui.cards[land_id].get_global_transform() * (ui.cards[land_id].size * 0.5)).distance_to(play_target) < 1 and ui.cards[land_id].scale.is_equal_approx(Vector2.ONE), "A dropped card must not immediately lift or enlarge under the stationary pointer: center=%s target=%s scale=%s dropPointer=%s pointer=%s" % [ui.cards[land_id].get_global_transform() * (ui.cards[land_id].size * 0.5), play_target, ui.cards[land_id].scale, ui.cards[land_id].drop_pointer, ui.get_global_mouse_position()]): return
	# Review clicks and rejected plays must not consume a safe land undo.
	ui._choose_player(1)
	if not await wait_ready(): return
	if not check(ui.cards[land_id].data.availableActions.returnToHand, "Reviewing a player must preserve unused land return"): return
	hand_center = ui.cards[second_id].get_global_transform() * (ui.cards[second_id].size * 0.5)
	ui._drag_card(second_id, play_target - hand_center)
	if not await wait_ready(): return
	if not check(ui.cards[second_id].data.zone == "Hand" and ui.cards[land_id].data.availableActions.returnToHand, "A rejected second land must preserve the first land's return gesture"): return
	# Let the independently rejected second card finish returning before measuring undo.
	for _frame in range(20):
		if not ui.play_positions.has(second_id): break
		await ui.get_tree().create_timer(0.05).timeout
	await ui.get_tree().create_timer(0.2).timeout
	var commander_id: int = ui.snapshot.players[0].zones.Command[0].id
	if Array(OS.get_cmdline_user_args()).has("--expect-wrong-color"):
		commander_id = ui.snapshot.players[0].zones.Command.filter(func(card): return card.name == "Yoshimaru, Ever Faithful")[0].id
	# An unpaid cast is rolled back by Forge and must not consume the earlier land undo.
	for _attempt in range(2):
		ui._intent("card", {"id": commander_id})
		for _step in range(30):
			if not await wait_ready(): return
			if ui.adapter.prepaid_target < 0 and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": break
		if not check(ui.cards[land_id].data.availableActions.returnToHand and not ui.cards[land_id].data.tapped and ui.snapshot.players[0].zones.Command.any(func(card): return card.id == commander_id), "Repeated canceled unpaid spells must preserve the unused land's return permission and leave the attempted spell in its origin zone"): return
	var return_target: Vector2 = ui.hand_root.global_position + Vector2(ui.hand_root.size.x * 0.5, 100)
	ui._drag_card(land_id, return_target - placed_center)
	if not check(ui.cards[land_id].get_parent() == ui.hand_root and ui.cards[land_id].hand_mode and ui.pending_returns.has(land_id), "An undo drop must preview in the hand before Forge responds"): return
	var return_pose: Transform2D = ui.cards[land_id].get_global_transform()
	var return_animation: Tween = ui.cards[land_id].animation
	ui._layout_board()
	if not check(ui.cards[land_id].get_global_transform().is_equal_approx(return_pose), "A pending undo must not animate back toward its former board position"): return
	if not await wait_ready(): return
	if not check(ui.cards[land_id].data.zone == "Hand" and not ui.manual_positions.has(land_id), "Dragging the unused land into hand must invoke Forge undo"): return
	if not check(ui.pending_returns.is_empty() and ui.cards[land_id].animation == return_animation, "Forge confirmation must not restart the hand settle animation"): return
	if not check(ui.cards[land_id].position.is_equal_approx(ui.cards[land_id].resting_position) and is_equal_approx(ui.cards[land_id].rotation, ui.cards[land_id].base_rotation), "The return must finish in its chosen fan slot"): return
	hand_center = ui.cards[land_id].get_global_transform() * (ui.cards[land_id].size * 0.5)
	ui._drag_card(land_id, play_target - hand_center)
	if not await wait_ready(): return
	if not check(ui.cards[land_id].data.zone == "Battlefield", "Undo must also restore the land-play allowance"): return
	hand_center = ui.cards[second_id].get_global_transform() * (ui.cards[second_id].size * 0.5)
	ui._drag_card(second_id, play_target - hand_center)
	if not await wait_ready(): return
	if not check(ui.cards[second_id].data.zone == "Hand", "Forge allowed a second land in the turn"): return
	# Cast the one-mana fixture commander through the same callback as a zone card.
	# No floating mana: Forge must cancel payment rather than asking us to tap later.
	var priority_before_cast: int = ui.adapter.auto_priority_passes
	drag_commander(commander_id, play_target)
	for _step in range(30):
		if not await wait_ready(): return
		if ui.adapter.prepaid_target < 0 and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": break
	if not check(ui.snapshot.players[0].zones.Command.any(func(card): return card.id == commander_id) and not ui.cards[land_id].data.tapped, "Insufficient floating mana must cancel without tapping extra sources"): return
	ui._pick(ui.cards[land_id].data, false)
	if not await wait_ready(): return
	var wrong_color := Array(OS.get_cmdline_user_args()).has("--expect-wrong-color")
	if not check(ui.cards[land_id].data.tapped and int(ui.snapshot.players[0].mana.get("U" if wrong_color else "W", 0)) == 1, "Tapping the land before casting must float mana"): return
	for _click in range(3):
		if not check(ui.cards[land_id].data.availableActions.undoTap, "Forge must advertise undo for the latest unspent mana activation"): return
		ui._pick(ui.cards[land_id].data, false)
		if not await wait_ready(): return
		if not check(ui.snapshot.asks.is_empty() and not ui.cards[land_id].data.tapped and int(ui.snapshot.players[0].mana.get("U" if wrong_color else "W", 0)) == 0, "Clicking an unused mana source must undo both the tap and its generated mana"): return
		ui._pick(ui.cards[land_id].data, false)
		if not await wait_ready(): return
		if not check(ui.cards[land_id].data.tapped and int(ui.snapshot.players[0].mana.get("U" if wrong_color else "W", 0)) == 1, "Repeated tap/undo cycles must never accumulate extra mana"): return
	if Array(OS.get_cmdline_user_args()).has("--expect-artifact"):
		# One floating white cannot cast the two-mana commander. Refund the
		# partial payment, then undo that land by clicking it, without the undo button.
		for _attempt in range(2):
			var passes_before: int = ui.adapter.auto_priority_passes
			ui._intent("card", {"id": commander_id})
			for _step in range(30):
				if not await wait_ready(): return
				if ui.adapter.prepaid_target < 0 and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": break
			if not check(ui.snapshot.players[0].zones.Command.any(func(card): return card.id == commander_id) and int(ui.snapshot.players[0].mana.get("W", 0)) == 1 and ui.cards[land_id].data.availableActions.undoTap and ui.adapter.auto_priority_passes == passes_before, "Canceled partial payment must preserve refunded mana and click undo without passing priority: " + str(ui.snapshot.prompt) + " card=" + str(ui.cards[land_id].data)): return
		ui._pick(ui.cards[land_id].data, false)
		if not await wait_ready(): return
		if not check(not ui.cards[land_id].data.tapped and ui.snapshot.players[0].mana.get("W", 0) == 0, "A single land click must traverse canceled-cast checkpoints and undo its mana tap"): return
		ui._pick(ui.cards[land_id].data, false)
		if not await wait_ready(): return
		# Spend no mana outside Forge: advance normally, play the second land, then
		# float exactly two mana from the two real sources for the artifact cast.
		var previous_turn: int = ui.snapshot.game.turn
		for _step in range(90):
			if ui.snapshot.game.activePlayer == 0 and ui.snapshot.game.turn > previous_turn and ui.snapshot.game.phase == "Main 1": break
			if not ui.snapshot.asks.is_empty():
				submit_choice()
			elif ui.snapshot.prompt.okEnabled:
				ui._primary_action()
			if not await wait_ready(): return
		ui._intent("card", {"id": second_id})
		if not await wait_ready(): return
		if not check(ui.cards[second_id].data.zone == "Battlefield", "Second-turn artifact fixture must legally play its second land: prompt=%s card=%s feedback=%s modal=%s" % [ui.snapshot.prompt, ui.cards[second_id].data, ui.toast.text, ui.modal.visible]): return
		for source_id in [land_id, second_id]:
			ui._pick(ui.cards[source_id].data, false)
			if not await wait_ready(): return
		if not check(int(ui.snapshot.players[0].mana.get("W", 0)) == 2, "The artifact must be paid with exactly two pre-tapped lands"): return
		ui._pick(ui.cards[second_id].data, false)
		if not await wait_ready(): return
		if not check(not ui.cards[second_id].data.tapped and ui.cards[land_id].data.availableActions.undoTap, "Undoing the newest land must expose the preceding unspent tap"): return
		ui._pick(ui.cards[land_id].data, false)
		if not await wait_ready(): return
		if not check(not ui.cards[land_id].data.tapped and ui.snapshot.players[0].mana.get("W", 0) == 0, "Sequential land clicks must remove exactly their generated mana"): return
		for source_id in [land_id, second_id]:
			ui._pick(ui.cards[source_id].data, false)
			if not await wait_ready(): return
	priority_before_cast = ui.adapter.auto_priority_passes
	drag_commander(commander_id, play_target)
	if not await wait_ready(): return
	if wrong_color:
		for _step in range(30):
			if not await wait_ready(): return
			if ui.adapter.prepaid_target < 0 and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": break
		if not check(ui.snapshot.players[0].zones.Command.any(func(card): return card.id == commander_id) and int(ui.snapshot.players[0].mana.get("U", 0)) == 1, "Wrong-colored floating mana must cancel the cast and remain available"): return
		if not check(ui.cards[land_id].data.availableActions.undoTap, "Wrong-colored canceled payment must preserve click-to-undo mana"): return
		ui._pick(ui.cards[land_id].data, false)
		if not await wait_ready(): return
		if not check(not ui.cards[land_id].data.tapped and ui.snapshot.players[0].mana.get("U", 0) == 0, "Wrong-colored payment cancellation must allow one-click undo without retaining mana"): return
		print("PASS: Godot live integration (wrong-colored floating mana cancels without auto-tapping sources)")
		ui.get_tree().quit()
		return
	for _step in range(12):
		if ui.snapshot.players[0].zones.Battlefield.any(func(c): return c.id == commander_id): break
		if not ui.snapshot.asks.is_empty():
			submit_choice()
		elif ui.adapter.prepaid_target >= 0:
			await ui.get_tree().create_timer(0.2).timeout
		elif ui.snapshot.get("autoPassStackId", -1) >= 0:
			await ui.get_tree().create_timer(0.2).timeout
		elif ui.snapshot.prompt.okEnabled:
			ui._primary_action()
		else:
			await ui.get_tree().create_timer(0.2).timeout
		if not await wait_ready(): return
	if not check(ui.cards.has(commander_id) and ui.cards[commander_id].data.zone == "Battlefield", "Commander casting/payment/resolution failed"): return
	if ui.cards[commander_id].data.get("commander", false):
		if not check(int(ui.cards[commander_id].data.get("commanderTax", -1)) == 2, "A commander cast from the command zone must advertise two additional generic mana for its next cast"): return
	if not check(ui.adapter.auto_priority_passes > priority_before_cast, "A routine paid cast must resolve without a manual priority click"): return
	if not check(ui.cards[land_id].data.tapped, "Forge's payment did not tap the land"): return
	if not check(not ui.cards[land_id].data.availableActions.undoTap, "Spending mana must revoke click-to-untap permission"): return
	var paid_pool: Dictionary = ui.snapshot.players[0].mana.duplicate(true)
	ui._pick(ui.cards[land_id].data, false)
	if not await wait_ready(): return
	if not check(ui.cards[land_id].data.tapped and ui.snapshot.players[0].mana == paid_pool and ui.cards[commander_id].data.zone == "Battlefield", "Clicking a spent mana source must not untap it, refund mana, or undo the paid spell"): return
	ui._intent("undo_tap", {"id": land_id})
	if not await wait_ready(): return
	if not check(ui.cards[land_id].data.tapped and ui.cards[commander_id].data.zone == "Battlefield", "The bridge must reject a stale/forged mana-untap request after payment"): return
	if not check(not ui.cards[land_id].data.availableActions.returnToHand, "Using a land must remove card-specific return permission"): return
	var requests_after_use: int = ui.adapter.request_counter
	ui._intent("return_to_hand", {"id": land_id})
	if not check(ui.adapter.request_counter == requests_after_use and ui.cards[land_id].data.zone == "Battlefield", "A used card must not send a card-specific undo request"): return
	var casting_turn: int = ui.snapshot.game.turn
	for _step in range(90):
		if ui.snapshot.game.activePlayer == 0 and ui.snapshot.game.turn > casting_turn and ui.snapshot.game.phase == "Declare attackers": break
		if not ui.snapshot.asks.is_empty():
			submit_choice()
		elif ui.snapshot.prompt.okEnabled:
			ui._primary_action()
		else:
			await ui.get_tree().create_timer(0.2).timeout
		if not await wait_ready(): return
	if not check(ui.snapshot.game.phase == "Declare attackers" and ui.snapshot.game.activePlayer == 0, "Did not reach a later legal attack step"): return
	var before_attack: int = ui.adapter.request_counter
	ui._pick(ui.cards[commander_id].data, false)
	if not check(ui.targeting and ui.primary.disabled and not ui.targeting_overlay.lines.is_empty() and ui.targeting_overlay.lines[0][1] == Vector2.INF and ui.adapter.request_counter == before_attack and ui.snapshot.combat.is_empty(), "Choosing an attacker must start an arrow without declaring against a default defender"): return
	ui._choose_player(0)
	ui._primary_action()
	if not check(ui.targeting and ui.adapter.request_counter == before_attack, "Self-targeting and advancing while choosing a defender must not submit actions"): return
	ui._secondary_action()
	if not check(not ui.targeting and ui.adapter.request_counter == before_attack and ui.snapshot.combat.is_empty(), "Canceling the arrow must not trigger Forge's alpha strike"): return
	ui._pick(ui.cards[commander_id].data, false)
	ui._pick(ui.cards[commander_id].data, false)
	if not check(not ui.targeting and ui.adapter.request_counter == before_attack, "Clicking the selected attacker again must cancel only the local arrow"): return
	ui._pick(ui.cards[commander_id].data, false)
	ui._choose_player(2)
	if not await wait_ready(): return
	if not check(not ui.targeting and ui.snapshot.combat.any(func(entry): return entry.attacker == commander_id and entry.defenderId == 2), "Attacker-first declaration must use the clicked second opponent"): return
	ui._pick(ui.cards[commander_id].data, false)
	ui._choose_player(1)
	if not await wait_ready(): return
	if not check(ui.snapshot.combat.any(func(entry): return entry.attacker == commander_id and entry.defenderId == 1), "Forge did not declare the attacker against the chosen defender"): return
	ui._pick(ui.cards[commander_id].data, false)
	ui._choose_player(1)
	if not await wait_ready(): return
	if not check(ui.snapshot.combat.filter(func(entry): return entry.attacker == commander_id).size() == 1, "Choosing the same defender again must keep exactly one declaration"): return
	ui._primary_action()
	if not await wait_ready(): return
	if not check(ui.cards[commander_id].data.tapped, "Committing attackers must use Forge's tap state"): return
	if not check(not ui.cards[commander_id].data.availableActions.undoTap, "A combat tap must never advertise free untapping"): return
	ui._intent("undo_tap", {"id": commander_id})
	if not await wait_ready(): return
	if not check(ui.cards[commander_id].data.tapped and ui.snapshot.combat.any(func(entry): return entry.attacker == commander_id), "The bridge must reject an untap request for an attacking creature"): return
	if not check(manual_draws > 0, "The live match must exercise the manual draw gate"): return
	# Recover a real board without replaying any action.
	var sent_before: int = ui.adapter.request_counter
	ui.adapter.socket.close()
	await ui.get_tree().create_timer(0.4).timeout
	if not await wait_ready(): return
	if not check(ui.adapter.session == session and ui.adapter.request_counter == sent_before and ui.cards[commander_id].data.zone == "Battlefield", "Reconnect replayed an action or lost board state"): return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--live-capture="):
			ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ui.capture_size = Vector2i(1600, 1000)
			await ui._save_frame(arg.trim_prefix("--live-capture="))
			ui.capture_size = Vector2i(1280, 800)
			ui.get_window().size = ui.capture_size
			await ui._save_frame(arg.trim_prefix("--live-capture=").replace("1600", "1280"))
	print("PASS: Godot live integration (manual draw/cue, insufficient floating mana cancellation, prepaid casting, fixed drop position, drag-to-undo/replay land, used-card rejection, second-land rejection, stack resolution, attack/defender, duplicate guard, reconnect, hidden hands; generic choices exercised: ", choices, ")")
	ui.get_tree().quit()
