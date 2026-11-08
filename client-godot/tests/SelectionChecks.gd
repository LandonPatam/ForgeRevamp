extends RefCounted

func run(ui: Control, directory: String = "") -> void:
	var panel = preload("res://scripts/ui/SelectionPanel.gd").new()
	ui.add_child(panel)
	var state := {"connectionReady": true, "prompt": {"message": "Return a land", "cards": [{"id": 41, "name": "Island"}, {"id": 42, "hidden": true}], "selMin": 1, "selMax": 1, "chosen": [], "okEnabled": false}}
	panel.present(state)
	if not directory.is_empty():
		panel.position = Vector2(290, 180)
		panel.z_index = 110
		await ui._save_frame(directory.path_join("engine-card-selection.png"))
	assert(panel.confirm_button.disabled and not panel.none_button.visible)
	var gallery: Dictionary = state.duplicate(true)
	gallery.prompt.cards = []
	for index in range(18): gallery.prompt.cards.append({"id": 4000 + index, "name": "Atraxa, Praetors' Voice"})
	panel.present(gallery)
	panel.option_buttons[0].mouse_entered.emit()
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	assert(is_equal_approx(panel.preview.size.y, panel.PREVIEW_SIZE.y) and is_equal_approx(panel.preview.size.x / panel.preview.size.y, 144.0 / 202), "A long result list must not stretch the card preview: " + str(panel.preview.size))
	if not directory.is_empty():
		panel.position = Vector2(16, 16)
		await ui._save_frame(directory.path_join("selection-preview-proportions-1600.png"))
		ui.capture_size = Vector2i(1280, 800)
		ui.get_window().size = ui.capture_size
		await ui.get_tree().create_timer(0.2).timeout
		panel.present(gallery)
		panel.reset_size()
		await ui.get_tree().process_frame
		await ui.get_tree().process_frame
		await ui._save_frame(directory.path_join("selection-preview-proportions-1280.png"))
		assert(panel.get_global_rect().end.x <= 1280 and is_equal_approx(panel.preview.size.y, panel.PREVIEW_SIZE.y), "Popup previews and their gallery must fit the narrower screen without squeezing")
		ui.capture_size = Vector2i(1600, 1000)
		ui.get_window().size = ui.capture_size
		await ui.get_tree().create_timer(0.2).timeout
	panel.present(state)
	var picked: Array = []
	panel.selected_card.connect(func(id): picked.append(id))
	panel.option_buttons[0].pressed.emit()
	assert(picked == [41], "Selections must route the real engine card ID")
	state.prompt.chosen = ["card:41"]
	state.prompt.okEnabled = true
	panel.present(state)
	assert(not panel.confirm_button.disabled and panel.option_buttons[0].text.begins_with("✓"))
	state.connectionReady = false
	panel.present(state)
	assert(panel.confirm_button.disabled and panel.option_buttons[0].disabled)
	state.connectionReady = true
	state.prompt.selMin = 0
	state.prompt.chosen = []
	panel.present(state)
	assert(panel.none_button.visible and not panel.none_button.disabled and panel.confirm_button.disabled, "Empty optional selections require an explicit Choose none")
	state.prompt.inputKind = "InputSelectEntitiesFromList"
	state.prompt.selMin = 1
	state.prompt.okEnabled = false
	state.prompt.cancelEnabled = true
	var skipped: Array = []
	panel.action_requested.connect(func(action): skipped.append(action))
	panel.present(state)
	assert(panel.none_button.visible and not panel.none_button.disabled, "Optional one-card native choices expose Forge's decline even with minimum 1")
	panel.none_button.pressed.emit()
	assert(skipped == ["cancel"], "Declining an optional native effect must send its authorized cancel action")
	assert(panel.option_buttons[1].text == "Face-down card" and panel.preview.data.name == "Island")
	state.prompt.inputKind = "InputSelectStackItems"
	state.prompt.message = "Choose a spell or ability to counter"
	state.prompt.cards = []
	state.prompt.entities = [{"kind": "stack", "id": 801, "sourceName": "Triggered ability", "text": "Draw a card, then put a counter on this permanent.", "card": {"id": 41, "name": "Fathom Mage"}}, {"kind": "stack", "id": 802, "sourceName": "Another trigger from the same card", "text": "Draw a card.", "card": {"id": 41, "name": "Fathom Mage"}}]
	state.prompt.okEnabled = false
	state.prompt.cancelEnabled = true
	state.prompt.cancelLabel = "Cancel targeting"
	var entities: Array = []
	panel.entity_selected.connect(func(action, id): entities.append([action, id]))
	panel.present(state)
	panel.option_buttons[1].pressed.emit()
	assert(entities == [["stack", 802]], "Two abilities from one card must route distinct stack IDs")
	assert(panel.cancel_button.visible and panel.cancel_button.text == "Cancel targeting")
	state.prompt.chosen = ["card:41", "stack:802"]
	state.prompt.okEnabled = true
	panel.present(state)
	assert(panel.option_buttons[1].text.begins_with("✓") and not panel.option_buttons[0].text.begins_with("✓"))
	assert(panel.hint.text == "1 selected", "Earlier targeting stages must not inflate the current selection count")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("stack-target-gallery.png"))
	state.prompt.entities = [{"kind": "player", "id": 2, "engineId": 70, "name": "Opponent"}]
	state.prompt.inputKind = "InputSelectEntitiesFromList"
	state.prompt.chosen = ["player:70"]
	panel.present(state)
	panel.option_buttons[0].pressed.emit()
	assert(entities.back() == ["player", 2] and panel.option_buttons[0].text.begins_with("✓"), "Player selections must preserve engine references while sending local seat indices")
	state.prompt.cancelEnabled = true
	state.prompt.cancelLabel = "Mine"
	state.prompt.selectionShortcut = "MINE"
	panel.present(state)
	var native_actions: Array = []
	panel.action_requested.connect(func(action): native_actions.append(action))
	panel.cancel_button.pressed.emit()
	assert(panel.cancel_button.text == "Select my permanents" and native_actions == ["cancel"], "The native shortcut must use Forge's mass-selection action without confirming")
	panel.queue_free()
	var optional = preload("res://scripts/ui/PromptPanel.gd").new()
	ui.add_child(optional)
	optional.present({"id": 888, "kind": "choose", "min": 0, "max": 1, "options": [{"label": "Plains"}, {"label": "Island"}]})
	var answers: Array = []
	optional.answered.connect(func(_id, value): answers.append(value))
	optional._submit()
	assert(answers.is_empty(), "Repeated confirmation must not silently decline a library search")
	optional._toggle(1)
	optional._submit()
	assert(answers == [[1]])
	optional.present({"id": 889, "kind": "choose", "title": "Proliferate", "min": 0, "max": 6, "bulkSelection": true, "localPlayerId": 11, "options": [
		{"label": "Your creature", "cardId": 91, "controllerId": 11, "card": {"id": 91, "name": "Forgotten Ancient"}},
		{"label": "Opponent creature", "cardId": 92, "controllerId": 22, "card": {"id": 92, "name": "Opponent creature"}},
		{"label": "Your land", "cardId": 93, "controllerId": 11, "card": {"id": 93, "name": "Dreadship Reef"}},
		{"label": "Your planeswalker", "cardId": 94, "controllerId": 11, "card": {"id": 94, "name": "Your planeswalker"}},
		{"label": "You", "playerId": 11},
		{"label": "Opponent", "playerId": 22}
	]})
	optional.mine_button.pressed.emit()
	assert(optional.chosen == [0, 2, 3] and answers == [[1]], "Select mine must include all eligible permanent types, exclude players and opponents, and wait for confirmation")
	if not directory.is_empty():
		optional.position = Vector2(220, 100)
		optional.z_index = 110
		await ui._save_frame(directory.path_join("proliferate-select-mine.png"))
	optional._toggle(1)
	assert(optional.chosen == [0, 2, 3, 1], "The shortcut selection must remain editable")
	optional._submit()
	assert(answers.back() == [0, 2, 3, 1], "Confirm must preserve original engine option indices")
	optional.present({"id": 890, "kind": "choose", "title": "Choose mana", "abilityChoice": true, "manaChoice": true, "min": 0, "max": 1, "options": [{"label": "White — Add {W}."}, {"label": "Blue — Add {U}."}]})
	optional.option_buttons[1].pressed.emit()
	optional._submit()
	assert(answers.back() == [1] and answers.size() == 3 and not optional.confirm_button.visible, "A mana color click submits its exact index once without another confirmation")
	optional.queue_free()
	await ui.get_tree().process_frame
	print("PASS: authoritative card selections, readiness, hidden faces and explicit empty choices")
