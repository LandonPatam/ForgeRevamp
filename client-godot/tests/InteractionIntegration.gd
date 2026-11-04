extends "res://tests/DecisionIntegration.gd"

func run(table: Control) -> void:
	ui = table
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 1000)
	deadline = Time.get_ticks_msec() + 110000
	var mulligans := 0
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return
		if not ui.snapshot.asks.is_empty():
			submit_choice()
			continue
		var state: Dictionary = ui.snapshot
		var kind: String = state.prompt.get("inputKind", "")
		if kind == "InputConfirmMulligan":
			if (find_card("Island").is_empty() or find_card("Spell Pierce").is_empty()) and mulligans < 3:
				mulligans += 1
				ui.opening_hand.submit("cancel")
			else: ui.opening_hand.submit("ok")
		elif kind == "InputLondonMulligan":
			if state.prompt.okEnabled: ui.opening_hand.submit("ok")
			else:
				var protected_ids := [find_card("Island").get("id", -1), find_card("Spell Pierce").get("id", -1)]
				var candidate: Dictionary = zone("Hand").filter(func(card): return not state.prompt.get("chosen", []).has("card:" + str(card.id)) and not protected_ids.has(card.id))[0]
				ui.opening_hand.card_chosen.emit(candidate.id)
		elif StartingPlayerDialog.needs_selection(state): ui.modal_panel.buttons[0].pressed.emit()
		elif state.game.activePlayer == 0 and state.game.phase == "Main 1" and kind == "InputPassPriority": break
		elif state.prompt.okEnabled: ui._primary_action()
	var island: Dictionary = find_card("Island")
	var counter: Dictionary = find_card("Spell Pierce")
	if not check(not island.is_empty() and not counter.is_empty(), "Fixture requires Island and Spell Pierce"): return
	ui._click_card(island.id)
	if not await wait_ready(): return
	ui._click_card(island.id)
	if not await wait_ready(): return
	if not check(ui.snapshot.players[0].mana.get("U", 0) == 1, "Hold one blue mana for the response"): return
	# Hold the land rather than floating mana across phases.
	ui._click_card(island.id)
	if not await wait_ready(): return
	var original := -1
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return
		if not ui.snapshot.asks.is_empty():
			submit_choice()
			continue
		if not ui.snapshot.stack.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority" and ui.snapshot.stack[0].get("sourceName", "") == "Ponder":
			original = int(ui.snapshot.stack[0].id)
			break
		if ui.snapshot.prompt.okEnabled: ui._primary_action()
	if not check(original >= 0 and not ui.incoming_effect.panel.visible, "An opponent's routine non-targeted sorcery stays in the rail"): return
	ui.incoming_effect.review()
	if not check(ui.incoming_effect.rules.text == ui.snapshot.stack[0].text, "Show the actual pending spell text"): return
	var before: int = ui.adapter.request_counter
	ui.incoming_effect.browse_button.pressed.emit()
	if not check(not ui.incoming_effect.panel.visible and not ui.interaction_panel.panel.visible and ui.adapter.request_counter == before, "Respond exposes the board without another popup or passing priority"): return
	ui._click_card(island.id)
	if not await wait_ready(): return
	ui._click_card(counter.id)
	if not await resolve_to_choice(): return
	var index := -1
	if ui.snapshot.asks.is_empty():
		if not check(ui.snapshot.prompt.get("inputKind", "") == "InputSelectStackItems" and ui.modal_panel is SelectionDialog, "Counterspell targeting must use a card gallery"): return
		for i in range(ui.modal_panel.options.size()):
			if int(ui.modal_panel.options[i].id) == original: index = i
		if not check(index >= 0, "The gallery must offer the opponent's exact spell instance"): return
		ui.modal_panel.option_buttons[index].pressed.emit()
	else:
		var ask: Dictionary = ui.snapshot.asks[0]
		for i in range(ask.options.size()):
			if int(ask.options[i].get("stackId", -1)) == original: index = i
		if not check(index >= 0 and ask.options[index].has("card"), "Callback target choices must also include exact stack IDs and visible card faces: " + JSON.stringify(ask)): return
		ui.modal_panel.option_buttons[index].pressed.emit()
		ui.modal_panel.confirm_button.pressed.emit()
	if not await wait_ready(): return
	for attempt in range(30):
		var responses: Array = ui.snapshot.stack.filter(func(item): return int(item.get("sourceId", -1)) == int(counter.id))
		if responses.is_empty() and not ui.snapshot.stack.any(func(item): return int(item.id) == original): break
		if not responses.is_empty():
			if not check(responses[0].targets.any(func(target): return target.kind == "stack" and int(target.id) == original), "The response must retain the exact targeted spell"): return
			if not check(not ui.incoming_effect.panel.visible, "Our chosen counterspell must not reopen as another effect preview"): return
			if ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority" and not ui.Live.is_automatic_stack(ui.snapshot): ui._primary_action()
		if not await wait_ready(): return
	if not check(not ui.snapshot.stack.any(func(item): return int(item.id) == original or int(item.get("sourceId", -1)) == int(counter.id)) and zone("Graveyard").any(func(card): return card.id == counter.id), "Rail OK resolves this response even if another opponent immediately casts a new spell"): return
	if not check(int(ui.incoming_effect.active.get("stackId", -1)) != original, "The already reviewed countered spell must not reopen its popup"): return
	if not check(ui.snapshot.players.slice(1).any(func(player): return player.zones.Graveyard.any(func(card): return card.name == "Ponder")), "The countered spell must reach its owner's graveyard"): return
	print("PASS: Godot live integration (explicit review without passing, preserved counterspell window, exact stack target and no repeated own-effect preview)")
	ui.get_tree().quit()
