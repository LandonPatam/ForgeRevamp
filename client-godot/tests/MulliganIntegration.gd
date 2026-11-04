extends "res://tests/LiveIntegration.gd"

func run(table: Control) -> void:
	ui = table
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 1000)
	deadline = Time.get_ticks_msec() + 110000
	var redraws := 0
	var kept := false
	var bottom_confirmed := false
	var bottom_ids: Array[int] = []
	var previous_hand: Array = []
	var library_before_keep := 0
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return
		if not ui.snapshot.asks.is_empty():
			submit_choice()
			continue
		var state: Dictionary = ui.snapshot
		var kind: String = state.prompt.get("inputKind", "")
		var hand: Array = state.players[0].zones.Hand
		print("Mulligan flow: ", kind, " hand=", hand.size(), " redraws=", redraws, " kept=", kept)
		if kind == "InputConfirmMulligan":
			var owed := maxi(0, redraws - 1)
			if not check(state.prompt.get("mulliganReturnCount", -1) == owed and ui.opening_hand.hint.visible, "Keep/Mulligan must show the engine's upcoming return count before committing"): return
			if owed > 0 and not check(ui.opening_hand.hint.text.contains(str(owed)), "The upcoming card count must appear in the opening-hand banner"): return
			if not check(not kept and not bottom_confirmed, "Keep must commit the hand; no further mulligan prompt may follow bottoming"): return
			if not check(hand.size() == 7, "Every replacement must offer all seven cards before Keep"): return
			var ids: Array = hand.map(func(card): return card.id)
			if not previous_hand.is_empty() and not check(ids != previous_hand, "Mulligan must deal a replacement hand"): return
			previous_hand = ids
			if redraws < 3:
				ui.opening_hand.submit("cancel")
				redraws += 1
			else:
				kept = true
				library_before_keep = state.players[0].libraryCount
				bottom_ids.assign([hand[0].id, hand[1].id])
				ui.opening_hand.submit("ok")
		elif kind == "InputLondonMulligan":
			if not check(kept and redraws == 3 and not bottom_confirmed, "Bottom selection must happen only after Keep, once for the final hand"): return
			if not check(hand.size() == 7, "Final hand must remain complete during bottom selection"): return
			var selected: Array = state.prompt.get("chosen", [])
			if selected.is_empty():
				if not check(not state.prompt.okEnabled, "Three multiplayer mulligans owe two cards after the free first mulligan"): return
				ui.opening_hand.card_chosen.emit(bottom_ids[0])
			elif selected.size() == 1:
				if not check(not state.prompt.okEnabled, "One selected card must not satisfy a two-card penalty"): return
				ui.opening_hand.card_chosen.emit(bottom_ids[1])
			else:
				if not check(selected.size() == 2 and state.prompt.okEnabled, "Exactly two cards must enable final confirmation"): return
				bottom_confirmed = true
				ui.opening_hand.submit("ok")
		elif kept and bottom_confirmed and kind == "InputPassPriority":
			if not check(hand.all(func(card): return not bottom_ids.has(card.id)), "Selected cards must leave the kept hand"): return
			if not check(hand.size() == 5 + manual_draws and state.players[0].libraryCount == library_before_keep + 2 - manual_draws, "Final hand and library counts must reflect exactly two returned cards and subsequent draws"): return
			print("PASS: Godot live integration (three full replacement hands, free first mulligan, no bottoming before Keep, exactly two final selections, then game start without another mulligan)")
			ui.get_tree().quit()
			return
		elif StartingPlayerDialog.needs_selection(state):
			ui.modal_panel.buttons[0].pressed.emit()
		elif state.prompt.okEnabled:
			ui._primary_action()
	check(false, "Mulligan flow did not reach gameplay")
