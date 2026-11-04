extends RefCounted
const ManaPaymentDialog = preload("res://scripts/ui/ManaPaymentPanel.gd")

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
	state.asks = []
	state.pendingCastId = -1
	state.pendingDraws = []
	state.connectionReady = true
	state.players[0].mana = {"W": 1, "B": 2, "C": 1}
	state.prompt = {"inputKind": "InputPayManaOfCostPayment", "cardId": 1, "message": "Pay mana cost {2}", "cancelEnabled": true, "okEnabled": true}
	ui._apply_state(state)
	var panel: Control = ui.modal_panel
	assert(ui.modal.visible and panel is ManaPaymentDialog and ui.open_ask == -2, "Activation mana payment must open a required popup")
	assert(panel.mana_buttons.keys() == ["W", "B", "C"] and panel.mana_buttons.B.text.contains("2"), "Offer only pool colors with authoritative counts")
	if DisplayServer.get_name() != "headless":
		await ui._save_frame("res://artifacts/mana-payment.png")
	ui._dismiss_modal()
	assert(ui.modal.visible, "Outside/Escape dismissal cannot cancel a mana payment")
	var selected: Array = []
	panel.mana_selected.connect(func(code): selected.append(code))
	panel.mana_buttons.B.pressed.emit()
	assert(selected == [4] and panel.mana_buttons.W.disabled and panel.cancel_button.disabled, "Chosen black mana must emit Forge's black code and disable duplicate submissions")
	state.connectionReady = false
	ui._apply_state(state)
	assert(ui.modal_panel.mana_buttons.B.disabled, "Pending or disconnected payment must stay disabled")
	state.connectionReady = true
	state.players[0].mana.B = 1
	state.prompt.message = "Pay mana cost {1}"
	ui._apply_state(state)
	assert(ui.modal.visible and ui.modal_panel.mana_buttons.B.text.contains("1"), "Partial payment must refresh the remaining pool and cost")
	ui.modal_panel.sources_requested.emit()
	ui._apply_state(state)
	assert(not ui.modal.visible, "Choosing battlefield sources must allow manual mana generation without canceling")
	state.players[0].mana.U = 1
	ui._apply_state(state)
	assert(ui.modal.visible and ui.modal_panel.mana_buttons.has("U"), "New mana must reopen the pool chooser")
	state.players[0].mana = {}
	ui._apply_state(state)
	assert(ui.modal.visible and ui.modal_panel.mana_buttons.is_empty() and not ui.modal_panel.sources_button.disabled, "An empty pool must offer battlefield mana sources and cancellation")
	state.prompt.inputKind = "InputPassPriority"
	ui._apply_state(state)
	assert(not ui.modal.visible, "Engine completion must close the mana popup")
	state.prompt.inputKind = "InputPayManaOfCostPayment"
	state.pendingCastId = 1
	ui._apply_state(state)
	assert(not ui.modal.visible, "Automatic spell payment must retain its existing flow")
	ui._close_modal()
	ui.live = was_live
	if saved_cancel == null:
		ui.cancel_button.queue_free()
		ui.cancel_button = saved_cancel
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	print("PASS: activation mana popup, pool choices, partial payment, readiness, source selection and completion")
