extends RefCounted

class RecordingAdapter extends RefCounted:
	var effects: Array = []
	var intents: Array = []
	func acknowledge_effect(id: int) -> void: effects.append(id)
	func send_intent(intent: Dictionary) -> void: intents.append(intent)

func run(ui: Control) -> void:
	var toast_color: Color = ui.toast.modulate
	var modal_visible: bool = ui.modal.visible
	ui.set_transition_preview(true)
	assert(ui.modal.visible == modal_visible and is_zero_approx(ui.modal.modulate.a) and is_zero_approx(ui.opening_hand.modulate.a), "Cinematic mask must not change decision visibility/state")
	assert(is_equal_approx(ui.table_backdrop.cinematic_tint, 1.0), "Cinematic grid starts teal")
	for layer in ui.get_children():
		if layer is CanvasItem and layer != ui.table_backdrop and layer != ui.toast:
			assert(is_zero_approx(layer.modulate.a), "All foreground roots must be masked during the grid reveal")
	ui.toast.modulate.a = 0.0
	ui.set_transition_preview(false)
	assert(is_zero_approx(ui.table_backdrop.cinematic_tint), "Normal table uses its gray grid")
	assert(is_zero_approx(ui.toast.modulate.a), "Finishing a preview must not resurrect an expired toast")
	ui.toast.modulate = toast_color
	var face = preload("res://scripts/ui/CardFace.gd")
	assert(face.counter_label("P1P1") == "+1/+1" and face.counter_label("M1M1") == "-1/-1", "Counter badges use printed rules notation")
	assert(face.counter_label("P2P2") == "+2/+2", "Other power/toughness counters retain both signs")
	var pager := preload("res://scripts/ui/PagedChoices.gd").new()
	ui.add_child(pager)
	pager.configure(3, 3)
	for index in range(8):
		var option := Button.new()
		option.text = "Choice %d" % index
		pager.grid.add_child(option)
	pager.refresh()
	assert(pager.grid.get_children().filter(func(option): return option.visible).size() == 3, "Only a readable page of options is shown")
	pager.next.pressed.emit()
	assert(pager.page == 1 and pager.grid.get_child(3).visible and not pager.grid.get_child(0).visible, "All choices remain reachable on later pages")
	pager.queue_free()
	var readable := preload("res://scripts/ui/ReadableText.gd").new()
	ui.add_child(readable)
	var long_message := "One line of rules.\n".repeat(40)
	readable.present(long_message, 480, 100, 15)
	assert(readable.label.text == long_message.strip_edges(), "Scrolling rules preserve all nonblank content without splitting sentences")
	assert(readable.scroll.custom_minimum_size.y == 100, "Long rules remain inside the text budget")
	assert(readable.compact_text("First\r\n\r\n\r\n  Second\n\n\nThird") == "First\n\nSecond\n\nThird", "Forge spacer lines collapse to one paragraph break")
	readable.queue_free()
	var board_choice := preload("res://scripts/ui/BoardChoice.gd").new()
	ui.add_child(board_choice)
	var ask := {"id": 991, "title": "Proliferate", "min": 0, "max": 3, "localPlayerId": 17, "options": [{"cardId": 101, "controllerId": 17}, {"cardId": 102, "controllerId": 18}, {"playerId": 17}]}
	var submitted: Array = []
	board_choice.answered.connect(func(id, indices): submitted.append([id, indices]))
	board_choice.present(ask, {}, true)
	board_choice.mine_button.pressed.emit()
	assert(board_choice.chosen == [0], "Mine selects eligible local permanents, excluding players and opponents")
	board_choice.select_entity("card", 102)
	board_choice.select_entity("player", 17)
	board_choice.present(ask, {}, true)
	assert(board_choice.chosen.size() == 3 and submitted.is_empty(), "Board selections survive snapshots without submitting prematurely")
	board_choice.confirm_button.pressed.emit()
	assert(submitted == [[991, [0, 1, 2]]], "One final confirmation sends the original callback ID and option indices")
	board_choice.present(ask, {}, false)
	board_choice.select_entity("card", 101)
	assert(board_choice.chosen.size() == 3 and board_choice.confirm_button.disabled, "Disconnected board choices cannot change or submit")
	board_choice.queue_free()
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var fixture: Dictionary = saved.duplicate(true)
	var commander: Dictionary = fixture.players[0].zones.Hand.pop_front()
	fixture.players[0].zones.Command = [commander]
	ui._apply_state(fixture)
	ui._show_zone(0, "Command")
	ui.pending_command_cast = int(commander.id)
	ui.snapshot.pendingCastId = int(commander.id)
	ui.snapshot.prompt.inputKind = "InputPassPriority"
	ui._close_accepted_commander_browser()
	assert(ui.zone_owner == 0, "An optimistic client preview must not close a rejected commander play")
	ui.snapshot.prompt.inputKind = "InputPayManaOfCostPayment"
	ui._close_accepted_commander_browser()
	assert(ui.zone_owner == -1 and not ui.zone_panel.visible, "Accepted commander payment closes the browser")
	ui._show_zone(0, "Command")
	ui.pending_command_cast = int(commander.id)
	ui.snapshot.players[0].zones.Command = []
	ui._close_accepted_commander_browser()
	assert(ui.zone_owner == -1, "A commander leaving its zone also closes the browser")
	ui._apply_state(saved)
	var attacker: int = saved.players[0].zones.Battlefield[0].id
	var blocker: int = saved.players[1].zones.Battlefield[0].id
	ui.snapshot.combat = [{"attacker": attacker, "defenderId": 1, "blockers": [blocker]}]
	ui.targeting = false
	ui._update_lines()
	assert(ui.targeting_overlay.lines.size() == 1, "A block replaces the attack-to-player arrow")
	assert(not ui.targeting_overlay.is_processing(), "Fixed combat arrows retain their drawing without rebuilding every frame")
	var line: Array = ui.targeting_overlay.lines[0]
	assert(line[0] == ui.cards[attacker].get_global_transform() * (ui.cards[attacker].size * 0.5) and line[1] == ui.cards[blocker].get_global_transform() * (ui.cards[blocker].size * 0.5), "Blocked attack points to its specific blocker")
	ui.snapshot.combat[0].blockers = []
	ui._update_lines()
	assert(ui.targeting_overlay.lines[0][1] == ui.hud_values[1].portrait.get_global_rect().get_center(), "Removing the block restores the player target")
	ui.snapshot.combat[0].blocked = true
	ui._update_lines()
	assert(ui.targeting_overlay.lines.is_empty(), "Losing a declared blocker must not imply damage to the defending player")
	ui.snapshot.combat[0].trample = true
	ui._update_lines()
	assert(ui.targeting_overlay.lines.size() == 1, "A blocked trampler can still threaten the defending player")
	var fixed_lines: Array = ui.targeting_overlay.lines.duplicate(true)
	ui.targeting_overlay.lines = [[Vector2(10, 20), Vector2.INF]]
	assert(ui.targeting_overlay.is_processing(), "A targeting arrow still follows the pointer every frame")
	ui.targeting_overlay.lines = []
	assert(not ui.targeting_overlay.is_processing(), "Clearing targeting stops its idle pointer polling")
	ui.targeting_overlay.lines = fixed_lines
	ui.snapshot.revealed = [commander]
	ui._show_revealed()
	assert(ui.modal.visible and ui.modal_panel.ask.options[0].card.id == commander.id, "Revealed-card browsing must render actual card faces")
	ui.modal_panel._submit()
	assert(not ui.modal.visible, "Revealed-card browsing closes locally")
	var original_adapter = ui.adapter
	var original_live: bool = ui.live
	var recording := RecordingAdapter.new()
	ui.adapter = recording
	ui.live = true
	var event := {"id": 8100, "stackId": 8200, "source": commander, "targets": [], "effectText": "Destroy target creature."}
	fixture = saved.duplicate(true)
	fixture.connectionReady = true
	fixture.asks = []
	fixture.stack = [{"id": 8200, "card": commander}]
	fixture.prompt = {"inputKind": "InputPassPriority", "okEnabled": true}
	fixture.targetedEffects = [event]
	ui.snapshot = fixture
	ui.incoming_effect.reset()
	ui.incoming_effect.present(fixture)
	assert(ui.incoming_effect.panel.visible)
	ui._intent("ok")
	ui.incoming_effect.present(fixture)
	assert(ui.incoming_effect.active.is_empty() and not ui.incoming_effect.panel.visible and recording.effects == [8200], "Rail OK dismisses its notice once and acknowledges that exact stack item")
	ui.incoming_effect.reset()
	fixture.prompt.inputKind = "InputSelectTargets"
	ui.incoming_effect.present(fixture)
	ui._intent("ok")
	assert(not ui.incoming_effect.active.is_empty() and recording.intents.back().action == "ok", "Required target decisions keep their own interaction lifecycle")
	ui.live = original_live
	ui.adapter = original_adapter
	recording = null
	ui.incoming_effect.reset()
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	print("PASS: commander browser acceptance, stack OK dismissal, required decisions and blocker arrow redirection")
