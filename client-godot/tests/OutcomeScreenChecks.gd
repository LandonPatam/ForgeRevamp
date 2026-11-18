extends RefCounted

## YOU LOSE / YOU WIN: falling ASCII letters, then exactly one button; I lost keeps the table open.
func run(ui: Control, directory: String = "") -> void:
	for won in [false, true]:
		ui._show_outcome_screen(won, {} if won else {"reason": "commanderDamage", "sources": [{"name": "Kalemne, Disciple of Iroas", "amount": 24}]})
		var screen: Control = ui.outcome_screen
		assert(screen != null and screen.visible and screen.mouse_filter == Control.MOUSE_FILTER_STOP, "The result screen covers the table until acknowledged")
		assert(not screen.button.visible, "The button waits for the letters to land")
		assert(screen.cells.size() > 60, "The message is built from many falling characters")
		assert(won or (screen.status.contains("COMMANDER DAMAGE") and screen.status.contains("KALEMNE") and screen.status.contains("24")), "A loss names its cause: " + screen.status)
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		screen.handle_key(enter)
		assert(is_instance_valid(ui.outcome_screen), "Enter cannot skip the result before the button appears")
		for i in range(int((screen.settle_time + 0.5) / 0.05) + 2): screen._process(0.05)
		assert(screen.button.visible and screen.button.text == ("I WON" if won else "I lost"), "One button: I WON / I lost")
		assert(screen.get_children().filter(func(child): return child is Button).size() == 1)
		if not directory.is_empty():
			screen.clock = 0.0
			screen.button.hide()
			await ui.get_tree().create_timer(screen.settle_time + 1.4).timeout
			await ui._save_frame(directory.path_join("outcome-%s.png" % ("win" if won else "lose")))
		if won:
			# I WON hands off to the app's victory wipe; without an app host it just closes.
			screen.queue_free()
			ui.outcome_screen = null
			continue
		screen.button.pressed.emit()
		await ui.get_tree().process_frame
		assert(not is_instance_valid(ui.outcome_screen), "I lost closes the screen so the player can keep spectating")
	# Each Forge loss reason reads as a cause; without one the screen keeps its plain status.
	const Outcome = preload("res://scripts/ui/OutcomeScreen.gd")
	assert(Outcome.loss_cause({"reason": "life", "sources": [{"name": "Inferno Titan", "amount": 6}, {"name": "Stoneshock Giant", "amount": 8}]}).contains("INFERNO TITAN (6), STONESHOCK GIANT (8)"), "Life loss names the final hit")
	assert(Outcome.loss_cause({"reason": "life", "sources": [], "card": "Exsanguinate"}).contains("EXSANGUINATE"), "Life loss without damage names the effect")
	assert(Outcome.loss_cause({"reason": "poison", "amount": 10}).contains("10 POISON"), "Poison")
	assert(Outcome.loss_cause({"reason": "effect", "card": "Door to Nothingness"}).contains("DOOR TO NOTHINGNESS"), "A card that makes you lose")
	assert(Outcome.loss_cause({}).is_empty(), "No reason, no cause line")
	print("PASS: outcome screen ASCII message, loss cause, single acknowledgment button and spectating after a loss")
