extends "res://tests/DecisionIntegration.gd"
const ManaPaymentDialog = preload("res://scripts/ui/ManaPaymentPanel.gd")
var scenario := ""
var saw: Dictionary = {}

func capture(stage: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--live-capture="):
			await ui._save_frame(arg.trim_prefix("--live-capture=").replace(".png", "-" + stage + ".png"))

func step() -> bool:
	var state: Dictionary = ui.snapshot
	if not state.asks.is_empty():
		var ask: Dictionary = state.asks[0]
		print("SCENARIO choice: ", ask.kind, " ", ask.get("title", ""), " / ", ask.get("message", ""))
		if ask.kind == "choose" and ask.get("min", 0) == 0:
			if not answer_off_popup([]): ui.modal_panel._emit_answer([])
		else: submit_choice()
		return true
	if ui.modal_panel is SelectionDialog and ui.modal.visible:
		if not ui.modal_panel.none_button.disabled: ui.modal_panel.none_button.pressed.emit()
		elif not ui.modal_panel.confirm_button.disabled: ui.modal_panel.confirm_button.pressed.emit()
		elif not ui.modal_panel.option_buttons.is_empty(): ui.modal_panel.option_buttons[0].pressed.emit()
		else: return check(false, "Empty required gallery: " + str(state.prompt))
		return true
	if ui.incoming_effect.panel.visible and not state.stack.is_empty() and int(ui.incoming_effect.active.get("stackId", -1)) == int(state.stack[0].id):
		ui.incoming_effect.resolve_button.pressed.emit()
		return true
	if press_card_tether(): return true
	if ui.interaction_panel.panel.visible and not ui.interaction_panel.confirm_button.disabled:
		ui.interaction_panel.confirm_button.pressed.emit()
		return true
	if state.prompt.okEnabled:
		ui._primary_action()
		return true
	return check(false, "No usable interaction control: " + JSON.stringify(state.prompt))

func prepared() -> bool:
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return false
		var state: Dictionary = ui.snapshot
		if scenario == "blocking" and state.prompt.get("inputKind", "") == "InputBlock": return true
		# The fixture jumps to turn 5 straight after the starting roll; finish that animation as a player would.
		if int(state.game.turn) >= 5 and ui.modal.visible and is_instance_valid(ui.modal_panel) and ui.modal_panel.get_script().resource_path.ends_with("CoinTossPanel.gd"):
			ui.coin_toss_seen[int(ui.modal_panel.toss_id)] = true
			ui._close_modal()
		if scenario != "blocking" and int(state.game.turn) >= 5 and state.prompt.get("inputKind", "") == "InputPassPriority":
			if scenario in ["proliferate", "tokens", "reanimate", "combat"]:
				if state.game.activePlayer == 0 and state.game.phase == "Main 1": return true
			else: return true
		if not state.asks.is_empty(): submit_choice()
		elif state.prompt.get("inputKind", "") == "InputConfirmMulligan": ui.opening_hand.submit("ok")
		elif StartingPlayerDialog.needs_selection(state) and ui.modal_panel is StartingPlayerDialog: ui.modal_panel.buttons[0].pressed.emit()
		elif state.prompt.okEnabled: ui._primary_action()
	return check(false, "Prepared board did not load: turn=%s input=%s asks=%s modal=%s incoming=%s stack=%s" % [ui.snapshot.get("game", {}).get("turn", -1), ui.snapshot.get("prompt", {}).get("inputKind", ""), ui.snapshot.get("asks", []).map(func(ask): return [ask.kind, ask.get("title", "")]), (ui.modal_panel.get_script().resource_path if is_instance_valid(ui.modal_panel) and ui.modal_panel.get_script() != null else "none"), ui.incoming_effect.panel.visible, ui.snapshot.get("stack", []).size()])

func settle() -> bool:
	for index in range(80):
		if not await wait_ready(): return false
		if ui.snapshot.stack.is_empty() and ui.snapshot.asks.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": return true
		if not await step(): return false
	return check(false, "Interaction did not settle: " + str(ui.snapshot.prompt) + " modal=" + str(ui.modal.visible) + " " + (ui.modal_panel.get_script().resource_path if is_instance_valid(ui.modal_panel) and ui.modal_panel.get_script() != null else "none") + " effect=" + str(ui.incoming_effect.showing()) + " responding=" + str(ui.incoming_effect.responding) + " interaction=" + str(ui.interaction_panel.panel.visible) + " autoPass=" + str(ui.snapshot.get("autoPassStackId", -1)) + " acked=" + str(ui.adapter.acknowledged_effects) + " stack=" + str(ui.snapshot.stack.map(func(item): return [item.id, item.get("sourceName", "")])))

func tap(name: String, count: int = 1) -> bool:
	var sources: Array = zone("Battlefield").filter(func(card): return card.name == name and not card.get("tapped", false))
	if not check(sources.size() >= count, "Missing untapped sources: " + name): return false
	for index in range(count):
		ui._click_card(sources[index].id)
		if not await wait_ready(): return false
	return true

func cast(name: String) -> bool:
	var card := find_card(name)
	if not check(not card.is_empty(), "Missing spell " + name): return false
	ui._click_card(card.id)
	if not await wait_ready(): return false
	return check(not (ui.snapshot.asks.is_empty() and ui.snapshot.stack.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority" and zone("Hand").any(func(value): return value.id == card.id)), "Cast was rejected: " + name + " / " + str(ui.snapshot.prompt))

func select_named(name: String) -> bool:
	if not ui.snapshot.asks.is_empty(): return await choose_named(name)
	if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and ui.interaction_panel.panel.visible:
		var legal_ids: Array = ui.snapshot.prompt.selectable.map(func(id): return int(id))
		var targets: Array = ui.snapshot.prompt.get("cards", []).filter(func(card): return card.name == name and legal_ids.has(int(card.id)))
		if not check(targets.size() == 1, "Expected one legal board target named " + name): return false
		ui._click_card(targets[0].id)
		if not await wait_ready(): return false
		if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and not ui.interaction_panel.confirm_button.disabled:
			ui.interaction_panel.confirm_button.pressed.emit()
			return await wait_ready()
		return true
	if not check(ui.modal_panel is SelectionDialog and ui.modal.visible, "Expected visible card gallery for " + name + " (open modal: " + (ui.modal_panel.get_script().resource_path if is_instance_valid(ui.modal_panel) and ui.modal_panel.get_script() != null else "none") + ", decision panel visible: " + str(ui.interaction_panel.panel.visible) + "): " + str(ui.snapshot.prompt)): return false
	for index in range(ui.modal_panel.options.size()):
		if ui.modal_panel.options[index].get("name", "") == name:
			ui.modal_panel.option_buttons[index].pressed.emit()
			if not await wait_ready(): return false
			if ui.modal_panel is SelectionDialog and ui.modal.visible and not ui.modal_panel.confirm_button.disabled: ui.modal_panel.confirm_button.pressed.emit()
			return await wait_ready()
	return check(false, "Gallery omitted " + name)

func counter(card: Dictionary, key: String) -> int:
	return int(card.get("counters", {}).get(key, 0))

func drop_equipment(source: Dictionary, target: Dictionary) -> void:
	var view: Control = ui.cards[source.id]
	var recipient: Control = ui.cards[target.id]
	var start: Vector2 = view.get_global_transform() * (view.size * 0.5)
	var finish: Vector2 = recipient.get_global_transform() * (recipient.size * 0.5)
	ui._drag_card(source.id, finish - start)

func reported_interactions() -> bool:
	var plains: Array = zone("Battlefield").filter(func(card): return card.name == "Plains")
	for index in range(2, -1, -1):
		ui._click_card(plains[index].id)
		if not await wait_ready(): return false
	for index in range(3):
		var current: Dictionary = ui.cards[plains[index].id].data
		if not check(current.availableActions.undoTap, "Each preceding unused mana tap must regain click undo: " + str(index) + " " + str(current)): return false
		ui._click_card(plains[index].id)
		if not await wait_ready(): return false
		if not check(not ui.cards[plains[index].id].data.tapped and ui.snapshot.players[0].mana.get("W", 0) == 2 - index, "Each untap must remove only its activation's mana"): return false
	var expanse := find_card("Terramorphic Expanse")
	var bear := find_card("Grizzly Bears", "Battlefield")
	var splitter := find_card("Bonesplitter", "Battlefield")
	if not await tap("Plains"): return false
	drop_equipment(splitter, bear)
	if not await wait_ready(): return false
	for index in range(30):
		if not await wait_ready(): return false
		if int(find_card("Bonesplitter", "Battlefield").get("attachedTo", -1)) == int(bear.id): break
		if not ui.snapshot.asks.is_empty(): submit_choice()
		elif ui.snapshot.prompt.get("inputKind", "") == "InputConfirm" and ui.snapshot.prompt.okEnabled: ui._primary_action()
		else: await ui.get_tree().create_timer(0.1).timeout
	if not check(int(find_card("Bonesplitter", "Battlefield").get("attachedTo", -1)) == int(bear.id), "Prepaid dropped equipment must attach without a manual Resolve click: " + str(ui.snapshot.prompt)): return false
	await capture("equipped")
	var gear := find_card("Vulshok Battlegear", "Battlefield")
	drop_equipment(gear, bear)
	if not await wait_ready(): return false
	if not check(ui.modal.visible and ui.modal_panel is ManaPaymentDialog and not ui.modal_panel.cancel_button.disabled and not ui.modal_panel.sources_button.disabled, "Insufficient equip mana must offer battlefield sources and Cancel"): return false
	await capture("equip-needs-mana")
	ui.modal_panel.cancel_button.pressed.emit()
	if not await wait_ready(): return false
	if not check(not find_card("Vulshok Battlegear", "Battlefield").has("attachedTo"), "Canceling equip must leave the equipment unattached"): return false
	drop_equipment(gear, bear)
	if not await wait_ready(): return false
	ui.modal_panel.sources_button.pressed.emit()
	if not await tap("Plains", 2) or not await tap("Forest"): return false
	for index in range(20):
		if int(find_card("Vulshok Battlegear", "Battlefield").get("attachedTo", -1)) == int(bear.id): break
		if not await wait_ready(): return false
	if not check(int(find_card("Vulshok Battlegear", "Battlefield").get("attachedTo", -1)) == int(bear.id), "Adding mana from the board must finish the dropped equip through Forge"): return false
	ui._click_card(expanse.id)
	if not await wait_ready(): return false
	if not check(ui.cards[expanse.id].data.zone == "Battlefield" and not ui.cards[expanse.id].data.tapped, "Terramorphic Expanse itself must enter untapped"): return false
	await capture("expanse-untapped")
	var forests_before: Array = zone("Battlefield").filter(func(card): return card.name == "Forest").map(func(card): return int(card.id))
	ui._click_card(expanse.id)
	if not await resolve_to_choice() or not await choose_named("Forest") or not await settle(): return false
	var fetched: Array = zone("Battlefield").filter(func(card): return card.name == "Forest" and not forests_before.has(int(card.id)))
	return check(fetched.size() == 1 and fetched[0].get("tapped", false), "The basic land fetched by Expanse must enter tapped")

func wakanda() -> bool:
	if not await tap("Forest", 6) or not await cast("Wakanda Forever!"): return false
	var battlefield_chosen := false
	var hand_chosen := false
	for index in range(60):
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty():
			var ask: Dictionary = ui.snapshot.asks[0]
			if not check(ask.kind != "message" or not ask.get("options", []).any(func(option): return option.has("card")), "Wakanda's reveal must go directly into its selectable gallery"): return false
		if ui.modal_panel is SelectionDialog and ui.modal.visible:
			if not check(ui.modal_panel.options.size() == 6 and ui.modal_panel.option_buttons.any(func(button): return not button.disabled), "Wakanda's first gallery must show all six revealed cards with eligible cards clickable"): return false
			await capture("hand-choice" if battlefield_chosen else "battlefield-choice")
			if not battlefield_chosen:
				if not await select_named("Grizzly Bears"): return false
				battlefield_chosen = true
			else:
				if not await select_named("Sol Ring"): return false
				hand_chosen = true
			continue
		if hand_chosen and ui.snapshot.stack.is_empty() and ui.snapshot.asks.is_empty():
			var bear := find_card("Grizzly Bears", "Battlefield")
			await capture("result")
			return check(not bear.is_empty() and counter(bear, "Indestructible") == 1 and not find_card("Sol Ring").is_empty() and zone("Graveyard").size() == 5, "Wakanda must put one permanent on the field with indestructible, one in hand, and the rest in the graveyard: " + str(bear))
		if not await step(): return false
	return check(false, "Wakanda never completed both selections")

func smith() -> bool:
	if not await tap("Plains", 2) or not await cast("Ingenious Smith"): return false
	var viewed_ids: Array = []
	var selected_artifact := false
	for index in range(60):
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty():
			var ask: Dictionary = ui.snapshot.asks[0]
			if ask.kind == "message":
				var shown: Array = ask.get("options", []).filter(func(option): return option.has("card"))
				if shown.size() == 4:
					viewed_ids = shown.map(func(option): return int(option.card.id))
					if not check(shown.all(func(option): return not option.card.get("hidden", false)), "Smith's initial four cards must show their authorized faces"): return false
					var artifacts: Array = shown.filter(func(option): return str(option.card.get("typeLine", "")).contains("Artifact"))
					if not check(artifacts.size() == (1 if scenario == "smith-artifact" else 0), "Smith's first reveal must show the artifact that can actually be selected"): return false
					await capture("four-viewed")
			elif ask.kind == "choose" and ask.options.any(func(option): return option.get("card", {}).get("name", "") == "Sol Ring"):
				if not check(scenario == "smith-artifact" and ask.options.all(func(option): return viewed_ids.has(int(option.get("card", {}).get("id", -1)))), "Smith may only offer artifacts among the same four revealed instances"): return false
				selected_artifact = true
				if not await select_named("Sol Ring"): return false
				continue
		if ui.modal_panel is SelectionDialog and ui.modal.visible:
			var offered: Array = ui.snapshot.prompt.get("cards", [])
			if not check(scenario == "smith-artifact" and offered.size() == 1 and offered[0].name == "Sol Ring" and viewed_ids.has(int(offered[0].id)), "Smith's native choice must come from the exact four viewed cards"): return false
			if not check(ui.modal_panel.options.size() == 4 and ui.modal_panel.option_buttons.filter(func(button): return not button.disabled).size() == 1, "Smith shows all four cards while enabling only the artifact"): return false
			await capture("eligible-artifact")
			selected_artifact = true
			if not await select_named("Sol Ring"): return false
			continue
		if not viewed_ids.is_empty() and not find_card("Ingenious Smith", "Battlefield").is_empty() and ui.snapshot.stack.is_empty() and ui.snapshot.asks.is_empty():
			return check((not find_card("Sol Ring").is_empty()) == (scenario == "smith-artifact") and selected_artifact == (scenario == "smith-artifact"), "No-artifact Smith must add nothing; artifact Smith must add only its chosen artifact")
		if not await step(): return false
	return check(false, "Smith resolution did not finish")

func hand_reveal() -> bool:
	if not await tap("Island") or not await cast("Peek"): return false
	ui._choose_player(1)
	if not await wait_ready(): return false
	if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and ui.snapshot.prompt.okEnabled:
		ui._primary_action()
		if not await wait_ready(): return false
	var saw_hand := false
	for index in range(50):
		if not await wait_ready(): return false
		if ui.native_reveal:
			saw_hand = true
			var panel: Control = ui.modal_panel
			if not check(panel.ask.options.size() == 2 and panel.ask.options.all(func(option): return not option.card.get("hidden", false)) and panel.ask.options.any(func(option): return option.card.name == "Sol Ring"), "Peek must display the opponent's actual hand before acknowledgment"): return false
			panel.board_requested.emit()
			if not check(ui.decision_board_button.visible and not ui.modal_center.visible, "The real hand reveal must allow viewing the battlefield without answering Forge"): return false
			await capture("battlefield-review")
			ui.decision_board_button.pressed.emit()
			await capture("opponent-hand")
			panel._submit()
			continue
		if saw_hand and ui.snapshot.stack.is_empty() and ui.snapshot.asks.is_empty(): return true
		if not await step(): return false
	return check(false, "Peek never displayed the opponent's hand")

func panther_claws() -> bool:
	if not await tap("Plains", 4) or not await cast("Hammer of Nazahn"): return false
	var targeted := false
	var decisions := 0
	for index in range(60):
		if not await wait_ready(): return false
		if not check(not ui.incoming_effect.panel.visible, "Our Claws target must not produce a second spell/ability preview"): return false
		if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets":
			targeted = true
			if not await select_named("T'Challa, the Black Panther"): return false
			continue
		if not ui.snapshot.asks.is_empty() or ui.snapshot.prompt.get("inputKind", "") == "InputConfirm":
			decisions += 1
		if targeted and ui.snapshot.stack.is_empty() and ui.snapshot.asks.is_empty():
			var commander := find_card("T'Challa, the Black Panther", "Battlefield")
			var claws := find_card("Hammer of Nazahn", "Battlefield")
			await capture("attached")
			return check(counter(commander, "P1P1") == 2 and int(commander.power) == 6 and int(claws.get("attachedTo", -1)) == int(commander.id) and decisions == 1, "Claws must attach to T'Challa after his real two-counter cast trigger and one optional-use decision")
		if not await step(): return false
	return check(false, "Claws never finished attaching to T'Challa: " + str(ui.snapshot.prompt))

func proliferate() -> bool:
	if not await tap("Island", 2) or not await cast("Contentious Plan"): return false
	for index in range(30):
		if not ui.snapshot.asks.is_empty() and str(ui.snapshot.asks[0].get("title", "")).to_lower().contains("proliferate"): break
		if ui.board_choice.visible or ui.snapshot.prompt.has("selectionShortcut"): break
		if not await step() or not await wait_ready(): return false
	if not check(ui.board_choice.visible or ui.snapshot.prompt.has("selectionShortcut"), "Proliferate did not present recipients: " + str(ui.snapshot.prompt)): return false
	if not check(not ui.modal.visible, "Proliferate keeps the battlefield available instead of opening a card gallery"): return false
	if ui.snapshot.prompt.has("selectionShortcut"):
		if not check(not ui.stack_scroll.visible and not ui.prompt_body.visible and not ui.primary.visible and not ui.cancel_button.visible, "The active rail decision replaces covered stack items and duplicate native controls"): return false
		if not check(ui.stack_attention.attention_target() == ui.interaction_panel.panel, "Proliferate's attention outline follows the active decision"): return false
	var ballista := find_card("Walking Ballista", "Battlefield")
	ui._click_card(ballista.id)
	if not await wait_ready(): return false
	var selected_count: int = ui.board_choice.chosen.size() if ui.board_choice.visible else ui.snapshot.prompt.get("chosen", []).size()
	if not check(selected_count == 1, "Clicking the actual battlefield card selects a proliferate recipient"): return false
	ui._click_card(ballista.id)
	if not await wait_ready(): return false
	await capture("selection")
	if not ui.snapshot.asks.is_empty():
		if not check(ui.board_choice.mine_button != null and ui.board_choice.mine_button.visible, "Proliferate must expose Select my permanents"): return false
		ui.board_choice.mine_button.pressed.emit()
		var chosen_names: Array = ui.board_choice.chosen.map(func(index): return ui.snapshot.asks[0].options[index].label)
		if not check(["Walking Ballista", "Fathom Mage", "Dreadship Reef", "Jace Beleren"].all(func(name): return chosen_names.has(name)), "Bulk selection omitted eligible noncreature permanents"): return false
		if not check(ui.board_choice.chosen.size() == 4, "Bulk selection must exclude opponent permanents and players"): return false
		ui.board_choice._submit()
	else:
		if not check(ui.interaction_panel.cancel_button.text == "Select my permanents", "Native proliferate must expose Mine"): return false
		ui.interaction_panel.cancel_button.pressed.emit()
		if not await wait_ready(): return false
		if not check(ui.snapshot.prompt.chosen.size() == 4, "Native Mine must select exactly four eligible permanents"): return false
		ui.interaction_panel.confirm_button.pressed.emit()
	if not await settle(): return false
	if not check(counter(find_card("Walking Ballista", "Battlefield"), "P1P1") == 5 and counter(find_card("Fathom Mage", "Battlefield"), "P1P1") == 4, "Scales + Constrictor must turn proliferate's one +1/+1 counter into three: " + str(zone("Battlefield"))): return false
	if not check(counter(find_card("Dreadship Reef", "Battlefield"), "STORAGE") == 3 and counter(find_card("Jace Beleren", "Battlefield"), "LOYALTY") == 4, "Noncreature counters must increase without creature-only replacement effects"): return false
	if not check(counter(ui.snapshot.players[0], "EXPERIENCE") == 2 and counter(ui.snapshot.players[1], "POISON") == 1, "Mine must leave unselected player counters unchanged"): return false
	if not check(zone("Hand").size() == 4, "Contentious Plan plus three Fathom Mage triggers must draw exactly four cards, got " + str(zone("Hand").size())): return false
	await capture("result")
	return true

func blocking() -> bool:
	var attackers: Array = ui.snapshot.combat.map(func(entry): return int(entry.attacker))
	if not check(attackers.size() == 2, "Two actual attackers are available for separate block assignments"): return false
	var defenders := [find_card("Centaur Courser", "Battlefield"), find_card("Hill Giant", "Battlefield")]
	for index in range(2):
		ui._click_card(attackers[index])
		if not await wait_ready(): return false
		ui._click_card(defenders[index].id)
		if not await wait_ready(): return false
		if not check(ui.snapshot.prompt.get("inputKind", "") == "InputBlock" and ui.snapshot.combat.any(func(entry): return int(entry.attacker) == attackers[index] and entry.blockers.has(defenders[index].id)), "Block assignment appears before any OK confirmation: " + JSON.stringify([ui.snapshot.prompt, ui.snapshot.combat])): return false
	ui._update_lines()
	var blue: Array = ui.targeting_overlay.lines.filter(func(line): return line.size() > 2 and line[2] == Color("80d9ff"))
	if not check(blue.size() == 2, "Both declared blockers have immediate arrows before OK"): return false
	ui._click_card(attackers[0])
	if not await wait_ready(): return false
	ui._click_card(defenders[0].id)
	if not await wait_ready(): return false
	if not check(ui.snapshot.combat.any(func(entry): return int(entry.attacker) == attackers[0] and entry.blockers.is_empty()), "Clicking the assigned blocker removes it before confirmation"): return false
	ui._click_card(defenders[0].id)
	if not await wait_ready(): return false
	await capture("assignments-before-ok")
	ui._primary_action()
	if not await wait_ready(): return false
	return check(ui.snapshot.prompt.get("inputKind", "") != "InputBlock", "A single final OK commits all block assignments")

func equipment() -> bool:
	var host := find_card("Grizzly Bears", "Battlefield")
	var gear := [find_card("Bonesplitter", "Battlefield"), find_card("Basilisk Collar", "Battlefield")]
	for card in gear:
		if not check(int(card.get("attachedTo", -1)) == int(host.id) and ui.cards[card.id].get_parent() == ui.cards[host.id].get_parent() and ui.cards[card.id].resting_z < ui.cards[host.id].resting_z, "Both pieces of equipment stack behind their actual creature"): return false
	if not check(ui.cards[gear[0].id].resting_position != ui.cards[gear[1].id].resting_position, "Multiple equipment cards have distinct exposed edges"): return false
	await capture("attached")
	if not await tap("Island") or not await cast("Unsummon") or not await select_named("Grizzly Bears") or not await settle(): return false
	if not check(not find_card("Grizzly Bears").is_empty(), "Unsummon returns the equipped creature to hand"): return false
	for card in gear:
		var detached := find_card(card.name, "Battlefield")
		if not check(not detached.is_empty() and not detached.has("attachedTo") and ui.cards[card.id].is_visible_in_tree(), "Equipment stays visible and separates when its creature leaves play"): return false
	await capture("detached")
	return true

func triland() -> bool:
	var land := find_card("Sandsteppe Citadel", "Battlefield")
	ui._click_card(land.id)
	if not await resolve_to_choice(): return false
	var ask: Dictionary = ui.snapshot.asks[0]
	if not check(ask.options.size() == 3, "Tri-land presents one choice per mana color"): return false
	for option in ask.options:
		var label: String = option.label
		if not check(not label.contains("{T}:") and ask.get("sourceCard", {}).get("name", "") == land.name, "Tap-only mana choice hides the tap cost and retains the source card: " + str(ask)): return false
		var count := 0
		for code in ["W", "B", "G"]:
			if label.contains("{" + code + "}"): count += 1
		if not check(count == 1 and not label.contains(" or "), "Each tri-land choice describes only its actual selected mana: " + label): return false
	var tether: Control = ui.interaction_panel.callout
	if not check(tether.visible and not ui.modal.visible and tether.mode_buttons.size() == 3 and tether.mode_buttons.all(func(button): return button.colors.size() == 1) and not tether.yes_button.visible, "The mana choice is a tether of mana symbols on the land, picked with one click: no popup"): return false
	if not check(tether.title.text.contains("SANDSTEPPE CITADEL"), "The tether names its card: " + tether.title.text): return false
	await capture("mana-options")
	for i in range(tether.mode_buttons.size()):
		if str(ask.options[i].label).begins_with("Green"): tether.mode_buttons[i].pressed.emit()
	if not await wait_ready(): return false
	return check(ui.snapshot.players[0].mana.get("G", 0) == 1 and ui.snapshot.players[0].mana.get("W", 0) == 0 and ui.snapshot.players[0].mana.get("B", 0) == 0, "Selecting green produces precisely green mana")

func insights() -> bool:
	var chosen := false
	var revealed := false
	for index in range(50):
		if not await wait_ready(): return false
		if ui.modal.visible and ui.modal_panel is SelectionDialog:
			if not check(ui.modal_panel.source_context.visible and ui.modal_panel.source_view.data.get("name", "") == "Manifold Insights" and not ui.modal_panel.source_rules.visible, "Native card choices show the resolving source without duplicating its printed rules"): return false
			chosen = true
			await capture("choice")
			ui.modal_panel.option_buttons[0].pressed.emit()
			continue
		elif not ui.snapshot.asks.is_empty():
			var ask: Dictionary = ui.snapshot.asks[0]
			if not check(ask.get("sourceCard", {}).get("name", "") == "Manifold Insights", "Every reveal/choice carries the resolving source: " + str(ask)): return false
			if ask.kind == "message":
				revealed = ask.get("options", []).any(func(option): return option.has("card") and not option.card.get("hidden", false))
				await capture("reveal")
			elif ask.kind == "choose":
				chosen = true
				if not check(ui.modal_panel.source_view != null and ui.modal_panel.source_view.data.name == "Manifold Insights", "The source face remains visible while choosing"): return false
				await capture("choice")
		if chosen and ui.snapshot.stack.is_empty() and ui.snapshot.asks.is_empty():
			return check(revealed and int(ui.snapshot.players[1].handCount) == 2, "Each opponent's chosen card goes into the caster's hand: " + str(ui.snapshot.players[1].handCount))
		if not await step(): return false
	return check(false, "Manifold Insights did not complete; reveal=%s choice=%s" % [revealed, chosen])

func tokens() -> bool:
	if not await tap("Plains", 2) or not await cast("Raise the Alarm") or not await settle(): return false
	var soldiers: Array = zone("Battlefield").filter(func(card): return card.get("token", false) and card.get("typeLine", "").contains("Soldier"))
	if not check(soldiers.size() == 4, "Doubling Season must create four Soldiers"): return false
	print("TOKEN IMAGE: ", soldiers[0].get("imageKey", ""), " / ", soldiers[0].get("tokenImageUrls", []))
	if not check(not soldiers[0].get("tokenImageUrls", []).is_empty(), "Created tokens must expose their exact Forge artwork URLs"): return false
	if "--token-online-images" in OS.get_cmdline_user_args():
		var image_deadline := Time.get_ticks_msec() + 45000
		while Time.get_ticks_msec() < image_deadline and ui.cards[soldiers[0].id].face.full_image == null:
			await ui.get_tree().create_timer(0.1).timeout
		if not check(soldiers.all(func(card): return ui.cards[card.id].face.full_image != null), "Every created Soldier must display its downloaded token face"): return false
	if not check(ui.snapshot.players[0].life == 44 and ui.snapshot.players[1].life == 36 and ui.snapshot.players[2].life == 36, "Four Warden/Tremors triggers must gain four life and deal four damage to each opponent: " + str(ui.snapshot.players.map(func(player): return player.life))): return false
	await capture("result")
	return true

func reanimate() -> bool:
	if not await tap("Swamp") or not await cast("Reanimate"): return false
	if not await select_named("Eternal Witness"): return false
	for index in range(40):
		if not await wait_ready(): return false
		if ui.snapshot.stack.is_empty() and ui.snapshot.asks.is_empty() and not find_card("Reanimate").is_empty() and not find_card("Eternal Witness", "Battlefield").is_empty(): break
		var offered: Array = ui.snapshot.asks[0].get("options", []) if not ui.snapshot.asks.is_empty() else (ui.modal_panel.options if ui.modal_panel is SelectionDialog and ui.modal.visible else [])
		if offered.any(func(option): return option.get("name", option.get("label", "")) == "Reanimate"):
			if not await select_named("Reanimate"): return false
			break
		if not await step(): return false
	if not await settle(): return false
	if not check(not find_card("Eternal Witness", "Battlefield").is_empty() and not find_card("Reanimate").is_empty(), "Witness must reanimate and return its own Reanimate spell to hand"): return false
	if not check(ui.snapshot.players[0].life == 38, "Reanimate loses three life and Soul Warden gains one"): return false
	if not check(find_card("Eternal Witness", "Battlefield").get("sick", false), "The reanimated creature must display summoning sickness"): return false
	await capture("result")
	return true

func await_spell(name: String) -> bool:
	for index in range(60):
		if not await wait_ready(): return false
		if not ui.snapshot.stack.is_empty() and ui.snapshot.stack[0].get("sourceName", "") == name and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority":
			# A wipe shows as its card mid-table, anything else as the response popup; both name the spell.
			if not check(ui.incoming_effect.showing() and ui.incoming_effect.active.get("stackId", -1) == ui.snapshot.stack[0].id, "The response popup must identify " + name): return false
			await capture("incoming")
			ui.incoming_effect.respond() # View battlefield / Respond with action
			return true
		if not await step(): return false
	return check(false, "The opponent did not cast " + name)

func protection() -> bool:
	if not await await_spell("Wrath of God"): return false
	if not await tap("Forest", 2) or not await cast("Heroic Intervention") or not await settle(): return false
	if not check(not find_card("Grizzly Bears", "Battlefield").is_empty() and not find_card("Elvish Mystic", "Battlefield").is_empty() and not find_card("Sol Ring", "Battlefield").is_empty(), "Intervention must preserve your creatures; Wrath must leave artifacts alone"): return false
	if not check(ui.snapshot.players[1].zones.Graveyard.any(func(card): return card.name == "Grizzly Bears") and ui.snapshot.players[1].zones.Battlefield.any(func(card): return card.name == "Darksteel Gargoyle"), "Wrath must kill the opposing Bear but preserve the indestructible Gargoyle"): return false
	if not await tap("Plains") or not await cast("Swords to Plowshares"): return false
	if not await select_named("Darksteel Gargoyle"): return false
	if not await settle(): return false
	if not check(ui.snapshot.players[1].zones.Exile.any(func(card): return card.name == "Darksteel Gargoyle") and ui.snapshot.players[1].life == 43, "Exile must bypass indestructible and grant life equal to the Gargoyle's power"): return false
	await capture("result")
	return true

func blink() -> bool:
	if not await await_spell("Lightning Bolt"): return false
	var targets: Array = ui.snapshot.stack[0].get("targets", []).filter(func(target): return target.kind == "card")
	if not check(targets.size() == 1, "The Bolt fixture requires a creature target"): return false
	var name: String = targets[0].name
	var hand_before: int = zone("Hand").size()
	if not await tap("Plains") or not await cast("Ephemerate") or not await select_named(name) or not await settle(): return false
	var returned := find_card(name, "Battlefield")
	# Forge retains the physical card ID across zone changes; its internal timestamp
	# carries rules-object identity. Survival, sickness and fresh ETBs verify the blink.
	if not check(not returned.is_empty() and returned.get("sick", false) and returned.get("damage", 0) == 0, "The blinked creature must survive Bolt, return with sickness, and have no marked damage"): return false
	if not check(zone("Exile").any(func(card): return card.name == "Ephemerate") and ui.snapshot.players[1].zones.Graveyard.any(func(card): return card.name == "Lightning Bolt"), "Ephemerate must rebound into exile and Bolt must finish without killing the new object"): return false
	var expected_life := 41 if name == "Elvish Visionary" else 40
	var expected_hand := hand_before if name == "Elvish Visionary" else hand_before - 1
	if not check(ui.snapshot.players[0].life == expected_life and zone("Hand").size() == expected_hand, "Blink's ETB draw/life triggers must resolve exactly once"): return false
	await capture("result")
	return true

func combat() -> bool:
	var attacker := find_card("Vampire Nighthawk", "Battlefield")
	var aura := find_card("Rancor", "Battlefield")
	if not check(ui.cards[aura.id].get_parent() == ui.cards[attacker.id].get_parent() and ui.cards[aura.id].resting_z < ui.cards[attacker.id].resting_z, "Attached Aura is stacked behind its actual creature"): return false
	if not check(attacker.get("power", 0) == 4 and attacker.get("toughness", 0) == 3, "Rancor must give the Nighthawk +2 power"): return false
	for index in range(30):
		if ui.snapshot.prompt.get("inputKind", "") == "InputAttack": break
		if not await step() or not await wait_ready(): return false
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputAttack", "Reach actual attacker selection"): return false
	ui._click_card(attacker.id)
	ui._choose_player(1)
	if not await wait_ready(): return false
	if not check(ui.snapshot.combat.any(func(entry): return int(entry.attacker) == int(attacker.id)), "Attack must be declared through board controls"): return false
	var distributed := false
	for index in range(60):
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "distribute":
			var ask: Dictionary = ui.snapshot.asks[0]
			if not check(ask.options.size() == 2 and int(ask.amount) == 4 and int(ask.lethal[0]) == 1, "Deathtouch must make one damage lethal for trample assignment"): return false
			var spinners: Array = ui.modal_panel.find_children("*", "SpinBox", true, false)
			spinners[0].value = 1
			spinners[1].value = 3
			if not check(not ui.modal_panel.confirm_button.disabled, "One blocker damage plus three trample damage must be a legal visible allocation"): return false
			await capture("damage-allocation")
			ui.modal_panel.confirm_button.pressed.emit()
			distributed = true
		elif distributed and ui.snapshot.stack.is_empty() and not find_card("Rancor").is_empty(): break
		else:
			if not await step(): return false
	if not check(distributed and ui.snapshot.players[0].life == 44 and ui.snapshot.players[1].life == 37, "Combat must deal three trample damage and gain four lifelink life"): return false
	if not check(not find_card("Vampire Nighthawk", "Graveyard").is_empty() and not find_card("Rancor").is_empty(), "The blocker must kill Nighthawk and Rancor's death trigger must return the aura"): return false
	var blocker: Array = ui.snapshot.players[1].zones.Battlefield.filter(func(card): return card.name == "Darksteel Gargoyle")
	if not check(blocker.size() == 1 and blocker[0].get("damage", 0) == 1, "The indestructible blocker must survive deathtouch with a visible temporary damage marker"): return false
	await capture("result")
	return true

func stack_priority() -> bool:
	if scenario in ["stack-response", "stack-free-response"]:
		if not check(not ui.snapshot.stack.is_empty() and int(ui.snapshot.get("autoPassStackId", -1)) == -1, "A counterspell that can target the opponent creature must preserve its response window"): return false
		var creature: Dictionary = ui.snapshot.stack[0].duplicate(true)
		await ui.get_tree().create_timer(0.5).timeout
		if not check(ui.snapshot.stack.any(func(item): return item.id == creature.id) and not ui.incoming_effect.panel.visible, "A legal response pauses without a forced informational popup"): return false
		if scenario == "stack-free-response":
			ui._primary_action()
			if not await settle(): return false
			await capture("result")
			return check(ui.snapshot.players[1].zones.Battlefield.any(func(card): return card.name == "Grizzly Bears"), "Declining an available counter resolves the opponent creature")
		if not await tap("Island", 2) or not await cast("Counterspell"): return false
		if not ui.snapshot.asks.is_empty():
			if not await choose_named("Grizzly Bears"): return false
		if ui.snapshot.prompt.get("inputKind", "") == "InputSelectStackItems":
			ui._select_stack_card(creature)
			if not await wait_ready(): return false
			if ui.snapshot.prompt.okEnabled: ui._primary_action()
		if not await settle(): return false
		if not check(ui.snapshot.players[1].zones.Graveyard.any(func(card): return card.name == "Grizzly Bears") and not ui.snapshot.players[1].zones.Battlefield.any(func(card): return card.name == "Grizzly Bears"), "The retained window must allow Counterspell to actually counter the creature"): return false
	else:
		for index in range(60):
			if ui.snapshot.stack.is_empty(): break
			if not check(not ui.incoming_effect.panel.visible and not ui.modal.visible, "An unrelated creature needs no acknowledgment, even with an unrelated activated ability available"): return false
			await ui.get_tree().create_timer(0.1).timeout
		if not check(ui.snapshot.stack.is_empty() and ui.snapshot.players[1].zones.Battlefield.any(func(card): return card.name == "Grizzly Bears"), "The opponent creature must enter without a manual priority click"): return false
		if not check(ui.adapter.auto_priority_passes > 0, "The adapter must pass the routine item automatically"): return false
	await capture("result")
	return true

func greater_good() -> bool:
	var source := find_card("Greater Good", "Battlefield")
	if not check(not source.is_empty(), "Greater Good must be on the battlefield"): return false
	ui._click_card(source.id)
	var sacrificed := false
	var discarded := 0
	for index in range(80):
		if not await wait_ready(): return false
		var state: Dictionary = ui.snapshot
		var kind: String = state.prompt.get("inputKind", "")
		print("SCENARIO greater-good: ", kind, " asks=", state.asks.size(), " stack=", state.stack.size(), " phase=", state.game.phase, " msg=", state.prompt.get("message", ""), " modal=", ui.modal.visible, " rail=", ui.interaction_panel.panel.visible)
		var selectable: Array = state.prompt.get("selectable", []).map(func(id): return int(id))
		if not sacrificed and selectable.size() > 0 and kind != "InputPassPriority":
			var bears := find_card("Grizzly Bears", "Battlefield")
			if not check(not bears.is_empty() and selectable.has(int(bears.id)), "The sacrifice cost must offer Grizzly Bears: " + str(state.prompt)): return false
			await capture("sacrifice")
			ui._click_card(bears.id)
			sacrificed = true
			if not await wait_ready(): return false
			if ui.snapshot.prompt.get("okEnabled", false) and ui.snapshot.prompt.get("inputKind", "") != "InputPassPriority": ui._primary_action()
			continue
		if sacrificed and kind != "InputPassPriority":
			var hand_ids: Array = zone("Hand").map(func(card): return int(card.id))
			var choices: Array = selectable.filter(func(id): return hand_ids.has(id))
			if choices.size() > 0 and discarded == 0:
				await capture("discard")
				for id in choices.slice(0, 3):
					ui._click_card(id)
					if not await wait_ready(): return false
				discarded = 3
				# Hand picks stay local until the red Discard button sends them.
				if ui.hand_pick_panel.visible and not ui.hand_pick_confirm.disabled: ui.hand_pick_confirm.pressed.emit()
				elif ui.snapshot.prompt.get("okEnabled", false) and ui.snapshot.prompt.get("inputKind", "") != "InputPassPriority": ui._primary_action()
				continue
		if sacrificed and state.stack.is_empty() and state.asks.is_empty() and kind == "InputPassPriority" and not find_card("Grizzly Bears", "Graveyard").is_empty():
			await capture("result")
			if not check(state.game.phase == "Main 1", "Resolving Greater Good must leave you in Main 1, not skip to " + state.game.phase): return false
			return check(discarded == 3 and zone("Hand").size() == 3 and zone("Graveyard").size() == 4, "Greater Good must draw two and ask for three discards (hand %d, graveyard %d, discarded %d)" % [zone("Hand").size(), zone("Graveyard").size(), discarded])
		if not await step(): return false
	return check(false, "Greater Good did not finish")

func pass_turn() -> bool:
	if not check(int(ui.snapshot.game.activePlayer) == 0 and ui.snapshot.game.phase == "Main 1", "Pass turn starts in your own main phase"): return false
	# Prepared boards keep the setup overlays that swallow keys; drive the Space handler directly.
	ui._pass_turn()
	for index in range(150):
		await ui.get_tree().create_timer(0.1).timeout
		var state: Dictionary = ui.snapshot
		if int(state.game.turn) > 5 or int(state.game.activePlayer) != 0:
			await capture("result")
			return check(not find_card("Llanowar Elves").is_empty(), "Passing the turn must not play anything for you")
	return check(false, "Space did not pass the turn without further clicks: " + str(ui.snapshot.game) + " " + str(ui.snapshot.prompt))

## Reported bug: picking an ability in the "Choose ability" popup did nothing (Mind Stone stayed
## untapped, no mana). One click on the ability must activate it in Forge.
func mind_stone() -> bool:
	var stone := find_card("Mind Stone", "Battlefield")
	if not check(not stone.is_empty(), "Mind Stone missing from the prepared board"): return false
	ui._click_card(stone.id)
	if not await wait_ready(): return false
	if not check(not ui.snapshot.asks.is_empty(), "Clicking Mind Stone must ask which ability: " + str(ui.snapshot.prompt)): return false
	var options: Array = ui.snapshot.asks[0].get("options", [])
	var index := -1
	for i in range(options.size()):
		if str(options[i].get("label", "")).contains("Add {C}"): index = i
	var tether: Control = ui.interaction_panel.callout
	if not check(index >= 0 and tether.visible and not ui.modal.visible and index < tether.mode_buttons.size(), "The ability choice must be a tether on Mind Stone offering {C}: " + str(options)): return false
	await capture("choose-ability")
	tether.mode_buttons[index].pressed.emit() # Exactly what a player's click does; no Confirm.
	if not await wait_ready(): return false
	await capture("result")
	var after := find_card("Mind Stone", "Battlefield")
	if not check(after.get("tapped", false), "Choosing the ability must tap Mind Stone"): return false
	if not check(int(ui.snapshot.players[0].mana.get("C", 0)) == 1, "Choosing the ability must add {C}: " + str(ui.snapshot.players[0].mana)): return false
	return check(ui.snapshot.asks.is_empty(), "No further decision may remain after the ability resolves")

func run_scenario(table: Control, name: String) -> void:
	ui = table
	scenario = name
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 1000)
	deadline = Time.get_ticks_msec() + 115000
	if not await prepared(): return
	print("SCENARIO prepared: ", name, " ", ui.snapshot.players.map(func(player): return player.zones.Battlefield.map(func(card): return card.name)))
	await capture("prepared")
	var passed := false
	match name:
		"reported-interactions": passed = await reported_interactions()
		"wakanda": passed = await wakanda()
		"panther-claws": passed = await panther_claws()
		"hand-reveal": passed = await hand_reveal()
		"smith-artifact", "smith-empty": passed = await smith()
		"stack-auto", "stack-response", "stack-unaffordable", "stack-ability", "stack-free-response": passed = await stack_priority()
		"proliferate": passed = await proliferate()
		"triland": passed = await triland()
		"insights": passed = await insights()
		"blocking": passed = await blocking()
		"equipment": passed = await equipment()
		"tokens": passed = await tokens()
		"reanimate": passed = await reanimate()
		"protection": passed = await protection()
		"blink": passed = await blink()
		"combat": passed = await combat()
		"greater-good": passed = await greater_good()
		"pass-turn": passed = await pass_turn()
		_:
			# New scenarios need no registration: tests/scenarios/<name>.state + func <name_with_underscores>().
			var driver := name.replace("-", "_")
			if has_method(driver): passed = await call(driver)
			else: passed = check(false, "Scenario driver not implemented: " + driver)
	if not passed: return
	print("PASS: Godot live integration (prepared ", name, " card-combination scenario; UI choices and exact resulting game state)")
	ui.get_tree().quit()

## Dimir Aqueduct with no other land returns itself: the play is accepted (land drop used), the turn stays usable.
func aqueduct() -> bool:
	var land := find_card("Dimir Aqueduct")
	ui._click_card(land.id)
	if not await settle(): return false
	for index in range(30):
		await ui.get_tree().process_frame
	print("SCENARIO log: ", ui.snapshot.log.slice(0, 6))
	await capture("returned")
	if not check(zone("Hand").any(func(card): return card.id == land.id), "The Aqueduct returns itself to hand"): return false
	if not check(not ui.play_positions.has(land.id) and ui.cards[land.id].get_parent() == ui.hand_root, "The returned Aqueduct is back in the hand fan, not a stuck pending play"): return false
	if not check(ui.toast.text.contains("Dimir Aqueduct") and ui.toast.text.contains("returned"), "A clear message explains the Aqueduct returned and the land drop is used: " + ui.toast.text): return false
	if not await cast("Ornithopter"): return false
	if not await settle(): return false
	return check(zone("Battlefield").any(func(card): return card.name == "Ornithopter"), "The turn continues: another spell can still be cast")

func describe_ui(label: String) -> void:
	print("SCENARIO ", label, ": modal=", ui.modal.visible, " panel=", (ui.modal_panel.get_script().resource_path if is_instance_valid(ui.modal_panel) and ui.modal_panel.get_script() != null else str(ui.modal_panel)), " center=", ui.modal_center.visible, " return=", ui.decision_board_button.visible, " rail=", ui.interaction_panel.panel.visible, " asks=", ui.snapshot.asks.map(func(ask): return [ask.kind, ask.get("title", "")]), " input=", ui.snapshot.prompt.get("inputKind", ""), " msg=", str(ui.snapshot.prompt.get("message", "")).left(80))

## Bonders' Enclave's ability choice can be stepped away from and always found again.
func enclave() -> bool:
	var land := find_card("Bonders' Enclave", "Battlefield")
	ui._click_card(land.id)
	if not await wait_ready(): return false
	# The ability choice is a tether on the land, not a popup (Return to decision is covered by the
	# DecisionReview UI check for popups).
	if not check(not ui.modal.visible and ui.interaction_panel.callout.visible and ui.snapshot.asks.any(func(ask): return ask.get("title", "") == "Choose ability"), "Clicking Bonders' Enclave opens its ability choice as a tether"): return false
	await capture("tether")
	var hand := int(ui.snapshot.players[0].handCount)
	if not await choose_named("Draw"): return false
	for index in range(40):
		if str(ui.snapshot.prompt.get("inputKind", "")).begins_with("InputPayMana") and ui.snapshot.prompt.okEnabled:
			if ui.modal_panel is ManaPaymentDialog and ui.modal.visible: ui.modal_panel.sources_button.pressed.emit()
			else:
				var swamp: Array = zone("Battlefield").filter(func(card): return card.name == "Swamp" and not card.get("tapped", false))
				if not check(not swamp.is_empty(), "A Swamp pays the Enclave's {3}"): return false
				ui._click_card(swamp[0].id)
			if not await wait_ready(): return false
		elif int(ui.snapshot.players[0].handCount) > hand or not ui.snapshot.stack.is_empty(): break
		await ui.get_tree().create_timer(0.1).timeout
	if not await settle(): return false
	return check(int(ui.snapshot.players[0].handCount) == hand + 1, "The returned decision still activates the draw ability")

## Forge's priority scan marks what is castable now: affordable hand cards, the commander and flashback.
func playable() -> bool:
	for index in range(20): await ui.get_tree().process_frame
	var flag := func(name: String, zone_name: String) -> bool:
		for card in ui.snapshot.players[0].zones[zone_name]:
			if card.name == name: return ui._playable(card, 0, zone_name)
		return false
	print("SCENARIO playable: ", ["Ornithopter", "Mind Stone", "Craw Wurm"].map(func(name): return [name, flag.call(name, "Hand")]), " souls=", flag.call("Lingering Souls", "Graveyard"), " commander=", flag.call("Gravecrawler", "Command"))
	if not check(flag.call("Ornithopter", "Hand") and flag.call("Mind Stone", "Hand"), "Affordable hand cards are playable"): return false
	if not check(not flag.call("Craw Wurm", "Hand"), "A six-mana creature with two Swamps is not playable"): return false
	if not check(flag.call("Lingering Souls", "Graveyard"), "A flashback card you can afford is playable from the graveyard"): return false
	if not check(flag.call("Gravecrawler", "Command") and ui.hud_values[0].zones.Command.playable, "Your castable commander lights the command zone"): return false
	var stone: Control = ui.cards[find_card("Mind Stone").id]
	if not check(stone.data.get("playable", false), "The hand card view carries the playable glow"): return false
	await capture("hand")
	if not check(not stone.data.get("ready", false), "Nothing is teal before any mana is tapped"): return false
	# Teal once the tapped mana pays for it: one Swamp pays Gravecrawler ({B}), not Mind Stone ({2}).
	if not await tap("Swamp", 1): return false
	for index in range(10): await ui.get_tree().process_frame
	var ready := func(name: String) -> bool:
		for zone_name in ["Hand", "Command"]:
			for card in ui.snapshot.players[0].zones[zone_name]:
				if card.name == name: return ui._playable(card, 0, zone_name) and ui._ready_now(card, zone_name)
		return false
	if not check(ready.call("Gravecrawler") and ui.hud_values[0].zones.Command.castable_now and not ready.call("Mind Stone") and not ready.call("Ornithopter"), "One floating B: the commander is ready, Mind Stone isn't, free spells stay purple"): return false
	if not await tap("Swamp", 1): return false
	for index in range(10): await ui.get_tree().process_frame
	if not check(ready.call("Mind Stone"), "Two floating mana: Mind Stone turns teal"): return false
	if not check(stone.data.get("ready", false), "The hand card view carries the teal glow"): return false
	await capture("ready")
	# Spend the mana: nothing that costs mana stays highlighted.
	if not await cast("Mind Stone"): return false
	if not await settle(): return false
	for index in range(20): await ui.get_tree().process_frame
	return check(not flag.call("Lingering Souls", "Graveyard") and flag.call("Ornithopter", "Hand"), "After spending the mana only the free spell stays playable")

## A board wipe is news for this seat only when it can reach one of its permanents.
func wipe_events() -> Array:
	return ui.snapshot.get("targetedEffects", []).filter(func(event): return event.get("kind", "") == "massRemoval")

func wrath_hits() -> bool:
	var events := wipe_events()
	print("SCENARIO wipe events: ", events.map(func(event): return event.get("source", {}).get("name", "?")))
	if not check(events.size() == 1 and events[0].get("source", {}).get("name", "") == "Wrath of God", "A wipe that reaches your creature is announced with its real source card"): return false
	# With no possible response it still waits on you: the spell sits in the middle of the table with a
	# branch to each creature it will destroy, before anything dies.
	for index in range(20): await ui.get_tree().process_frame
	await ui.get_tree().create_timer(0.6).timeout
	if not check(not ui.snapshot.stack.is_empty() and int(ui.snapshot.get("autoPassStackId", -1)) != int(ui.snapshot.stack[0].id), "The wipe must wait for this seat even without a response"): return false
	var effect: Control = ui.incoming_effect
	if not check(effect.wipe_card.visible and not effect.panel.visible, "The wipe shows as its card on the table, not the decision popup"): return false
	var reached: Array = effect._wipe_views()
	if not check(reached.size() >= 2, "Branches reach both Grizzly Bears: " + str(events[0].get("affected", []))): return false
	if not check(zone("Battlefield").any(func(card): return card.name == "Grizzly Bears"), "Nothing is destroyed before you see it"): return false
	await capture("wipe")
	effect.wipe_resolve.pressed.emit()
	for index in range(30):
		if not await wait_ready(): return false
		if not zone("Battlefield").any(func(card): return card.name == "Grizzly Bears"): break
		await ui.get_tree().create_timer(0.2).timeout
	if not check(not zone("Battlefield").any(func(card): return card.name == "Grizzly Bears"), "Resolve lets Forge resolve the wipe"): return false
	return check(not effect.wipe_card.visible, "The wipe overlay closes once it resolves")

func wrath_misses() -> bool:
	return check(wipe_events().is_empty(), "A wipe that cannot reach any of your permanents is not announced to you: " + str(wipe_events()))

## "Sacrifice Evolving Wilds?" attaches to the card as a terminal callout and answers with Y.
func wilds() -> bool:
	var wilds_card := find_card("Evolving Wilds", "Battlefield")
	ui._click_card(wilds_card.id)
	if not await wait_ready(): return false
	for index in range(10): await ui.get_tree().process_frame
	var panel: Control = ui.interaction_panel
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputConfirm" and int(ui.snapshot.prompt.get("sourceCard", {}).get("id", -1)) == int(wilds_card.id), "Forge's sacrifice confirmation carries its card: " + JSON.stringify(ui.snapshot.prompt).left(300)): return false
	if not check(panel.callout.visible and not panel.panel.visible, "The confirmation is a callout on the card, not the top banner"): return false
	var card_rect: Rect2 = panel._card_rect(ui.cards[wilds_card.id])
	var box := Rect2(panel.callout.position, panel.callout.size)
	if not check(not box.intersects(card_rect) and box.grow(panel.CALLOUT_GAP + 4).intersects(card_rect), "The callout sits right beside the card without covering it: " + str([box, card_rect])): return false
	if not check(panel.callout.title.text.contains("EVOLVING WILDS") and panel.callout.yes_button.text.begins_with("[Y]"), "The callout names the card and offers Y/N keys"): return false
	await capture("callout")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_Y
	panel._unhandled_key_input(key)
	if not await wait_ready(): return false
	if not check(not panel.callout.visible or ui.snapshot.prompt.get("inputKind", "") != "InputConfirm", "Y answers the confirmation"): return false
	for index in range(20): await ui.get_tree().process_frame
	print("SCENARIO search: input=", ui.snapshot.prompt.get("inputKind", ""), " asks=", ui.snapshot.asks.map(func(ask): return [ask.kind, ask.get("title", "")]), " modal=", (ui.modal_panel.get_script().resource_path if is_instance_valid(ui.modal_panel) else "none"), " banner=", panel.panel.visible, " callout=", panel.callout.visible)
	if not await resolve_to_choice(): return false
	var search: Control = ui.modal_panel
	if not check(search is SelectionDialog and search.carousel_mode and search.carousel.visible, "A library search must open the card carousel"): return false
	var island := -1
	for r in range(search.groups.size()):
		if search.options[search.groups[r][0]].get("name", "") == "Island": island = r
	if not check(island >= 0, "The search must offer Island"): return false
	search.carousel.focus_requested.emit(island) # As the wheel or an arrow key would.
	await ui.get_tree().create_timer(0.8).timeout
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = search.carousel.size * 0.5 + Vector2(0, 10)
	click.pressed = true
	search.carousel._gui_input(click)
	click.pressed = false
	search.carousel._gui_input(click)
	for index in range(10): await ui.get_tree().process_frame
	if not check(search.staged.size() == 1 and search.options[search.staged[0]].name == "Island", "Clicking the middle card must mark Island: " + str(search.staged)): return false
	if not check(ui.snapshot.prompt.get("chosen", []).is_empty() and ui.modal.visible and not search.confirm_button.disabled, "Marking a card must send nothing to Forge until OK"): return false
	await capture("search")
	search.confirm_button.pressed.emit()
	if not await settle(): return false
	return check(not find_card("Evolving Wilds", "Graveyard").is_empty() and zone("Battlefield").filter(func(card): return card.name == "Island").size() == 2, "Evolving Wilds was sacrificed and fetched an Island")

## Discarding happens on your own hand: no card gallery, the table dims, a click marks the card red
## through Forge's own selection, and the prompt confirms exactly those cards.
func discard() -> bool:
	if not await tap("Mountain") or not await cast("Faithless Looting"): return false
	for index in range(40):
		if not await wait_ready(): return false
		if ui.snapshot.prompt.get("inputKind", "") == "InputSelectCardsFromList": break
		if not await step(): return false
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputSelectCardsFromList", "Faithless Looting must ask for a discard: " + str(ui.snapshot.prompt)): return false
	if not check(not (ui.modal.visible and ui.modal_panel is SelectionDialog), "Discarding must not open the card gallery"): return false
	if not check(ui.hand_pick_panel.visible and ui.hand_pick_shade.visible and not ui.interaction_panel.panel.visible, "The discard prompt must show over a dimmed table"): return false
	if not check(ui.hand_pick_confirm.disabled, "Nothing may be confirmed before a card is picked"): return false
	var picks: Array = zone("Hand").slice(0, 2)
	ui._click_card(picks[0].id)
	if not await wait_ready(): return false
	if not check(int(ui.cards[picks[0].id].data.get("pickMark", 0)) == 2, "A clicked hand card must be marked for discard: " + str(ui.snapshot.prompt.get("chosen", []))): return false
	ui._click_card(picks[1].id)
	if not await wait_ready(): return false
	# Both picks stay pending until the red Discard button: a branch runs to each picked card.
	if not check(ui.hand_pick_panel.visible and zone("Hand").any(func(card): return card.id == picks[1].id), "Picking never discards by itself; the red button does"): return false
	if not check(ui.hand_pick_lines.visible and ui.hand_pick_since.has(int(picks[0].id)) and ui.hand_pick_since.has(int(picks[1].id)), "A branch runs to each picked card: " + str(ui.hand_pick_since.keys())): return false
	if not check(ui.hand_pick_red and not ui.hand_pick_confirm.disabled, "Discard is the red confirm button, enabled once two cards are picked"): return false
	await ui.get_tree().create_timer(0.6).timeout
	await capture("picked")
	ui.hand_pick_confirm.pressed.emit()
	if not await settle(): return false
	var graveyard: Array = zone("Graveyard").map(func(card): return card.id)
	if not check(graveyard.has(picks[0].id) and graveyard.has(picks[1].id), "Forge must discard the two clicked cards: " + str(zone("Graveyard").map(func(card): return card.name))): return false
	return check(not ui.hand_pick_panel.visible and not ui.hand_pick_shade.visible, "The table must return to normal after discarding")

## A two-card library search: marks stay local, OK sends each exact instance to Forge in turn.
func cultivate() -> bool:
	if not await tap("Forest", 3) or not await cast("Cultivate"): return false
	if not await resolve_to_choice(): return false
	var search: Control = ui.modal_panel
	if not check(search is SelectionDialog and search.carousel_mode, "Cultivate's search must open the carousel"): return false
	for name in ["Island", "Swamp"]:
		for r in range(search.groups.size()):
			if search.options[search.groups[r][0]].get("name", "") == name: search._stage_group(r)
	if not check(search.staged.size() == 2 and ui.snapshot.prompt.get("chosen", []).is_empty(), "Two marks must stay local until OK: " + str(search.staged)): return false
	if not check(search.carousel.mark_labels.has("✓ 1 OF 2") and search.carousel.mark_labels.has("✓ 2 OF 2"), "Marks count your picks against the two allowed, not the copies: " + str(search.carousel.mark_labels)): return false
	# Right-clicking the middle card (Swamp, focused by the last mark) removes its mark; left-click adds it back.
	await ui.get_tree().create_timer(0.8).timeout
	var click := InputEventMouseButton.new()
	click.position = search.carousel.size * 0.5 + Vector2(0, 10)
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	search.carousel._gui_input(click)
	if not check(search.staged.size() == 1 and search.options[search.staged[0]].name == "Island", "Right-click must remove the Swamp mark: " + str(search.staged)): return false
	click.button_index = MOUSE_BUTTON_LEFT
	search.carousel._gui_input(click)
	click.pressed = false
	search.carousel._gui_input(click)
	if not check(search.staged.size() == 2, "Left-click must mark the Swamp again"): return false
	await capture("marked")
	search.confirm_button.pressed.emit()
	if not await settle(): return false
	var found: Array = zone("Battlefield").map(func(card): return card.name) + zone("Hand").map(func(card): return card.name)
	return check(found.has("Island") and found.has("Swamp") and ui.snapshot.players[0].libraryCount == 8, "Forge must fetch exactly the marked Island and Swamp: " + str(found))

## Four of your own abilities trigger at once: the stack builder orders them, nothing is sent until
## Confirm, and Forge stacks them so the top row resolves first.
func triggers() -> bool:
	if not await tap("Forest", 2) or not await cast("Elvish Visionary"): return false
	for index in range(40):
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "order": break
		if not await step(): return false
	if not check(not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "order", "Simultaneous triggers must ask for an order: " + str(ui.snapshot.asks)): return false
	var panel: Control = ui.modal_panel
	if not check(panel.get("order_stack") != null, "The order must open as the stack builder"): return false
	print("SCENARIO order options: ", ui.snapshot.asks[0].options.map(func(option): return option.label))
	await capture("stack")
	var wanted: Array[int] = panel.order_stack.order.duplicate()
	wanted.reverse()
	panel.order_stack.set_order(wanted)
	if not await wait_ready(): return false
	if not check(not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "order", "Reordering must not answer Forge"): return false
	var answers: Array = []
	panel.answered.connect(func(_id, value): answers.append(value))
	panel.confirm_button.pressed.emit()
	if not check(answers == [wanted], "Confirm must send the whole pile, top first: %s vs %s" % [answers, wanted]): return false
	if not await wait_ready(): return false
	return check(not ui.snapshot.asks.any(func(ask): return ask.kind == "order"), "Forge must accept the order and close the question")

## "Choose one or more" modes hang off the card as one callout; picks stay local until Confirm,
## then the bridge feeds every pick to Forge's one-at-a-time mode prompts.
func concord() -> bool:
	for index in range(40):
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].get("modeChoice", false): break
		if not await step(): return false
	if not check(not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].get("modeChoice", false), "Concord must ask for all its modes at once: " + str(ui.snapshot.asks)): return false
	var callout: Control = ui.interaction_panel.callout
	if not check(callout.visible and not ui.modal.visible, "The modes must attach to the card, not open a popup"): return false
	if not check(callout.mode_buttons.size() == 3 and callout.yes_button.disabled, "Three modes, nothing confirmable before a pick"): return false
	var hand_before: int = zone("Hand").size()
	callout.mode_buttons[1].pressed.emit()
	callout.mode_buttons[2].pressed.emit()
	await capture("modes")
	if not await wait_ready(): return false
	if not check(ui.snapshot.asks.size() == 1 and ui.snapshot.asks[0].get("modeChoice", false), "Picking modes must not answer Forge"): return false
	callout.yes_button.pressed.emit()
	for index in range(40):
		if not await wait_ready(): return false
		if zone("Battlefield").any(func(card): return str(card.name).contains("Spirit")): break
		if not await step(): return false
	if not check(zone("Battlefield").any(func(card): return str(card.name).contains("Spirit")), "Both picked modes must resolve: a Spirit token"): return false
	return check(zone("Hand").size() > hand_before, "… and a drawn card")

