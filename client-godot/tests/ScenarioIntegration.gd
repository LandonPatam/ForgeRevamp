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
			ui.modal_panel._emit_answer([])
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
		if scenario != "blocking" and int(state.game.turn) >= 5 and state.prompt.get("inputKind", "") == "InputPassPriority":
			if scenario in ["proliferate", "tokens", "reanimate", "combat"]:
				if state.game.activePlayer == 0 and state.game.phase == "Main 1": return true
			else: return true
		if not state.asks.is_empty(): submit_choice()
		elif state.prompt.get("inputKind", "") == "InputConfirmMulligan": ui.opening_hand.submit("ok")
		elif StartingPlayerDialog.needs_selection(state) and ui.modal_panel is StartingPlayerDialog: ui.modal_panel.buttons[0].pressed.emit()
		elif state.prompt.okEnabled: ui._primary_action()
	return check(false, "Prepared board did not load")

func settle() -> bool:
	for index in range(80):
		if not await wait_ready(): return false
		if ui.snapshot.stack.is_empty() and ui.snapshot.asks.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": return true
		if not await step(): return false
	return check(false, "Interaction did not settle: " + str(ui.snapshot.prompt))

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
	if not check(ui.modal_panel is SelectionDialog and ui.modal.visible, "Expected visible card gallery for " + name + ": " + str(ui.snapshot.prompt)): return false
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
	await capture("mana-options")
	if not await choose_named("Green"): return false
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
			if not check(ui.incoming_effect.panel.visible and ui.incoming_effect.active.get("stackId", -1) == ui.snapshot.stack[0].id, "The response popup must identify " + name): return false
			await capture("incoming")
			ui.incoming_effect.browse_button.pressed.emit()
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
		_: passed = check(false, "Scenario driver not implemented: " + name)
	if not passed: return
	print("PASS: Godot live integration (prepared ", name, " card-combination scenario; UI choices and exact resulting game state)")
	ui.get_tree().quit()
