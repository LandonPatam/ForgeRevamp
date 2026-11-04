extends "res://tests/DecisionIntegration.gd"

func tap_for(card: Dictionary, color: String, damage: int) -> bool:
	var life_before: int = ui.snapshot.players[0].life
	var mana_before: int = ui.snapshot.players[0].mana.get(color, 0)
	ui._click_card(card.id)
	if not await resolve_to_choice(): return false
	var ask: Dictionary = ui.snapshot.asks[0]
	if not check(ask.options.size() == 3, "Pain land must offer three initial mana choices: " + str(ask)): return false
	var fragment: String = {"C": "Add {C}", "U": "Blue", "B": "Black"}[color]
	if not await choose_named(fragment): return false
	if not check(ui.snapshot.asks.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority", "Choosing mana must not require a second color/stack prompt: " + str(ui.snapshot.prompt)): return false
	if not check(ui.snapshot.players[0].mana.get(color, 0) == mana_before + 1 and ui.cards[card.id].data.tapped, "Forge must produce exactly the chosen mana and tap the source: color=%s before=%s mana=%s tapped=%s options=%s" % [color, mana_before, ui.snapshot.players[0].mana, ui.cards[card.id].data.tapped, ask.options]): return false
	var mana_button: Button = ui.mana_buttons[["W", "U", "B", "R", "G", "C"].find(color)]
	if not check(mana_button.text == str(mana_before + 1) and not mana_button.disabled, "Chosen mana must appear in the actual enabled pool counter: " + mana_button.text): return false
	return check(ui.snapshot.players[0].life == life_before - damage, "Colored mana must deal exactly one damage; colorless must not")

func run(table: Control) -> void:
	ui = table
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 1000)
	deadline = Time.get_ticks_msec() + 110000
	if not await advance_to_main(): return
	var card: Dictionary = find_card("Underground River")
	ui._click_card(card.id)
	if not await wait_ready(): return
	ui._click_card(card.id)
	if not await resolve_to_choice(): return
	ui._intent("answer", {"id": ui.snapshot.asks[0].id, "value": []})
	if not await wait_ready(): return
	if not check(not ui.cards[card.id].data.tapped and ui.snapshot.players[0].mana.is_empty(), "Canceling the initial picker must not tap or produce mana"): return
	if not check(ui.cards[card.id].data.availableActions.returnToHand, "Canceling a mana picker must preserve the unused land's return permission"): return
	if not await tap_for(card, "C", 0): return
	ui._click_card(card.id) # Engine-authorized undo of an unused colorless activation.
	if not await wait_ready(): return
	if not check(not ui.cards[card.id].data.tapped and ui.snapshot.players[0].mana.get("C", 0) == 0, "Colorless tap undo must remove its mana"): return
	if not check(ui.cards[card.id].data.availableActions.returnToHand, "Undoing a complete mana activation must restore the land's return permission"): return
	ui._intent("return_to_hand", {"id": card.id})
	if not await wait_ready(): return
	if not check(zone("Hand").any(func(value): return value.id == card.id), "The undone land must actually return to hand"): return
	ui._click_card(card.id)
	if not await wait_ready(): return
	if not await tap_for(card, "U", 1): return
	if ui.cards[card.id].data.availableActions.undoTap:
		var damaged_life: int = ui.snapshot.players[0].life
		ui._click_card(card.id)
		if not await wait_ready(): return
		if not check(not ui.cards[card.id].data.tapped and ui.snapshot.players[0].mana.get("U", 0) == 0 and ui.snapshot.players[0].life == damaged_life + 1, "Authorized undo must reverse mana and damage together with the tap"): return
		if not check(ui.cards[card.id].data.availableActions.returnToHand, "Undoing mana and pain damage must restore land return permission"): return
		if not await tap_for(card, "U", 1): return
	if not await advance_to_main(int(ui.snapshot.game.turn)): return
	if not await tap_for(card, "B", 1): return
	var pool: Dictionary = ui.snapshot.players[0].mana.duplicate(true)
	ui._intent("card", {"id": card.id}) # Raw activation, not the client click-to-undo gesture.
	if not await wait_ready(): return
	if not check(ui.snapshot.asks.is_empty() and ui.snapshot.players[0].mana == pool and ui.cards[card.id].data.tapped, "Repeated clicks on a tapped pain land must not add mana"): return
	# A second untapped source remains usable when we receive priority on an opponent's turn.
	var second: Dictionary = find_card("Underground River")
	ui._click_card(second.id)
	if not await wait_ready(): return
	for seat in [1, 2]:
		ui._set_phase_stop(seat, "Main 1", true)
		if not await wait_ready(): return
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return
		if ui.snapshot.game.activePlayer != 0 and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": break
		if not ui.snapshot.asks.is_empty(): submit_choice()
		elif ui.snapshot.prompt.okEnabled: ui._primary_action()
	if not check(ui.snapshot.game.activePlayer != 0, "Must reach opponent priority window"): return
	if not await tap_for(second, "U", 1): return
	print("PASS: Godot live integration (single pain-land C/U/B picker, cancellation, exact mana and damage, complete mana-tap undo, repeated-activation rejection, opponent-turn activation with priority)")
	ui.get_tree().quit()
