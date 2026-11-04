extends "res://tests/LiveIntegration.gd"

func ready_main(after_turn: int = -1) -> bool:
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty():
			submit_choice()
			continue
		var state: Dictionary = ui.snapshot
		var kind: String = state.prompt.get("inputKind", "")
		if kind == "InputPassPriority" and state.game.activePlayer == 0 and state.game.phase == "Main 1" and state.game.turn > after_turn: return true
		if StartingPlayerDialog.needs_selection(state): ui.modal_panel.buttons[0].pressed.emit()
		elif kind == "InputConfirmMulligan":
			var hand: Array = state.players[0].zones.Hand
			if hand.filter(func(card): return card.name == "Plains").size() < 4 or not hand.any(func(card): return card.name == "Thran Dynamo"):
				ui.opening_hand.submit("cancel")
			else: ui.opening_hand.submit("ok")
		elif kind == "InputLondonMulligan":
			if state.prompt.okEnabled: ui._intent("ok")
			else:
				var hand: Array = state.players[0].zones.Hand
				var basics: Array = hand.filter(func(card): return card.name == "Plains")
				var extras: Array = hand.filter(func(card): return card.name == "Thran Dynamo")
				ui.opening_hand.card_chosen.emit(basics[-1].id if basics.size() > 4 else extras[-1].id)
		elif state.prompt.okEnabled: ui._primary_action()
	return check(false, "Could not reach main phase for takeback test")

func run(table: Control) -> void:
	ui = table
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 1000)
	deadline = Time.get_ticks_msec() + 115000
	if not await ready_main(): return
	var lands: Array[int] = []
	for i in range(4):
		var land: Dictionary = ui.snapshot.players[0].zones.Hand.filter(func(card): return card.name == "Plains")[0]
		lands.append(int(land.id))
		ui._intent("card", {"id": land.id})
		if not await wait_ready(): return
		if i < 3 and not await ready_main(int(ui.snapshot.game.turn)): return
	var spell: Dictionary = ui.snapshot.players[0].zones.Hand.filter(func(card): return card.name == "Thran Dynamo")[0]
	var target: Vector2 = ui.player_areas[0].get_global_rect().get_center()
	for id in lands:
		ui._pick(ui.cards[id].data, false)
		if not await wait_ready(): return
	if not check(ui.snapshot.players[0].mana.get("W", 0) == 4, "Four mana must be floated before casting"): return
	var passes_before: int = ui.adapter.auto_priority_passes
	var center: Vector2 = ui.cards[spell.id].get_global_rect().get_center()
	ui._drag_card(spell.id, target - center)
	for step in range(40):
		if not await wait_ready(): return
		if ui.snapshot.players[0].zones.Battlefield.any(func(card): return card.id == spell.id): break
		await ui.get_tree().create_timer(0.1).timeout
	if not check(ui.cards[spell.id].data.zone == "Battlefield" and ui.adapter.auto_priority_passes > passes_before and ui.snapshot.players[0].mana.get("W", 0) == 0, "The paid artifact must resolve automatically without Continue"): return
	if not check(ui.snapshot.get("takebackCast", {}).is_empty() and not ui.cards[spell.id].data.availableActions.returnToHand, "Automatic commitment must close the cast's takeback window"): return
	ui._intent("return_to_hand", {"id": spell.id})
	if not check(ui.cards[spell.id].data.zone == "Battlefield" and lands.all(func(id): return ui.cards[id].data.tapped), "A committed cast cannot restore the card or its spent sources"): return
	ui.adapter.send_intent({"action": "undo_card", "id": spell.id})
	if not await wait_ready(): return
	ui._intent("undo")
	if not await wait_ready(): return
	if not check(ui.cards[spell.id].data.zone == "Battlefield" and lands.all(func(id): return ui.cards[id].data.tapped), "Generic undo and forged takebacks must not cross the cast commitment"): return
	print("PASS: Godot live integration (four-mana artifact, automatic commitment without Continue, post-resolution takeback rejection)")
	ui.get_tree().quit()