## Only threats with an answer in hand: the wipe waits, View battlefield lets you cast Heroic
## Intervention on top of it, and your creatures survive while everyone else's die.
func wrath_response() -> bool:
	ui.ui_layout.stack_mode = 2.0 # Only threats, for this run only (not saved).
	ui.adapter.stack_mode = 2
	ui.adapter.auto_resolve_all = true
	var effect: Control = ui.incoming_effect
	for index in range(30): await ui.get_tree().process_frame
	await ui.get_tree().create_timer(0.6).timeout
	if not check(not ui.snapshot.stack.is_empty() and effect.wipe_card.visible, "Only threats still stops for a wipe you can answer"): return false
	await capture("wipe")
	effect.respond() # View battlefield
	if not await tap("Forest", 2) or not await cast("Heroic Intervention"): return false
	for index in range(20):
		if not await wait_ready(): return false
		if ui.snapshot.stack.size() >= 2: break
		await ui.get_tree().create_timer(0.2).timeout
	print("SCENARIO stack after casting: ", ui.snapshot.stack.map(func(item): return item.get("sourceName", "?")))
	if not check(ui.snapshot.stack.size() >= 2, "Heroic Intervention goes on the stack above the wipe"): return false
	await capture("responded")
	# Pass priority until Intervention resolves; then the wipe is back on top.
	for index in range(30):
		if not await wait_ready(): return false
		if ui.snapshot.stack.size() <= 1: break
		if not await step(): return false
	await ui.get_tree().create_timer(0.8).timeout
	print("SCENARIO wipe back on top: stack=", ui.snapshot.stack.map(func(item): return item.get("sourceName", "?")), " overlay=", effect.wipe_card.visible, " autoPass=", ui.snapshot.get("autoPassStackId", -1), " input=", ui.snapshot.prompt.get("inputKind", ""), " responding=", effect.responding)
	await capture("wipe-again")
	for index in range(30):
		if not await wait_ready(): return false
		if ui.snapshot.stack.is_empty(): break
		if effect.wipe_card.visible: effect.wipe_resolve.pressed.emit()
		elif not await step(): return false
		await ui.get_tree().create_timer(0.3).timeout
	var mine: Array = zone("Battlefield").filter(func(card): return card.name in ["Grizzly Bears", "Llanowar Elves"])
	var theirs: Array = ui.snapshot.players.slice(1).map(func(player): return player.zones.Battlefield.filter(func(card): return card.name in ["Grizzly Bears", "Goblin Guide"]).size())
	print("SCENARIO survivors: mine=", mine.map(func(card): return card.name), " theirs=", theirs)
	return check(mine.size() == 2 and theirs == [0, 0], "Your creatures survive (indestructible), everyone else's die")

