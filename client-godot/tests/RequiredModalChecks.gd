extends RefCounted

func run(ui: Control) -> void:
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var was_live: bool = ui.live
	var saved_cancel: Button = ui.cancel_button
	if saved_cancel == null:
		ui.cancel_button = Button.new()
		ui.add_child(ui.cancel_button)
		ui.cancel_button.hide()
	ui.live = true
	var state: Dictionary = saved.duplicate(true)
	state.connectionReady = true
	state.asks = []
	state.pendingDraws = []
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(2, 2)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	# Discarding from your own hand is picked on the hand: no gallery, the table dims, the prompt confirms.
	state.prompt = {"inputKind": "InputSelectCardsFromList", "message": "Discard one card", "cards": saved.players[0].zones.Hand.slice(0, 2), "selMin": 1, "selMax": 1, "chosen": [], "okEnabled": false, "cancelEnabled": false}
	ui._apply_state(state)
	assert(not ui.modal.visible and ui.hand_pick_panel.visible and ui.hand_pick_shade.visible and ui.hand_pick_confirm.disabled, "A hand-only discard must be picked on the dimmed table's hand")
	ui.hand_pick_shade.gui_input.emit(outside)
	ui._unhandled_key_input(escape)
	assert(ui.hand_pick_panel.visible, "Outside clicks and Escape must not dismiss a required discard")
	state.prompt.chosen = ["card:" + str(state.prompt.cards[0].id)]
	state.prompt.okEnabled = true
	ui._apply_state(state)
	assert(not ui.hand_pick_confirm.disabled and int(ui.cards[int(state.prompt.cards[0].id)].data.get("pickMark", 0)) == 2, "A picked hand card must be marked for discard and the prompt completable")
	state.prompt.inputKind = "InputPassPriority"
	state.prompt.cards = []
	state.prompt.chosen = []
	ui._apply_state(state)
	assert(not ui.hand_pick_panel.visible and not ui.hand_pick_shade.visible, "Engine completion must restore the table")
	# A selection that includes cards outside the hand keeps the required gallery.
	var elsewhere: Dictionary = saved.players[0].zones.Hand[0].duplicate(true)
	elsewhere.id = 990001
	state.prompt = {"inputKind": "InputSelectCardsFromList", "message": "Choose a card", "cards": [elsewhere, saved.players[0].zones.Hand[1]], "selMin": 1, "selMax": 1, "chosen": [], "okEnabled": false}
	ui._apply_state(state)
	var panel: Control = ui.modal_panel
	assert(ui.modal.visible and ui.open_ask == -2 and panel.confirm_button.disabled and not ui.hand_pick_panel.visible)
	ui.modal.get_child(0).gui_input.emit(outside)
	assert(ui.modal.visible and ui.modal_panel == panel and ui.open_ask == -2, "Outside clicks must not dismiss required selections")
	ui._unhandled_key_input(escape)
	assert(ui.modal.visible and ui.modal_panel == panel, "Escape must not hide a required selection")
	ui.modal.hide() # Simulate an older client's dismissed prompt/recovery snapshot.
	ui._apply_state(state)
	assert(ui.modal.visible and ui.modal_panel == panel, "An authoritative pending selection must restore a hidden dialog")
	state.prompt.chosen = ["card:" + str(state.prompt.cards[0].id)]
	state.prompt.okEnabled = true
	ui._apply_state(state)
	assert(not panel.confirm_button.disabled, "The protected selection must remain completable")
	state.prompt.inputKind = "InputPassPriority"
	state.prompt.cards = []
	ui._apply_state(state)
	assert(not ui.modal.visible, "Engine completion must close the required selection")
	state.asks = [{"id": 99101, "kind": "choose", "title": "Required choice", "message": "Choose one", "min": 1, "max": 1, "options": [{"label": "First"}, {"label": "Second"}]}]
	ui._apply_state(state)
	ui.modal.get_child(0).gui_input.emit(outside)
	assert(ui.modal.visible and ui.open_ask == 99101, "Generic engine decisions must also block outside dismissal")
	ui.modal.hide()
	ui._apply_state(state)
	assert(ui.modal.visible and ui.open_ask == 99101, "A pending engine ask must reopen after a hidden-dialog snapshot")
	ui._close_modal()
	ui.live = was_live
	if saved_cancel == null:
		ui.cancel_button.queue_free()
		ui.cancel_button = saved_cancel
	ui._apply_state(saved)
	ui._information("Information", "This window is dismissible.")
	ui.modal.get_child(0).gui_input.emit(outside)
	assert(not ui.modal.visible, "Informational popups should still close on outside click")
	await ui.get_tree().process_frame
	print("PASS: required discard/decision dismissal guards, snapshot recovery and information dismissal")
