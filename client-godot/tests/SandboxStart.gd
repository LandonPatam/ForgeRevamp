extends RefCounted
## UI sandbox (tools/sandbox.mjs, --sandbox): clicks through the real startup (notices, Keep,
## starting player) so the table opens on the prepared board, then hands every decision to the
## person at the keyboard. It answers nothing once the prepared board has priority.

const StartingPlayerDialog = preload("res://scripts/ui/StartingPlayerPanel.gd")
const LIMIT_MS := 60000

func run(ui: Control) -> void:
	ui.sandbox_starting = true
	var deadline := Time.get_ticks_msec() + LIMIT_MS
	while Time.get_ticks_msec() < deadline:
		await ui.get_tree().create_timer(0.15).timeout
		var state: Dictionary = ui.snapshot
		if state.is_empty() or not state.get("connectionReady", false):
			continue
		var game: Dictionary = state.get("game", {})
		var prompt: Dictionary = state.get("prompt", {})
		var asks: Array = state.get("asks", [])
		if not game.get("mulligan", false) and str(prompt.get("message", "")).contains("Priority:") and asks.is_empty():
			break
		if not asks.is_empty():
			if asks[0].get("kind", "") == "message" and is_instance_valid(ui.modal_panel) and ui.modal_panel.has_method("_submit"):
				ui.modal_panel._submit()
				await ui.get_tree().create_timer(0.3).timeout
				continue
			break # A real decision on the prepared board: leave it to the player.
		var kind: String = prompt.get("inputKind", "")
		if kind == "InputConfirmMulligan":
			ui.opening_hand.submit("ok")
		elif kind == "InputLondonMulligan":
			break
		elif StartingPlayerDialog.needs_selection(state):
			if ui.modal.visible and ui.modal_panel is StartingPlayerDialog and not ui.modal_panel.buttons.is_empty():
				ui.modal_panel.buttons[0].pressed.emit()
		elif prompt.get("okEnabled", false):
			ui._primary_action()
		else:
			continue
		await ui.get_tree().create_timer(0.4).timeout
	ui.sandbox_starting = false
	print("Sandbox board ready: turn %s, %s" % [ui.snapshot.get("game", {}).get("turn", "?"), ui.snapshot.get("game", {}).get("phase", "?")])