## Counterspell over a wipe: the target choice hangs off Counterspell and names the spell it answers.
func wrath_counter() -> bool:
	var effect: Control = ui.incoming_effect
	for index in range(30): await ui.get_tree().process_frame
	await ui.get_tree().create_timer(0.6).timeout
	if not check(effect.wipe_card.visible, "The wipe waits on you"): return false
	effect.respond()
	if not await tap("Island", 2) or not await cast("Counterspell"): return false
	for index in range(10):
		if not await wait_ready(): return false
	await ui.get_tree().create_timer(0.5).timeout
	var answer: Control = ui.response_target
	if not check(answer.visible and not ui.modal.visible, "Counterspell's target hangs off Counterspell, not a popup: " + JSON.stringify(ui.snapshot.asks).left(400)): return false
	if not check(answer.spell_card.data.get("name", "") == "Counterspell" and answer.target_view.data.get("name", "") == "Wrath of God", "Card A (Counterspell) answers card B (Wrath of God)"): return false
	if not check(answer.confirm.text.contains("COUNTERSPELL") and answer.confirm.text.contains("WRATH OF GOD"), "The confirm names both cards: " + answer.confirm.text): return false
	if not check(answer.stack_rect.call(int(ui.snapshot.asks[0].options[0].stackId)).has_area(), "The branch reaches the Wrath on the stack"): return false
	await ui.get_tree().create_timer(0.6).timeout
	await capture("target")
	answer.confirm.pressed.emit()
	for index in range(40):
		if not await wait_ready(): return false
		if ui.snapshot.stack.is_empty() and ui.snapshot.asks.is_empty(): break
		if not ui.snapshot.asks.is_empty(): return check(false, "Unexpected decision: " + JSON.stringify(ui.snapshot.asks).left(300))
		if not await step(): return false
	if not check(not answer.visible, "The callout closes once answered"): return false
	var creatures: Array = []
	for player in ui.snapshot.players: creatures.append_array(player.zones.Battlefield.filter(func(card): return card.name in ["Grizzly Bears", "Llanowar Elves", "Goblin Guide"]))
	return check(creatures.size() == 4, "Countered: every creature survives: " + str(creatures.map(func(card): return card.name)))

