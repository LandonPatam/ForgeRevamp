extends RefCounted
const AbilityOption = preload("res://scripts/ui/AbilityOption.gd")

## A long list is searchable, ten to a page, with types on the table first; answers keep Forge's index.
func _check_type_list(ui: Control, directory: String) -> void:
	var names := ["Advisor", "Ally", "Angel", "Archer", "Assassin", "Bat", "Bear", "Beast", "Cat", "Cleric", "Dragon", "Druid", "Dwarf", "Elf", "Faerie", "Giant", "Goblin", "Human", "Knight", "Merfolk", "Soldier", "Spirit", "Vampire", "Wizard", "Zombie"]
	var original: Dictionary = ui.snapshot
	var state: Dictionary = ui.snapshot.duplicate(true)
	state.players[1].zones.Battlefield.append({"id": 9971, "name": "Goblin Guide", "typeLine": "Creature — Goblin Scout", "stats": "2/1"})
	state.players[1].zones.Battlefield.append({"id": 9973, "name": "Goblin Piker", "typeLine": "Creature — Goblin Warrior", "stats": "2/1"})
	state.players[1].zones.Graveyard.append({"id": 9972, "name": "Llanowar Elves", "typeLine": "Creature — Elf Druid", "stats": "1/1"})
	state.players[1].zones.Battlefield.append({"id": 9974, "name": "Hidden", "typeLine": "Creature — Zombie", "hidden": true})
	ui.snapshot = state
	var options: Array = names.map(func(name): return {"label": name})
	var source := {"id": 9970, "name": "Metallic Mimic", "typeLine": "Artifact Creature — Shapeshifter", "text": "As this creature enters, choose a creature type."}
	ui._open_decision({"id": 9980, "kind": "choose", "title": "Choose a creature type", "message": "Choose a creature type", "min": 1, "max": 1, "options": options, "sourceCard": source})
	var panel: Control = ui.modal_panel
	await ui.get_tree().process_frame
	assert(panel.list_menu and panel.list_pager.page_size == 10, "A long plain list shows ten to a page")
	assert(panel.list_pager.grid.get_children().filter(func(child): return child.visible).size() == 10, "Exactly ten rows show")
	var rows: Array = panel.list_pager.grid.get_children()
	assert(rows[0] == panel.option_buttons[names.find("Goblin")], "The most common type on the table comes first")
	assert(rows.find(panel.option_buttons[names.find("Elf")]) < rows.find(panel.option_buttons[names.find("Advisor")]), "Types on the table come before the rest")
	assert(str(panel.ask.options[names.find("Goblin")].label).contains("2 on the table"), "The list shows how many are on the table")
	assert(panel.ask.options[names.find("Zombie")].get("tableCount", 0) == 0, "Hidden cards never rank a type")
	assert(panel.source_view.get_global_rect().position.x < panel.search.get_global_rect().position.x, "The card sits left of the list")
	assert(panel.list_pager.get_global_rect().position.y > panel.search.get_global_rect().position.y, "The search sits above the list")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("creature-type-list.png"))
	panel.search.text_changed.emit("wiz")
	assert(panel.list_pager.matches().size() == 1, "Searching narrows the list")
	panel.search.text_submitted.emit("wiz")
	assert(panel.chosen == [names.find("Wizard")], "Enter picks the match and keeps Forge's index")
	var answers := []
	panel.answered.connect(func(_id, value): answers.append(value))
	panel._submit()
	assert(answers == [[names.find("Wizard")]], "The answer is Forge's original option index")
	panel.set_submission_enabled(true)
	panel.search.text_changed.emit("zzzz")
	assert(panel.list_pager.matches().is_empty() and panel.list_pager.caption.text == "No matches", "An empty search says so")
	# View battlefield leaves the hand and public zones usable while the decision waits.
	ui._open_decision({"id": 9981, "kind": "choose", "title": "Choose a creature type", "message": "Choose a creature type", "min": 1, "max": 1, "options": options, "sourceCard": source})
	assert(ui._modal_covers_table(), "An open decision covers the table")
	ui._set_decision_board(true)
	assert(not ui._modal_covers_table(), "View battlefield uncovers the table")
	ui._show_zone(0, "Graveyard")
	assert(ui.zone_owner == 0 and ui.zone_name == "Graveyard", "Zones open while viewing the battlefield")
	ui._layout_zone_browser()
	assert(ui.zone_panel.visible, "The zone browser shows while viewing the battlefield")
	ui._close_zone_browser()
	ui._set_decision_board(false)
	assert(ui._modal_covers_table(), "Returning to the decision covers the table again")
	ui._close_modal()
	ui.snapshot = original

