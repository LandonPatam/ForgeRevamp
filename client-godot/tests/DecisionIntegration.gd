extends "res://tests/LiveIntegration.gd"
var free_redraw := false

func zone(name: String) -> Array:
	return ui.snapshot.players[0].zones[name]

func find_card(name: String, where: String = "Hand") -> Dictionary:
	for card in zone(where):
		if card.get("name", "") == name:
			return card
	return {}

func advance_to_main(after_turn: int = -1) -> bool:
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty():
			var ask: Dictionary = ui.snapshot.asks[0]
			if ask.kind in ["choose", "order"] and ask.min == 0 and not ask.options.is_empty():
				ui.modal_panel._toggle(0)
				ui.modal_panel._submit()
			else:
				submit_choice()
			continue
		var state: Dictionary = ui.snapshot
		var kind: String = state.prompt.get("inputKind", "")
		if state.game.activePlayer == 0 and state.game.phase == "Main 1" and kind == "InputPassPriority" and state.game.turn > after_turn:
			return true
		if kind == "InputConfirmMulligan":
			if not free_redraw and ["Evolving Wilds", "Azorius Chancery", "Ash Barrens"].any(func(name): return find_card(name).is_empty()):
				free_redraw = true
				ui.opening_hand.submit("cancel")
			else:
				ui.opening_hand.submit("ok")
		elif ui.modal_panel is SelectionDialog:
			if not ui.modal_panel.confirm_button.disabled:
				ui.modal_panel.confirm_button.pressed.emit()
			else:
				ui.modal_panel.option_buttons[0].pressed.emit()
		elif kind == "InputLondonMulligan":
			if state.prompt.okEnabled: ui._intent("ok")
			else: ui.opening_hand.card_chosen.emit(zone("Hand")[0].id)
		elif str(state.prompt.message).to_lower().contains("portrait"):
			ui._choose_player(0)
		elif state.prompt.okEnabled:
			ui._primary_action()
	return check(false, "Cannot reach main phase for decision test")

func resolve_to_choice() -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() < mini(deadline, started + 9000):
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty() or ui.modal_panel is SelectionDialog:
			var panel: Control = ui.modal_panel
			var requests: int = ui.adapter.request_counter
			var outside := InputEventMouseButton.new()
			outside.button_index = MOUSE_BUTTON_LEFT
			outside.pressed = true
			outside.position = Vector2(2, 2)
			ui.modal.get_child(0).gui_input.emit(outside)
			if not check(ui.modal.visible and ui.modal_panel == panel and ui.adapter.request_counter == requests, "Outside clicks must preserve real Forge decisions without submitting an action"): return false
			return check(Time.get_ticks_msec() - started < 10000, "Decision must unlock before the 12-second request timeout")
		if ui.snapshot.prompt.get("inputKind", "") == "InputConfirm" and ui.snapshot.prompt.okEnabled:
			ui._primary_action() # Explicit sacrifice-cost confirmation, not a selection.
		await ui.get_tree().create_timer(0.2).timeout
	return check(false, "Expected a real engine decision: " + str(ui.snapshot.prompt) + " stack=" + str(ui.snapshot.stack) + " auto=" + str(ui.snapshot.get("autoPassStackId", -1)))

func choose_named(fragment: String) -> bool:
	if not await resolve_to_choice(): return false
	if not ui.snapshot.asks.is_empty():
		var ask: Dictionary = ui.snapshot.asks[0]
		# Delayed reveal can require an informational acknowledgment before choosing.
		if ask.kind == "message":
			ui.modal_panel._submit()
			return await choose_named(fragment)
		for i in range(ask.options.size()):
			if str(ask.options[i].label).to_lower().contains(fragment.to_lower()):
				ui.modal_panel._toggle(i)
				ui.modal_panel._submit()
				return await wait_ready()
	else:
		for i in range(ui.modal_panel.options.size()):
			if str(ui.modal_panel.options[i].get("name", "")).contains(fragment):
				ui.modal_panel.option_buttons[i].pressed.emit()
				if not await wait_ready(): return false
				if is_instance_valid(ui.modal_panel) and ui.modal_panel is SelectionDialog and not ui.modal_panel.confirm_button.disabled:
					ui.modal_panel.confirm_button.pressed.emit()
				return await wait_ready()
	return check(false, "Missing engine option: " + fragment)

const SelectionDialog = preload("res://scripts/ui/SelectionPanel.gd")

func run(table: Control) -> void:
	ui = table
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 1000)
	deadline = Time.get_ticks_msec() + 110000
	if not await advance_to_main(): return
	# Keep the fixture robust to shuffled openers by drawing through real turns.
	for name in ["Evolving Wilds", "Azorius Chancery", "Ash Barrens"]:
		while find_card(name).is_empty():
			if not await advance_to_main(int(ui.snapshot.game.turn)): return
		var card: Dictionary = find_card(name)
		print("Testing engine card: ", name)
		if name == "Ash Barrens":
			var basic: Dictionary = find_card("Island", "Battlefield")
			if not check(not basic.is_empty() and not basic.tapped, "Searched land must untap for landcycling payment"): return
			ui._click_card(basic.id)
			if not await wait_ready(): return
			var began := Time.get_ticks_msec()
			ui._click_card(card.id)
			if not await choose_named("cycling"): return
			if not check(Time.get_ticks_msec() - began < 10000, "Ability choice cannot wait for the connection timeout"): return
			# Pay the cycling cost with the existing floating blue mana if Forge asks.
			if ui.snapshot.prompt.get("inputKind", "").begins_with("InputPayMana"):
				ui._intent("mana", {"id": 2})
				if not await wait_ready(): return
			if not await choose_named("Plains"): return
			if not check(not find_card("Plains").is_empty() and not find_card("Ash Barrens", "Graveyard").is_empty(), "Landcycling must discard Ash Barrens and put the chosen basic into hand"): return
		else:
			ui._click_card(card.id)
			if not await wait_ready(): return
			if name == "Evolving Wilds":
				ui._click_card(card.id)
				if not await choose_named("Island"): return
				if not check(not find_card("Island", "Battlefield").is_empty() and find_card("Island", "Battlefield").tapped and not find_card(name, "Graveyard").is_empty(), "Evolving Wilds must sacrifice and fetch the chosen basic tapped"): return
			else:
				if not check(not find_card(name, "Battlefield").is_empty() and find_card(name, "Battlefield").tapped, "Chancery must enter tapped"): return
				if not await choose_named("Azorius Chancery"): return
				if not check(find_card(name, "Battlefield").is_empty() and not find_card(name).is_empty(), "Mandatory Chancery trigger must return the selected land to hand"): return
		if name != "Ash Barrens" and not await advance_to_main(int(ui.snapshot.game.turn)): return
	print("PASS: Godot live integration (Evolving Wilds choice, immediate Ash Barrens ability dialog, mandatory Chancery return)")
	ui.get_tree().quit()