## Only threats: an opponent's ability aimed at your creature (Aether Spellbomb's bounce) waits for you
## even with no response, so you see it before your creature leaves, not after.
func spellbomb() -> bool:
	ui.ui_layout.stack_mode = 2.0 # Only threats, for this run only.
	ui.adapter.stack_mode = 2
	ui.adapter.auto_resolve_all = true
	var effect: Control = ui.incoming_effect
	var warned := false
	for index in range(200):
		if not await wait_ready(): return false
		var top: Dictionary = ui.snapshot.stack[0] if not ui.snapshot.stack.is_empty() else {}
		if str(top.get("sourceName", "")) == "Aether Spellbomb":
			for wait in range(20): await ui.get_tree().process_frame
			print("SCENARIO spellbomb waiting: autoPass=", ui.snapshot.get("autoPassStackId", -1), " popup=", effect.showing(), " angel=", find_card("Serra Angel", "Battlefield").is_empty() == false)
			if effect.showing() and int(effect.active.get("stackId", -1)) == int(top.id) and not find_card("Serra Angel", "Battlefield").is_empty():
				var angel := find_card("Serra Angel", "Battlefield")
				if not check(effect.wipe_card.visible and not effect.panel.visible and effect.wipe_heading.text == "TARGETED EFFECT", "The targeted effect shows as its card on the table, like a wipe"): return false
				if not check(effect._wipe_views().has(ui.cards.get(int(angel.id))), "A branch runs from Aether Spellbomb to your Serra Angel"): return false
				warned = true
				await ui.get_tree().create_timer(0.6).timeout
				await capture("warned")
				effect.dismiss() # I accept
		if not find_card("Serra Angel", "Hand").is_empty() or (find_card("Serra Angel", "Battlefield").is_empty() and index > 5): break
		await ui.get_tree().create_timer(0.1).timeout
	if not check(not find_card("Serra Angel", "Hand").is_empty(), "The fixture needs the AI to bounce Serra Angel"): return false
	return check(warned, "The bounce aimed at your creature must be shown before it resolves, while it waits for you")