## Modes of one card read as text beside that card, even when the stack's top card is a different one.
func _check_modes_as_text(ui: Control, directory: String) -> void:
	var horror := {"id": 9990, "name": "Hullbreaker Horror", "typeLine": "Creature — Kraken Horror", "text": "Whenever you cast a spell, choose up to one —"}
	var amalgam := {"id": 9991, "name": "Overcharged Amalgam", "typeLine": "Creature — Zombie Horror"}
	var modes := [{"label": "Return target spell you don't control to its owner's hand.", "card": horror}, {"label": "Return target nonland permanent to its owner's hand.", "card": horror}]
	ui._open_decision({"id": 9982, "kind": "choose", "title": "", "message": "KLEEN activated Hullbreaker Horror - Choose a mode", "min": 0, "max": 1, "options": modes, "sourceCard": amalgam})
	var panel: Control = ui.modal_panel
	await ui.get_tree().process_frame
	assert(panel.source_view.data.name == "Hullbreaker Horror", "The card with the modes is the one shown")
	assert(panel.option_buttons.size() == 2 and not panel.option_buttons.any(func(button): return button.has_meta("card_preview")), "Each mode is a text option, not a card")
	assert(panel.option_buttons[1] is AbilityOption and panel.option_buttons[1].description.contains("nonland permanent"), "The mode's text is readable")
	if not directory.is_empty():
		await ui.get_tree().create_timer(0.2).timeout
		await ui._save_frame(directory.path_join("modes-as-text.png"))
	panel._toggle(1)
	assert(panel.chosen == [1] and not panel.confirm_button.disabled, "A mode can be chosen and confirmed")
	ui._close_modal()
	var copies := [{"label": "Island", "card": {"id": 1, "name": "Island"}}, {"label": "Island", "card": {"id": 1, "name": "Island"}}]
	assert(panel._with_modes_as_text({"kind": "choose", "options": copies}).options[0].has("card"), "A choice of cards keeps its card faces")
	var stack_items := [{"label": "Copy this", "stackId": 5, "card": horror}, {"label": "Or this", "stackId": 6, "card": horror}]
	assert(panel._with_modes_as_text({"kind": "choose", "options": stack_items}).options[0].has("card"), "Stack entries keep their card faces")

