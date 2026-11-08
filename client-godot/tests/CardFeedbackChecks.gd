extends RefCounted

func run(ui: Control, directory: String = "") -> void:
	const Option = preload("res://scripts/ui/ManaOption.gd")
	assert(Option.colors_for("Green") == [4] and Option.colors_for("Black") == [2])
	assert(Option.colors_for("Add {W}, {U}, or {G}.") == [0, 1, 4])
	assert(Option.colors_for("Destroy target green creature").is_empty(), "Rules text must not become a mana choice")
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var fixture: Dictionary = saved.duplicate(true)
	var creature: Dictionary = fixture.players[0].zones.Battlefield[0]
	creature.merge({"name": "Atraxa, Praetors' Voice", "power": 6, "toughness": 6, "stats": "6 / 6", "sick": true, "damage": 2, "counters": {"+1/+1": 2}}, true)
	fixture.combat = [{"attacker": 40, "defenderId": 0, "blockers": [creature.id]}]
	fixture.stack = [{"id": 991, "sourceId": 992, "card": creature, "text": "A deliberately long spell description: destroy target creature or enchantment, then draw a card. The complete interaction must wrap within the stack rail."}]
	ui._apply_state(fixture)
	await ui.get_tree().process_frame
	ui._update_lines()
	assert(ui.targeting_overlay.lines.any(func(line): return line.size() == 3 and line[2] == Color("80d9ff")), "Authoritative blockers must have visible assignment arrows")
	var view: Control = ui.cards[creature.id]
	assert(view.face.data.sick and view.face.data.damage == 2 and view.face.data.counters["+1/+1"] == 2)
	var stack_button: Button = ui.stack_box.get_child(0)
	var stack_text: Label = stack_button.rules_label
	assert(stack_text.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and stack_button.custom_minimum_size.y > 70, "Stack rules must wrap into a readable multi-line entry")
	ui._reject_card_action(creature.id)
	assert(view.rejection == 1 and not view.data.get("tapped", false), "Rejection must animate without changing tap state")
	if not directory.is_empty():
		view._on_enter()
		await ui.get_tree().create_timer(0.2).timeout
		await ui._save_frame(directory.path_join("card-status-and-stack.png"))
		view._on_exit()
	creature.damage = 0
	creature.sick = false
	creature.counters = {}
	ui._apply_state(fixture)
	assert(view.face.data.damage == 0 and not view.face.data.sick and view.face.data.counters.is_empty(), "Cleanup and counter removal must refresh cached faces")
	var ask := {"id": 994, "kind": "choose", "title": "Seaside Citadel", "message": "Choose mana to add", "min": 1, "max": 1, "options": [{"label": "White"}, {"label": "Blue"}, {"label": "Green"}]}
	ui._open_decision(ask)
	assert(ui.modal_panel.option_buttons[2] is Option and ui.modal_panel.option_buttons[2].colors == [4])
	ui.modal_panel._toggle(2)
	assert(ui.modal_panel.chosen == [2] and not ui.modal_panel.confirm_button.disabled, "Icon choices must retain the engine's option index")
	if not directory.is_empty():
		ui.modal_panel.option_buttons[2].set_process(false)
		ui.modal_panel.option_buttons[2].glow = 1
		ui.modal_panel.option_buttons[2].queue_redraw()
		await ui._save_frame(directory.path_join("mana-color-choice.png"))
	ui._close_modal()
	const Ability = preload("res://scripts/ui/AbilityOption.gd")
	var reef_options := [
		{"label": "{T}: Add {C}."},
		{"label": "{1}, {T}: Put a storage counter on Dreadship Reef."},
		{"label": "{1}, Remove X storage counters from Dreadship Reef: Add X mana in any combination of {U} and/or {B}."}
	]
	ui._open_decision({"id": 998, "kind": "choose", "title": "Choose ability", "message": "Dreadship Reef", "min": 0, "max": 1, "options": reef_options})
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	var reef_button: Button = ui.modal_panel.option_buttons[2]
	assert(reef_button.size.x >= 480, "The whole ability row must be a full-width click target")
	assert(reef_button is Ability and reef_button.text.is_empty(), "Complex abilities must use full effect/cost rows rather than extracted mana icons")
	assert(reef_button.cost_view.text == "Cost: {1}, Remove X storage counters from Dreadship Reef")
	assert(reef_button.effect_view.text == "Add X mana in any combination of {U} and/or {B}.", "Variable production must retain its quantity and combination rules")
	assert(ui.modal_panel.option_buttons[0].effect_view.text.contains("one colorless mana"))
	assert(reef_button.effect_view.runs.any(func(run): return not run.icon.is_empty()), "Rules must render inline mana symbols")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("dreadship-reef-abilities.png"))
	assert(not ui.modal_panel.confirm_button.visible, "Choosing an ability needs no separate Confirm")
	var activated: Array = []
	var reef_panel: Control = ui.modal_panel
	reef_panel.answered.connect(func(id, value): activated.append([id, value]))
	reef_panel._toggle(2)
	assert(reef_panel.chosen == [2] and reef_button.text.is_empty(), "Selecting a formatted ability must preserve the exact engine index and formatting")
	assert(activated == [[998, [2]]], "Clicking an ability activates exactly that ability")
	ui._close_modal()
	ui._open_decision({"id": 9999, "kind": "choose", "title": "Manifold Insights", "sourceCard": {"id": 9898, "name": "Manifold Insights", "text": "Reveal the top ten cards of your library. Starting with the next opponent in turn order, each opponent chooses a different nonland card from among them. Put the chosen cards into your hand and the rest on the bottom of your library in a random order."}, "message": "Choose a nonland card", "min": 1, "max": 1, "options": [{"label": creature.name, "card": creature}]})
	assert(ui.modal_panel.source_view.data.name == "Manifold Insights", "Intervention dialogs must retain the source card beside the choice")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("decision-source-card.png"))
	ui._close_modal()
	ui._open_decision({"id": 995, "kind": "choose", "title": "Choose a card", "message": "Select the card to use", "min": 1, "max": 1, "options": [{"label": creature.name, "card": creature}, {"label": "Face-down card", "card": {"id": 999, "hidden": true}}]})
	assert(ui.modal_panel.option_buttons[0].get_meta("card_preview").data.name == creature.name)
	assert(ui.modal_panel.option_buttons[1].get_meta("card_preview").data.hidden)
	ui.modal_panel._toggle(0)
	assert(ui.modal_panel.option_buttons[0].get_meta("card_preview").selected, "Card choices must mark the selected face")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("card-choice-popup.png"))
	ui._close_modal()
	var color_state := {"asks": [], "prompt": {"inputKind": "InputConfirm", "message": "Choose mana", "okLabel": "Green", "cancelLabel": "Black", "okEnabled": true, "cancelEnabled": true}, "connectionReady": true}
	ui._open_decision({"id": 996, "kind": "message", "title": "AI deck warning", "message": "The AI cannot play these cards well.", "options": [{"label": "Atraxa, Praetors' Voice", "card": {"id": -1, "name": "Atraxa, Praetors' Voice"}}, {"label": "Fathom Mage", "card": {"id": -1, "name": "Fathom Mage"}}]})
	if not directory.is_empty(): await ui._save_frame(directory.path_join("ai-warning-card-images.png"))
	ui._close_modal()
	var panel = preload("res://scripts/ui/ManaColorPanel.gd").new()
	ui.add_child(panel)
	assert(panel.needs_selection(color_state))
	panel.present(color_state)
	var actions: Array = []
	panel.action_requested.connect(func(action): actions.append(action))
	panel.get_child(0).get_child(1).get_child(1).pressed.emit()
	assert(actions == ["cancel"], "The second color must use Forge's second button without canceling the mana choice")
	panel.queue_free()
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	print("PASS: mana icon routing, sickness/counter/damage refresh, rejection feedback, readable stack and block arrows")