## Your commander dies: Forge's "move it to the command zone?" is a tether from the commander, not a banner.
func commander_zone() -> bool:
	var effect: Control = ui.incoming_effect
	for index in range(40):
		if not await wait_ready(): return false
		if effect.showing(): effect.dismiss() # I accept the Bolt
		var kind: String = ui.snapshot.prompt.get("inputKind", "")
		if not ui.snapshot.asks.is_empty() or kind == "InputConfirm": break
		await ui.get_tree().create_timer(0.2).timeout
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputConfirm" and ui.snapshot.prompt.get("sourceCard", {}).get("name", "") == "Gravecrawler", "Forge asks about moving the commander: " + JSON.stringify(ui.snapshot.prompt).left(300)): return false
	for index in range(20): await ui.get_tree().process_frame
	var panel: Control = ui.interaction_panel
	if not check(panel.callout.visible and not panel.panel.visible, "The commander question is a tether, not the top banner"): return false
	if not check(panel.callout_card == ui.hud_values[0].zones.Graveyard, "It hangs off your graveyard, where the commander is now"): return false
	if not check(panel.callout.face.visible and panel.callout.face.data.get("name", "") == "Gravecrawler", "The tether shows the commander's card"): return false
	if not check(panel.callout.yes_button.text.contains("Command zone"), "Yes reads as moving it to the command zone: " + panel.callout.yes_button.text): return false
	await capture("ask")
	panel.callout.yes_button.pressed.emit()
	for index in range(30):
		if not await wait_ready(): return false
		if ui.snapshot.players[0].zones.get("Command", []).any(func(card): return card.name == "Gravecrawler"): break
		await ui.get_tree().create_timer(0.2).timeout
	return check(ui.snapshot.players[0].zones.get("Command", []).any(func(card): return card.name == "Gravecrawler"), "Yes puts the commander in the command zone")

