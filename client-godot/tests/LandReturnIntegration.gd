extends "res://tests/DecisionIntegration.gd"
const ManaPaymentDialog = preload("res://scripts/ui/ManaPaymentPanel.gd")

func run(table: Control) -> void:
	ui = table
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 1000)
	deadline = Time.get_ticks_msec() + 110000
	if not await advance_to_main(): return
	while find_card("Swamp").is_empty() or find_card("Darkwater Catacombs").is_empty():
		if not await advance_to_main(int(ui.snapshot.game.turn)): return
	var swamp: Dictionary = find_card("Swamp")
	var land: Dictionary = find_card("Darkwater Catacombs")
	ui._click_card(swamp.id)
	if not await wait_ready(): return
	if not await advance_to_main(int(ui.snapshot.game.turn)): return
	ui._click_card(land.id)
	if not await wait_ready(): return
	if not check(ui.cards[land.id].data.availableActions.returnToHand, "New Darkwater Catacombs must be returnable"): return
	# An unpaid activation canceled in its cost prompt must preserve permission.
	ui._click_card(land.id)
	if not await wait_ready(): return
	if ui.snapshot.prompt.get("inputKind", "").begins_with("InputPayMana"):
		ui._intent("cancel")
		if not await wait_ready(): return
	if not check(not ui.cards[land.id].data.tapped and ui.cards[land.id].data.availableActions.returnToHand, "Canceling Darkwater's activation must preserve its unused land return"): return
	ui._intent("return_to_hand", {"id": land.id})
	if not await wait_ready(): return
	# Float the cost before playing Darkwater, then undo its paid activation.
	ui._click_card(swamp.id)
	if not await wait_ready(): return
	ui._click_card(land.id)
	if not await wait_ready(): return
	ui._click_card(land.id)
	if not await wait_ready(): return
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputPayManaOfCostPayment" and ui.modal.visible and ui.modal_panel is ManaPaymentDialog, "Darkwater must ask which floating mana to spend"): return
	if not check(ui.modal_panel.mana_buttons.keys() == ["B"] and ui.snapshot.players[0].mana.get("B", 0) == 1, "Only the available black mana must be offered, without automatically spending it"): return
	ui.modal_panel.mana_buttons.B.pressed.emit()
	if not await wait_ready(): return
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority" and not ui.modal.visible, "Choosing black mana must complete activation and close the popup"): return
	if not check(ui.cards[land.id].data.tapped and ui.snapshot.players[0].mana.get("U", 0) == 1 and ui.snapshot.players[0].mana.get("B", 0) == 1, "Darkwater must produce blue and black mana"): return
	if not check(not ui.cards[land.id].data.availableActions.returnToHand and ui.cards[land.id].data.availableActions.undoTap, "Active mana must block land return and permit activation undo"): return
	ui._click_card(land.id)
	if not await wait_ready(): return
	if not check(not ui.cards[land.id].data.tapped and ui.snapshot.players[0].mana.get("B", 0) == 1 and ui.snapshot.players[0].mana.get("U", 0) == 0, "Undo must restore Darkwater's complete activation cost and output"): return
	if not check(ui.cards[land.id].data.availableActions.returnToHand, "Undoing the mana tap must restore Darkwater's return permission in M1"): return
	var hand_target: Vector2 = ui.hand_root.global_position + Vector2(ui.hand_root.size.x * 0.5, 100)
	ui._drag_card(land.id, hand_target - ui.cards[land.id].get_global_rect().get_center())
	if not await wait_ready(): return
	if not check(zone("Hand").any(func(card): return card.id == land.id) and ui.cards[swamp.id].data.tapped and ui.snapshot.players[0].mana.get("B", 0) == 1, "Dragging Darkwater back must preserve the earlier Swamp tap and floating mana"): return
	ui._click_card(land.id)
	if not await wait_ready(): return
	if not check(ui.cards[land.id].data.zone == "Battlefield", "Returning the land must restore its land-play allowance"): return
	if not await advance_to_main(int(ui.snapshot.game.turn)): return
	if not check(not ui.cards[land.id].data.availableActions.returnToHand, "A later phase/turn must revoke return permission"): return
	print("PASS: Godot live integration (Darkwater canceled activation, paid activation undo, restored land return, drag to hand, land allowance and phase barrier)")
	ui.get_tree().quit()
