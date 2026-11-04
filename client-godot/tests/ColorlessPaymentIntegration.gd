extends "res://tests/DecisionIntegration.gd"
var redraw_used := false
var saw_ring_on_stack := false

func has_setup() -> bool:
	return ["Plains", "Forest", "Sol Ring", "Forgotten Ancient"].all(func(name): return not find_card(name).is_empty())

func choose_extra(cards: Array) -> int:
	for card in cards:
		if cards.filter(func(other): return other.get("name", "") == card.get("name", "")).size() > 1:
			return int(card.id)
	return int(cards[0].id)

func ready_main(after_turn: int = -1) -> bool:
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return false
		var state: Dictionary = ui.snapshot
		var kind: String = state.prompt.get("inputKind", "")
		if not state.asks.is_empty(): submit_choice()
		elif state.game.activePlayer == 0 and state.game.phase == "Main 1" and kind == "InputPassPriority" and state.game.turn > after_turn:
			return true
		elif kind == "InputConfirmMulligan":
			if not has_setup() and not redraw_used:
				redraw_used = true
				ui.opening_hand.submit("cancel")
			else: ui.opening_hand.submit("ok")
		elif kind == "InputLondonMulligan":
			if state.prompt.okEnabled: ui._intent("ok")
			else: ui.opening_hand.card_chosen.emit(choose_extra(zone("Hand")))
		elif kind == "InputSelectCardsFromList":
			if state.prompt.okEnabled: ui._intent("ok")
			else: ui._intent("card", {"id": choose_extra(state.prompt.cards)})
		elif StartingPlayerDialog.needs_selection(state): ui._choose_player(0)
		elif state.prompt.okEnabled: ui._primary_action()
	return check(false, "Cannot reach main phase for colorless payment fixture")

func await_permanent(id: int) -> bool:
	for step in range(40):
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty(): submit_choice()
		elif zone("Battlefield").any(func(card): return int(card.id) == id): return true
		elif not ui.snapshot.stack.is_empty() and int(ui.snapshot.stack[0].get("sourceId", -1)) != id and int(ui.snapshot.get("autoPassStackId", -1)) < 0 and ui.snapshot.prompt.get("okEnabled", false):
			# Other players' Ancients can trigger above this cast; acknowledge those
			# effects without manually confirming the permanent being tested.
			ui._primary_action()
		await ui.get_tree().create_timer(0.1).timeout
	return check(false, "Cast did not resolve automatically: " + str(ui.snapshot.prompt))

func run(table: Control) -> void:
	ui = table
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 1000)
	deadline = Time.get_ticks_msec() + 115000
	if not await ready_main(): return
	while not has_setup():
		if not await ready_main(int(ui.snapshot.game.turn)): return
	var plains: Dictionary = find_card("Plains")
	var forest: Dictionary = find_card("Forest")
	var ring: Dictionary = find_card("Sol Ring")
	var ancient: Dictionary = find_card("Forgotten Ancient")
	ui._click_card(plains.id)
	if not await wait_ready(): return
	ui._click_card(plains.id)
	if not await wait_ready(): return
	var passes_before: int = ui.adapter.auto_priority_passes
	ui.adapter.state_changed.connect(func(state):
		if state.get("stack", []).any(func(item): return int(item.get("sourceId", -1)) == int(ring.id)):
			saw_ring_on_stack = true
			check(ui.cards.has(ring.id) and ui.cards[ring.id].visible and ui.cards[ring.id].data.zone == "Stack", "A clicked Sol Ring must remain visible on the board while casting"))
	ui._click_card(ring.id)
	if not await await_permanent(int(ring.id)): return
	if not check(saw_ring_on_stack and ui.adapter.auto_priority_passes > passes_before, "Sol Ring must resolve without Continue and retain its pending card"): return
	if not await ready_main(int(ui.snapshot.game.turn)): return
	ui._click_card(forest.id)
	if not await wait_ready(): return
	for id in [plains.id, ring.id, forest.id]:
		ui._click_card(id)
		if not await wait_ready(): return
	var pool: Dictionary = ui.snapshot.players[0].mana
	if not check(pool.size() == 3 and int(pool.get("W", 0)) == 1 and int(pool.get("G", 0)) == 1 and int(pool.get("C", 0)) == 2, "Fixture must reproduce exactly the reported W/G/C/C floating pool: " + str(pool)): return
	var center: Vector2 = ui.cards[ancient.id].get_global_rect().get_center()
	ui._drag_card(ancient.id, ui.player_areas[0].get_global_rect().get_center() - center)
	if not await await_permanent(int(ancient.id)): return
	if not check(ui.snapshot.players[0].mana.is_empty() and [plains.id, ring.id, forest.id].all(func(id): return ui.cards[id].data.tapped), "Forgotten Ancient must spend W/G/C/C and leave every source tapped"): return
	print("PASS: Godot live integration (Sol Ring click remains visible and resolves without Continue; Forgotten Ancient paid with W/G/C/C)")
	ui.get_tree().quit()