## Five floating mana, then a six-mana spell with improvise: what the screen says you still owe must
## match Forge (one more), not the printed six.
func statuary() -> bool:
	if not await tap("Forest", 5): return false
	print("SCENARIO pool before cast: ", ui.snapshot.players[0].mana)
	if not await cast("Craw Wurm"): return false
	for index in range(20): await ui.get_tree().process_frame
	var panel: Control = ui.interaction_panel
	print("SCENARIO paying: ", panel.message.text.replace("
", " | "), " selectable=", ui.snapshot.prompt.get("selectable", []))
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputSelectCardsForConvokeOrImprovise", "Craw Wurm offers improvise: " + str(ui.snapshot.prompt.get("inputKind", ""))): return false
	if not check(panel.message.text.contains("{1}") and not panel.message.text.contains("{4}{G}{G}"), "With five floating green, the rail must say one more mana is owed, not the printed cost: " + panel.message.text): return false
	var artifacts: Array = zone("Battlefield").filter(func(card): return card.name in ["Ornithopter", "Mind Stone"]).map(func(card): return int(card.id))
	var offered: Array = ui.snapshot.prompt.get("selectable", []).map(func(id): return int(id))
	if not check(artifacts.all(func(id): return offered.has(id)), "The artifacts you can tap for improvise are offered (outlined): " + str(offered)): return false
	await capture("paying")
	ui._click_card(artifacts[0])
	if not await wait_ready(): return false
	for index in range(30):
		if not await wait_ready(): return false
		if zone("Battlefield").any(func(card): return card.name == "Craw Wurm"): break
		if ui.snapshot.prompt.get("okEnabled", false) and ui.snapshot.asks.is_empty() and str(ui.snapshot.prompt.get("inputKind", "")) != "InputPassPriority": ui._intent("ok")
		elif not ui.snapshot.stack.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": ui._intent("ok")
		await ui.get_tree().create_timer(0.2).timeout
	return check(zone("Battlefield").any(func(card): return card.name == "Craw Wurm"), "Five floating green plus one improvised artifact cast Craw Wurm")

## Card-list tethers: Izzet Boilerworks' "return a land" pick and Explorer's Scope's look both hang
## off their source card instead of the search window / popup.
func scope() -> bool:
	var tether: Control = ui.interaction_panel.callout
	var works := find_card("Izzet Boilerworks")
	ui._click_card(works.id)
	for index in range(30):
		if not await wait_ready(): return false
		if tether.visible and tether.card_mode: break
		if not ui.snapshot.stack.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": ui._intent("ok")
		await ui.get_tree().create_timer(0.2).timeout
	for index in range(10): await ui.get_tree().process_frame
	if not check(tether.visible and tether.card_mode and tether.card_pick and not ui.modal.visible, "Boilerworks' land choice is a tether, not the search window"): return false
	if not check(ui.interaction_panel.callout_card == ui.cards.get(int(find_card("Izzet Boilerworks", "Battlefield").get("id", -1))), "It hangs off Izzet Boilerworks"): return false
	var names: Array = tether.card_list.map(func(card): return card.name)
	if not check(names.size() == 3 and names.has("Island"), "All three lands are offered: " + str(names)): return false
	tether._focus_card(names.find("Island"))
	if not check(tether.yes_button.text.contains("Return") and tether.yes_button.text.contains("Island"), "Confirm names the choice: " + tether.yes_button.text): return false
	await ui.get_tree().create_timer(0.4).timeout
	await capture("boilerworks")
	tether.yes_button.pressed.emit()
	for index in range(30):
		if not await wait_ready(): return false
		if zone("Hand").any(func(card): return card.name == "Island"): break
		await ui.get_tree().create_timer(0.2).timeout
	if not check(zone("Hand").any(func(card): return card.name == "Island"), "The chosen Island returns to your hand"): return false
	# Explorer's Scope: attack, then the look at your top card hangs off the Scope.
	var bears := find_card("Grizzly Bears", "Battlefield")
	for index in range(30):
		if ui.snapshot.prompt.get("inputKind", "") == "InputAttack": break
		if not await step() or not await wait_ready(): return false
	ui._click_card(bears.id)
	ui._choose_player(1)
	if not await wait_ready(): return false
	ui._intent("ok")
	for index in range(40):
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "message": break
		if not ui.snapshot.stack.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": ui._intent("ok")
		await ui.get_tree().create_timer(0.2).timeout
	for index in range(10): await ui.get_tree().process_frame
	var scope_card := find_card("Explorer's Scope", "Battlefield")
	if not check(tether.visible and tether.card_mode and not tether.card_pick and not ui.modal.visible, "The look is a tether, not a popup"): return false
	if not check(ui.interaction_panel.callout_card == ui.cards.get(int(scope_card.id)) and tether.face.data.get("name", "") == "Forest", "It hangs off Explorer's Scope and shows the Forest"): return false
	await capture("scope")
	tether.yes_button.pressed.emit()
	if not await wait_ready(): return false
	for index in range(10): await ui.get_tree().process_frame
	return check(ui.snapshot.asks.is_empty() or ui.snapshot.asks[0].kind != "message", "OK acknowledges the look")

## Sword of the Animist's optional search: the tether's Yes must be usable (it was stuck disabled
## while the rail's Yes worked).
func animist() -> bool:
	# A mana-color tether first (its rows answer on click, so it hides Yes) — the real-game sequence.
	var citadel := find_card("Sandsteppe Citadel", "Battlefield")
	ui._click_card(citadel.id)
	for index in range(20):
		if not await wait_ready(): return false
		if ui.interaction_panel.callout.visible and not ui.interaction_panel.callout.mode_buttons.is_empty(): break
		await ui.get_tree().create_timer(0.1).timeout
	ui.interaction_panel.callout.mode_buttons[0].pressed.emit()
	if not await wait_ready(): return false
	var bears := find_card("Grizzly Bears", "Battlefield")
	for index in range(30):
		if ui.snapshot.prompt.get("inputKind", "") == "InputAttack": break
		if not await step() or not await wait_ready(): return false
	ui._click_card(bears.id)
	ui._choose_player(1)
	if not await wait_ready(): return false
	ui._intent("ok")
	var tether: Control = ui.interaction_panel.callout
	for index in range(40):
		if not await wait_ready(): return false
		if tether.visible or ui.snapshot.prompt.get("inputKind", "") == "InputConfirm" or not ui.snapshot.asks.is_empty(): break
		if not ui.snapshot.stack.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": ui._intent("ok")
		await ui.get_tree().create_timer(0.2).timeout
	for index in range(10): await ui.get_tree().process_frame
	print("SCENARIO animist prompt: ", JSON.stringify(ui.snapshot.prompt).left(500))
	print("SCENARIO animist asks: ", JSON.stringify(ui.snapshot.asks).left(500))
	print("SCENARIO animist ui: tether=", tether.visible, " yes=", tether.yes_button.text, " disabled=", tether.yes_button.disabled, " no_disabled=", tether.no_button.disabled, " rail=", ui.interaction_panel.panel.visible, " connectionReady=", ui.snapshot.get("connectionReady", false), " pendingDraws=", ui.snapshot.get("pendingDraws", []))
	await capture("ask")
	if not check(tether.visible and tether.yes_button.visible and not tether.yes_button.disabled, "The tether's Yes must be visible and clickable"): return false
	tether.yes_button.pressed.emit()
	for index in range(30):
		if not await wait_ready(): return false
		if ui.modal.visible or not ui.snapshot.asks.is_empty() or str(ui.snapshot.prompt.get("inputKind", "")).begins_with("InputSelect"): break
		await ui.get_tree().create_timer(0.2).timeout
	return check(ui.modal.visible or not ui.snapshot.asks.is_empty() or str(ui.snapshot.prompt.get("inputKind", "")).begins_with("InputSelect"), "Yes starts the land search")

## Your commander is bounced: Forge's replacement question ("put it in the command zone instead?")
## is a tether from the commander, not the top banner.
func commander_bounce() -> bool:
	var effect: Control = ui.incoming_effect
	for index in range(40):
		if not await wait_ready(): return false
		if effect.showing(): effect.dismiss() # I accept the Unsummon
		if not ui.snapshot.asks.is_empty() or ui.snapshot.prompt.get("inputKind", "") == "InputConfirm": break
		await ui.get_tree().create_timer(0.2).timeout
	for index in range(10): await ui.get_tree().process_frame
	var panel: Control = ui.interaction_panel
	var commander := find_card("Gravecrawler", "Battlefield")
	if not check(not commander.is_empty() and panel.callout.visible and not panel.panel.visible, "The commander replacement is a tether, not the top banner"): return false
	if not check(panel.callout_card == ui.cards.get(int(commander.id)), "It hangs off the commander itself"): return false
	if not check(panel.callout.yes_button.text.contains("Command zone") and panel.callout.line.text.contains("gravecrawler"), "It asks plainly about moving the commander: " + panel.callout.line.text): return false
	await capture("ask")
	panel.callout.yes_button.pressed.emit()
	for index in range(30):
		if not await wait_ready(): return false
		if ui.snapshot.players[0].zones.get("Command", []).any(func(card): return card.name == "Gravecrawler"): break
		await ui.get_tree().create_timer(0.2).timeout
	return check(ui.snapshot.players[0].zones.get("Command", []).any(func(card): return card.name == "Gravecrawler"), "Yes puts the commander in the command zone instead of your hand")

## Timing probe (not a pass/fail check): how long the engine takes between your decisions, from
## your Main 1 to Main 2 and through the next (bot) turn. It answers on the first frame a new
## decision appears (no settle waits), so every gap is engine, bridge and transport time.
func phase_timing() -> bool:
	var log := []
	var started := Time.get_ticks_msec()
	var last := started
	var start_turn := int(ui.snapshot.game.turn)
	var my_turn_done := -1
	var step_seen := ""
	var steps := []
	var acted_on := ""
	while Time.get_ticks_msec() - started < 60000:
		await ui.get_tree().process_frame
		var state: Dictionary = ui.snapshot
		if state.is_empty() or not state.get("connectionReady", false): continue
		var game: Dictionary = state.get("game", {})
		var label := "T%d p%d %s" % [int(game.get("turn", 0)), int(game.get("activePlayer", -1)), str(game.get("phase", ""))]
		if label != step_seen:
			steps.append([Time.get_ticks_msec() - started, label])
			step_seen = label
		if int(game.get("turn", 0)) >= start_turn + 2 or game.get("gameOver", false): break
		var kind: String = state.prompt.get("inputKind", "")
		if my_turn_done < 0 and int(game.get("activePlayer", -1)) == 0 and str(game.get("phase", "")) == "Main 2" and kind == "InputPassPriority":
			my_turn_done = Time.get_ticks_msec() - started
		var key := "%s|%s|%d|%s|%s" % [label, kind, state.stack.size(), str(state.asks.map(func(ask): return ask.id)), str(state.prompt.get("message", "")).left(40)]
		if key == acted_on: continue
		var acted := true
		if ui.incoming_effect.showing(): ui.incoming_effect.dismiss()
		elif not state.asks.is_empty(): submit_choice()
		elif kind in ["InputPassPriority", "InputAttack", "InputBlock"] and state.prompt.get("okEnabled", false): ui._intent("ok")
		else: acted = false
		if acted:
			var now := Time.get_ticks_msec()
			log.append([now - last, label, kind if state.asks.is_empty() else "ask:" + str(state.asks[0].kind), state.stack.size()])
			last = now
			acted_on = key
	var total := Time.get_ticks_msec() - started
	print("SCENARIO timing: my M1 -> M2 = %d ms; through the next turn = %d ms; decisions = %d" % [my_turn_done, total, log.size()])
	for entry in log: print("SCENARIO wait %5d ms before deciding at %s (%s, stack %d)" % entry)
	for entry in steps: print("SCENARIO step at %6d ms: %s" % entry)
	# Space from a fresh Main 1 on the next turn of yours is not reachable quickly; instead time Space
	# from this bot turn's end back around: press Space now and wait for your next decision.
	var space_started := Time.get_ticks_msec()
	ui._pass_turn()
	var space_ms := -1
	var space_label := ""
	while Time.get_ticks_msec() - space_started < 30000:
		await ui.get_tree().process_frame
		var state: Dictionary = ui.snapshot
		if state.is_empty() or not state.get("connectionReady", false) or not state.asks.is_empty(): continue
		var kind: String = state.prompt.get("inputKind", "")
		if kind in ["InputPassPriority", "InputAttack", "InputBlock"] and state.prompt.get("okEnabled", false) and Time.get_ticks_msec() - space_started > 30:
			var game: Dictionary = state.get("game", {})
			space_ms = Time.get_ticks_msec() - space_started
			space_label = "T%d p%d %s" % [int(game.get("turn", 0)), int(game.get("activePlayer", -1)), str(game.get("phase", ""))]
			break
	print("SCENARIO space: pass turn -> next decision at %s = %d ms" % [space_label, space_ms])
	return true
