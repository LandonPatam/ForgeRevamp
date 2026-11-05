extends RefCounted
const Attention = preload("res://scripts/ui/StackAttention.gd")

func run(ui: Control, directory: String = "") -> void:
	var state := {"stack": [{"id": 1}], "connectionReady": true, "asks": [], "game": {}, "prompt": {"inputKind": "InputPassPriority", "okEnabled": true, "cancelEnabled": true}}
	assert(Attention.needs_choice(state), "A stack waiting on this player to resolve or respond must glow")
	state.autoPassStackId = 1
	assert(not Attention.needs_choice(state), "An item that passes automatically must not glow")
	state.autoPassStackId = -1
	state.prompt.okEnabled = false
	assert(not Attention.needs_choice(state), "Priority this player cannot act on must not glow")
	state.prompt.okEnabled = true
	for kind in ["InputSelectTargets", "InputSelectCardsFromList", "InputSelectStackItems", "InputPayMana", "InputPayManaOfCostPayment", "InputConfirm"]:
		state.prompt.inputKind = kind
		state.prompt.okEnabled = kind == "InputConfirm"
		assert(Attention.needs_choice(state), "Missing stack decision cue: " + kind)
	state.prompt = {"inputKind": "InputSelectTargets", "okEnabled": true, "chosen": ["player:1"]}
	assert(not Attention.needs_choice(state), "Completed targeting that only needs OK must stop flashing")
	state.prompt = {"inputKind": "InputConfirm", "okEnabled": true, "cancelEnabled": false}
	assert(not Attention.needs_choice(state), "OK-only confirmation must not flash")
	for kind in ["choose", "order", "distribute", "input"]:
		state.asks = [{"kind": kind}]
		assert(Attention.needs_choice(state), "Generic decision must flash: " + kind)
	state.asks = [{"kind": "message"}]
	assert(not Attention.needs_choice(state), "Acknowledge-only messages must not flash")
	state.asks = [{"kind": "choose"}]
	state.connectionReady = false
	assert(not Attention.needs_choice(state), "Pending/disconnected requests must stop flashing")
	state.connectionReady = true
	state.game.gameOver = true
	assert(not Attention.needs_choice(state))
	state.game.gameOver = false
	state.stack.clear()
	assert(not Attention.needs_choice(state), "An empty stack must never flash")
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var fixture: Dictionary = saved.duplicate(true)
	fixture.stack = [{"id": 9000, "sourceId": 10, "text": "Triggered ability — choose a player", "card": saved.players[0].zones.Hand[0].duplicate(true)}]
	fixture.prompt = {"inputKind": "InputSelectTargets", "okEnabled": false, "chosen": []}
	ui._apply_state(fixture)
	assert(ui.stack_attention.attention and ui.stack_attention.is_processing())
	assert(ui.stack_attention.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	if not directory.is_empty():
		ui.stack_attention.capture_phase = 0
		await ui._save_frame(directory.path_join("stack-decision-dim-1600.png"))
		ui.stack_attention.capture_phase = 1
		await ui._save_frame(directory.path_join("stack-decision-bright-1600.png"))
	fixture.asks = [{"id": 9000, "kind": "choose", "title": "Choose a player", "message": "The ability needs your decision.", "min": 1, "max": 1, "options": [{"label": "Mira"}, {"label": "Thorne"}]}]
	ui._apply_state(fixture)
	assert(ui.modal.visible and ui.stack_attention.attention and ui.stack_attention.z_index > ui.modal.z_index)
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("stack-decision-dialog-1600.png"))
	ui.stack_attention.capture_phase = -1
	ui._apply_state(saved)
	assert(not ui.stack_attention.attention and not ui.stack_attention.is_processing() and not ui.modal.visible)
	await ui.get_tree().process_frame
	print("PASS: stack decision pulse, resolve-window glow, automatic/OK-only exclusions, completed choices, dialogs and lifecycle")