func run(ui: Control, directory: String = "") -> void:
	await _check_type_list(ui, directory)
	await _check_modes_as_text(ui, directory)
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
	state.prompt = {"inputKind": "InputConfirm", "message": "Look at your opponent's hand", "okEnabled": true}
	state.revealed = [{"id": 911, "name": "Sol Ring", "typeLine": "Artifact"}, {"id": 912, "name": "Island"}]
	ui._apply_state(state)
	var reveal: Control = ui.modal_panel
	assert(ui.native_reveal and reveal.ask.options.size() == 2 and reveal.ask.options[0].card.name == "Sol Ring", "Native hand reveals must show the exact authorized faces before OK")
	reveal.board_requested.emit()
	ui._apply_state(state)
	assert(ui.decision_board_button.visible and not ui.modal_center.visible and ui.modal_panel == reveal, "Viewing the table must retain the same unanswered engine decision across snapshots")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("return-to-decision.png"))
	ui.decision_board_button.pressed.emit()
	assert(ui.modal_center.visible and not ui.decision_board_button.visible)
	state.revealed = []
	state.prompt = {"inputKind": "InputPassPriority", "okEnabled": true}
	ui._apply_state(state)
	assert(not ui.modal.visible and not ui.native_reveal, "Completing a hand reveal must close its native modal")
	var source := {"id": 930, "name": "Ingenious Smith", "typeLine": "Creature", "text": "Look at the top four cards of your library. You may reveal an artifact from among them and put it into your hand."}
	state.prompt = {"inputKind": "InputSelectCardsFromList", "message": "Choose an artifact from the cards viewed", "sourceCard": source, "cards": [{"id": 911, "name": "Sol Ring", "typeLine": "Artifact"}], "revealedCards": [{"id": 911, "name": "Sol Ring", "typeLine": "Artifact"}, {"id": 912, "name": "Island"}], "selMin": 0, "selMax": 1, "chosen": [], "okEnabled": true}
	ui._apply_state(state)
	var selection: Control = ui.modal_panel
	assert(selection.source_context.visible and selection.source_context.get_parent() == selection.source_column, "The source card stays visible under the results list")
	assert(selection.options.size() == 2 and not selection.option_buttons[0].disabled and selection.option_buttons[1].disabled, "Viewed cards outside Forge's eligible set must remain visible and unselectable")
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("library-review-enlarged.png"))
		assert(ui.get_global_rect().encloses(selection.get_global_rect()), "Source and library gallery must fit the table")
	# Library search: identical cards stack into one row; each click picks one exact instance.
	var wilds := {"id": 940, "name": "Evolving Wilds", "typeLine": "Land", "text": "{T}, Sacrifice Evolving Wilds: Search your library for a basic land card."}
	var lands: Array = [{"id": 941, "name": "Forest", "typeLine": "Basic Land - Forest"}, {"id": 942, "name": "Forest", "typeLine": "Basic Land - Forest"}, {"id": 943, "name": "Mountain", "typeLine": "Basic Land - Mountain"}, {"id": 944, "name": "Forest", "typeLine": "Basic Land - Forest"}]
	state.prompt = {"inputKind": "InputSelectCardsFromList", "message": "Evolving Wilds (70)
 - {T}, Sacrifice: search.
Select a card from your library", "sourceCard": wilds, "cards": lands, "selMin": 1, "selMax": 2, "chosen": [], "okEnabled": true}
	ui._apply_state(state)
	selection = ui.modal_panel
	assert(selection.rows.size() == 2 and selection.option_buttons.size() == 4, "Three Forests and a Mountain make two rows but keep four exact instances")
	assert(selection.rows[0].text.contains("FOREST") and selection.rows[0].text.contains("×3"), "A stacked row shows its count: " + selection.rows[0].text)
	assert(selection.command.text.begins_with("C:\\EVOLVING_WILDS> select a card from your library"), "The header reads like a command line: " + selection.command.text)
	var picked: Array[int] = []
	selection.selected_card.connect(func(id): picked.append(id))
	selection.rows[0].pressed.emit()
	assert(picked == [941], "A stacked row picks its first copy: " + str(picked))
	state.prompt.chosen = ["card:941"]
	ui._apply_state(state)
	selection = ui.modal_panel
	assert(selection.rows[0].text.contains("[1✓]") and selection.hint.text.begins_with("1 selected"), "The row shows how many copies are picked: " + selection.rows[0].text + " | " + selection.hint.text)
	selection._highlight(1)
	assert(selection.preview.data.get("name", "") == "Mountain" and selection.preview_caption.text.contains("Mountain"), "The preview follows the highlighted row")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("library-search-grouped.png"))
	selection.selected_card.connect(func(id): picked.append(id))
	selection.rows[0].pressed.emit()
	assert(picked == [941, 942], "Clicking a stacked row again picks the next copy, never the same instance: " + str(picked))
	ui._close_modal()
	var order := {"id": 950, "kind": "order", "title": "Select order for simultaneous abilities", "message": "Resolve first", "min": 3, "max": 3, "autoOrder": true, "abilityOrder": true, "options": [{"label": "Draw a card.", "card": {"id": 951, "name": "Fathom Mage"}}, {"label": "Gain life.", "card": {"id": 952, "name": "Soul Warden"}}, {"label": "Create a token.", "card": {"id": 953, "name": "Young Pyromancer"}}]}
	ui._open_decision(order)
	var panel: Control = ui.modal_panel
	panel._toggle(1)
	assert(panel.option_buttons[1].text == "1 →" and panel.order_preview.text.contains("Soul Warden"), "Order numbers and arrows must identify the resolution sequence without repeated card text")
	var answers: Array = []
	panel.answered.connect(func(_id, value): answers.append(value))
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("simultaneous-abilities-large.png"))
		assert(ui.get_global_rect().encloses(panel.get_global_rect()), "Large simultaneous-ability cards must fit the viewport")
	panel.auto_button.pressed.emit()
	assert(answers == [[1, 0, 2]], "Auto preserves chosen order and appends Forge's remaining order exactly once")
	ui._close_modal()
	ui.live = false
	ui._apply_state(saved)
	ui.selected = ui.cards[1].data.duplicate(true)
	ui.hovered_source = ui.cards[3]
	ui.cards[3].hover_active = true
	var old_tapped: bool = ui.cards[3].data.get("tapped", false)
	ui._tap(true)
	assert(ui.cards[3].data.tapped != old_tapped and int(ui.selected.id) == 3, "T must act on the hovered card, regardless of the last clicked card")
	ui.hovered_source = null
	ui._tap(true)
	assert(ui.cards[3].data.tapped != old_tapped, "T over empty space must never act on stale selection")
	ui.adapter.state = saved.duplicate(true)
	ui.live = was_live
	if saved_cancel == null:
		ui.cancel_button.queue_free()
		ui.cancel_button = saved_cancel
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	print("PASS: authorized hand reveal, retained battlefield review, enlarged source/gallery, eligible-only selection, Forge Auto ordering and hover keyboard action")
