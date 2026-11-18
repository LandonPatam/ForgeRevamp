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
	return check(false, "No usable interaction control (modal=%s %s carousel=%s staged=%s committing=%s tether=%s): " % [ui.modal.visible, (ui.modal_panel.get_script().resource_path.get_file() if is_instance_valid(ui.modal_panel) and ui.modal_panel.get_script() != null else "none"), ui.modal_panel.get("carousel_mode") if is_instance_valid(ui.modal_panel) else "-", ui.modal_panel.get("staged") if is_instance_valid(ui.modal_panel) else "-", ui.modal_panel.get("committing") if is_instance_valid(ui.modal_panel) else "-", ui.interaction_panel.callout.visible] + JSON.stringify(state.prompt).left(300))

func prepared() -> bool:
	if scenario.begins_with("matrix-"): ui.adapter.hold_auto_priority = true # The driver looks first.
	while Time.get_ticks_msec() < deadline:
		if not await wait_ready(): return false
		var state: Dictionary = ui.snapshot
		if scenario in ["blocking", "combat-reasons", "maze", "no-legal-blocks", "combat-fx"] and state.prompt.get("inputKind", "") == "InputBlock": return true
		# A board whose stack resolves straight into your choice (Manifold Insights) is ready at that choice;
		# the scenario driver answers it.
		if int(state.game.turn) >= 5 and str(state.prompt.get("inputKind", "")).begins_with("InputSelect") and state.asks.is_empty() and not (ui.modal.visible and is_instance_valid(ui.modal_panel) and ui.modal_panel.get_script() != null and ui.modal_panel.get_script().resource_path.ends_with("CoinTossPanel.gd")): return true
		# The fixture jumps to turn 5 straight after the starting roll; finish that animation as a player would.
		if int(state.game.turn) >= 5 and ui.modal.visible and is_instance_valid(ui.modal_panel) and ui.modal_panel.get_script().resource_path.ends_with("CoinTossPanel.gd"):
			ui.coin_toss_seen[int(ui.modal_panel.toss_id)] = true
			ui._close_modal()
			ui._present_card_selection() # A choice already waiting behind the coin (Manifold Insights) opens now.
		if scenario not in ["blocking", "combat-reasons", "maze", "no-legal-blocks", "combat-fx"] and int(state.game.turn) >= 5 and state.prompt.get("inputKind", "") == "InputPassPriority":
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
	# A permanent's targets are a tether: click the card (staged), then the tether's Confirm.
	if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and ui.interaction_panel.target_tether:
		var legal: Array = ui.snapshot.prompt.selectable.map(func(id): return int(id))
		var named: Array = ui.snapshot.prompt.get("cards", []).filter(func(card): return card.name == name and legal.has(int(card.id)))
		if not check(named.size() == 1, "Expected one legal target named " + name + " on the tether"): return false
		ui._click_card(named[0].id)
		for index in range(5): await ui.get_tree().process_frame
		if not check(not ui.interaction_panel.callout.yes_button.disabled, "The tether's Confirm enables once the target is staged"): return false
		ui.interaction_panel.callout.yes_button.pressed.emit()
		return await wait_ready()
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

## Combat animations from Forge's real damage events: blocking Gray Ogre with Hill Giant must
## send each hit (who, whom, how much) and play the strike, the impacts and the Ogre's exit.
func combat_fx() -> bool:
	const Fx = preload("res://scripts/ui/TableFx.gd")
	Fx.speed = 1.0
	var giant := find_card("Hill Giant", "Battlefield")
	var ogre_cards: Array = ui.snapshot.players[1].zones.Battlefield.filter(func(card): return card.name == "Gray Ogre")
	var ogre_entry: Array = ui.snapshot.combat.filter(func(entry): return not ogre_cards.is_empty() and int(ogre_cards[0].id) == int(entry.attacker))
	if not check(ogre_entry.size() == 1, "Gray Ogre attacks: " + JSON.stringify(ui.snapshot.combat)): return false
	var jace := find_card("Jace Beleren", "Battlefield")
	var ogre := int(ogre_entry[0].attacker)
	ui._click_card(ogre)
	if not await wait_ready(): return false
	ui._click_card(giant.id)
	if not await wait_ready(): return false
	ui._primary_action()
	var fx: Control = ui.table_fx
	var saw_ghost := false
	var saw_hit := false
	var saw_strike := false
	for index in range(400):
		await ui.get_tree().process_frame
		if fx.ghosts.has(ogre): saw_ghost = true
		if fx.items.any(func(item): return item.kind == "number"): saw_hit = true
		if is_instance_valid(ui.cards.get(giant.id)) and ui.cards[giant.id].fx_offset.length() > 20.0: saw_strike = true
		if saw_hit and saw_ghost and not saw_strike: continue
		if saw_hit and saw_ghost and saw_strike: break
		if index % 6 == 0 and ui.snapshot.get("connectionReady", false) and ui.snapshot.asks.is_empty() and ui.snapshot.prompt.get("okEnabled", false) and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority": ui._intent("ok")
	await ui.get_tree().create_timer(0.08).timeout
	await capture("impact")
	await ui.get_tree().create_timer(0.3).timeout
	await capture("leaving")
	var hits: Array = ui.snapshot.get("fx", []).filter(func(event): return event.get("kind", "") == "damage")
	print("SCENARIO fx: ", JSON.stringify(hits))
	if not check(hits.any(func(event): return int(event.sourceId) == int(giant.id) and int(event.targetId) == ogre and int(event.amount) == 3 and event.combat), "Hill Giant's 3 combat damage to the Ogre is an fx event"): return false
	if not check(hits.any(func(event): return int(event.sourceId) == ogre and int(event.targetId) == int(giant.id) and int(event.amount) == 2 and event.combat), "The Ogre's 2 damage to the Giant is an fx event"): return false
	if not check(hits.any(func(event): return int(event.targetId) == int(jace.id) and int(event.amount) == 1 and event.combat), "Raging Goblin's 1 damage to Jace is an fx event"): return false
	if not check(saw_strike and saw_hit and saw_ghost, "The table played the strike (%s), the damage numbers (%s) and the Ogre's exit (%s)" % [saw_strike, saw_hit, saw_ghost]): return false
	await ui.get_tree().create_timer(1.5).timeout
	await capture("settled")
	return check(fx.ghosts.is_empty() and not ui.cards.has(ogre) and ui.cards[giant.id].fx_offset == Vector2.ZERO, "Every effect ends on the settled board")

## Spell animations from Forge's real stack: brackets lock on to what AI 1's Bolt and Shock aim
## at, Counterspell's answer shatters its stack entry ("countered"), and the other spell's
## resolution flies a projectile from its stack entry to its target ("resolve").
func spell_fx() -> bool:
	const Fx = preload("res://scripts/ui/TableFx.gd")
	Fx.speed = 1.0
	var fx: Control = ui.table_fx
	if not await wait_for(func(): return ui.snapshot.stack.size() == 2 and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority", 20.0): return check(false, "Bolt and Shock wait on the stack")
	var stack_ids: Array = ui.snapshot.stack.map(func(item): return int(item.id))
	var bears := find_card("Grizzly Bears", "Battlefield")
	fx.present(ui.snapshot) # Animations were switched on after this board's last snapshot.
	for index in range(20): await ui.get_tree().process_frame
	if not check(fx.lock_targets.any(func(lock): return lock.kind == "card" and int(lock.id) == int(bears.id)) and fx.lock_targets.any(func(lock): return lock.kind == "player"), "Brackets lock on to the Bears and to you: " + str(fx.lock_targets)): return false
	await capture("lock")
	ui.incoming_effect.respond()
	if not await tap("Island", 2) or not await cast("Counterspell"): return false
	for index in range(10):
		if not await wait_ready(): return false
	await ui.get_tree().create_timer(0.5).timeout
	if not check(ui.response_target.visible, "Counterspell asks which spell to answer"): return false
	var answered := int(ui.snapshot.asks[0].options[0].stackId)
	ui.response_target.confirm.pressed.emit()
	var saw_shatter := false
	var saw_bolt := false
	for index in range(600):
		await ui.get_tree().process_frame
		if fx.items.any(func(item): return item.kind == "strike"): saw_shatter = true
		if fx.items.any(func(item): return item.kind == "bolt" and not item.fizzle):
			if not saw_bolt:
				saw_bolt = true
				await ui.get_tree().create_timer(0.24).timeout
				await capture("projectile")
		if saw_shatter and saw_bolt: break
		if index % 6 == 0 and ui.snapshot.get("connectionReady", false) and ui.snapshot.asks.is_empty():
			if ui.incoming_effect.showing(): ui.incoming_effect.resolve_button.pressed.emit()
			elif ui.snapshot.prompt.get("okEnabled", false) and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority" and not ui.snapshot.stack.is_empty(): ui._intent("ok")
	var events: Array = ui.snapshot.get("fx", []).filter(func(event): return event.get("kind", "") in ["resolve", "countered", "fizzled"])
	print("SCENARIO spell fx: answered=", answered, " stack=", stack_ids, " ", JSON.stringify(events))
	if not check(events.any(func(event): return event.kind == "countered" and int(event.stackId) == answered), "The answered spell is reported countered"): return false
	var other: int = stack_ids.filter(func(id): return id != answered)[0]
	if not check(events.any(func(event): return event.kind == "resolve" and int(event.stackId) == other), "The other spell is reported resolved"): return false
	if not check(saw_shatter and saw_bolt, "The table shattered the countered entry (%s) and flew the other spell to its target (%s)" % [saw_shatter, saw_bolt]): return false
	await ui.get_tree().create_timer(1.5).timeout
	await capture("settled")
	await wait_for(func(): return ui.snapshot.stack.is_empty(), 10.0)
	await ui.get_tree().create_timer(1.0).timeout
	return check(fx.ghosts.is_empty() and fx.lock_targets.is_empty(), "Every effect and lock ends once the stack is empty: ghosts=%s locks=%s stack=%s" % [fx.ghosts.keys(), fx.lock_targets, ui.snapshot.stack.size()])

## Board-life animations from Forge's real resolution: an opponent's creature shown large, tokens
## printing in, a counter and a pump label, a drain line with rolling HP, and your mana symbol.
func board_fx() -> bool:
	const Fx = preload("res://scripts/ui/TableFx.gd")
	Fx.speed = 1.0
	var fx: Control = ui.table_fx
	if not await wait_for(func(): return ui.snapshot.stack.size() == 5 and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority", 20.0): return check(false, "AI 1's five spells wait on the stack: " + str(ui.snapshot.stack.size()))
	fx.present(ui.snapshot) # Animations were switched on after this board's last snapshot.
	var seen := {}
	var texts: Array = []
	if ui.incoming_effect.showing(): ui.incoming_effect.respond()
	if not await wait_ready() or not await tap("Forest"): return false
	var captured := {}
	for index in range(900):
		await ui.get_tree().process_frame
		for item in fx.items:
			if item.kind in ["showcase", "print", "mana", "bolt"] and fx.clock >= item.start: seen[item.kind] = true
			if item.kind == "number" and fx.clock >= item.start and not texts.has(item.text): texts.append(item.text)
		for kind in ["mana", "showcase", "print"]:
			if seen.has(kind) and not captured.has(kind):
				captured[kind] = true
				await ui.get_tree().create_timer(0.2).timeout
				await capture(kind)
		if ui.snapshot.stack.is_empty() and seen.size() >= 4 and index > 60: break
		if index % 8 == 0 and ui.snapshot.get("connectionReady", false) and ui.snapshot.asks.is_empty():
			if ui.incoming_effect.showing(): ui.incoming_effect.resolve_button.pressed.emit()
			elif ui.snapshot.prompt.get("okEnabled", false) and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority" and not ui.snapshot.stack.is_empty(): ui._intent("ok")
	texts = fx.shown_labels.duplicate()
	for kind in fx.played: seen[kind] = true
	print("SCENARIO board fx: seen=", seen.keys(), " labels=", texts, " director draw %.2f ms, snapshot diff %.2f ms" % [fx.cost.draw / 1000.0, fx.cost.present / 1000.0])
	print("SCENARIO giant: ", JSON.stringify(ui.snapshot.players[1].zones.Battlefield.filter(func(card): return card.name == "Hill Giant")).left(600), " graveyard=", ui.snapshot.players[1].zones.Graveyard.map(func(card): return card.name))
	await capture("labels")
	if not check(seen.has("mana"), "Tapping your Forest flies a mana symbol"): return false
	if not check(seen.has("showcase"), "AI 1's Grizzly Bears shows large before it settles"): return false
	if not check(seen.has("print"), "Raise the Alarm's Soldiers print in"): return false
	if not check(texts.has("+1/+1") and texts.has("+3/+3"), "The counter and the pump get labels: " + str(texts)): return false
	if not check(texts.has("+3") and texts.has("-3"), "The drain shows AI 1 gaining 3 and you losing 3: " + str(texts)): return false
	await ui.get_tree().create_timer(1.5).timeout
	var hidden: Array = ui.cards.values().filter(func(view): return view.fx_alpha < 1.0)
	return check(hidden.is_empty() and int(round(ui.hud_values[0].portrait.shown_life)) == int(ui.snapshot.players[0].life), "Every card is fully shown again and the HP digits settled on the real total")

## Board-wipe sweep and turn banner on a real engine: Wrath of God over five creatures plays one
## scan line with staggered exits, and passing the turn slides a TURN banner in once.
func wipe_fx() -> bool:
	const Fx = preload("res://scripts/ui/TableFx.gd")
	Fx.speed = 1.0
	var fx: Control = ui.table_fx
	if not await wait_for(func(): return not ui.snapshot.stack.is_empty() and ui.incoming_effect.showing(), 20.0): return check(false, "Wrath of God waits on you")
	fx.present(ui.snapshot) # Animations were switched on after this board's last snapshot.
	ui.incoming_effect.resolve_button.pressed.emit()
	var captured := false
	var worst := 0.0
	for index in range(600):
		await ui.get_tree().process_frame
		worst = maxf(worst, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if not captured and fx.items.any(func(item): return item.kind == "sweep" and fx.clock > item.start + item.life * 0.25):
			captured = true
			await capture("sweep")
		if fx.played.has("sweep") and fx.ghosts.is_empty() and index > 30: break
	print("SCENARIO wipe fx: worst process frame %.1f ms; director draw %.2f ms, snapshot diff %.2f ms" % [worst, fx.cost.draw / 1000.0, fx.cost.present / 1000.0])
	if not check(fx.played.has("sweep"), "The wipe plays one sweep across the table: " + str(fx.played)): return false
	var creatures: Array = []
	for player in ui.snapshot.players: creatures.append_array(player.zones.Battlefield.filter(func(card): return "Creature" in str(card.get("typeLine", ""))))
	if not check(creatures.is_empty(), "Every creature died: " + str(creatures.map(func(card): return card.name))): return false
	var turn := int(ui.snapshot.game.turn)
	ui._pass_turn()
	if not await pass_until(func(): return int(ui.snapshot.game.turn) > turn, 300): return check(false, "The turn passes")
	for index in range(12): await ui.get_tree().process_frame
	await capture("banner")
	if not check(int(fx.played.get("banner", 0)) == 1, "A new turn slides the banner in exactly once: " + str(fx.played)): return false
	await ui.get_tree().create_timer(2.0).timeout
	return check(fx.items.is_empty() and not fx.is_processing(), "Once every effect ends the director stops running (no idle cost): %d items, processing=%s" % [fx.items.size(), fx.is_processing()])

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
			# The reveal is part of this choice: the revealed cards are shown face up here.
			revealed = revealed or ui.modal_panel.options.any(func(option): return not option.get("hidden", false) and not str(option.get("name", "")).is_empty())
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
		# Forge is already waiting on the choice but the window opens a frame later (slow under a long suite).
		if str(ui.snapshot.prompt.get("inputKind", "")).begins_with("InputSelect") and not ui.modal.visible:
			await ui.get_tree().create_timer(0.2).timeout
			continue
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
			if name.begins_with("shape-"): passed = await shape_probe()
			elif has_method(driver): passed = await call(driver)
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

## A real connection drop during a staged discard. Discard sends the first pick; the socket closes in
## the same frame. After the reconnect the second pick is never sent on its own, nothing stays marked
## and Forge holds at most the first. The player marks the rest again and both cards are discarded.
func discard_interrupted() -> bool:
	if not await tap("Mountain") or not await cast("Faithless Looting"): return false
	for index in range(40):
		if not await wait_ready(): return false
		if ui.snapshot.prompt.get("inputKind", "") == "InputSelectCardsFromList": break
		if not await step(): return false
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputSelectCardsFromList" and ui.hand_pick_panel.visible, "Faithless Looting asks for a discard from the hand"): return false
	var picks: Array = zone("Hand").slice(0, 2).map(func(card): return int(card.id))
	for id in picks:
		ui._click_card(id)
		if not await wait_ready(): return false
	if not check(ui.hand_pick_staged == picks and not ui.hand_pick_confirm.disabled, "Both cards are marked locally"): return false
	ui.adapter.sent_requests = []
	ui.hand_pick_confirm.pressed.emit()
	var in_flight: Array = ui.adapter.sent_requests.map(func(request): return [request.get("action", ""), int(request.get("id", -1))])
	ui.adapter.socket.close()
	if not check(in_flight == [["card", picks[0]]], "Discard sent only the first pick before the drop: " + str(in_flight)): return false
	if not await wait_for(func(): return not ui.adapter.connected, 5.0): return check(false, "The client notices the dropped connection")
	if not check(not ui.hand_pick_committing and ui.hand_pick_staged.is_empty(), "The drop ends the send and clears the marks"): return false
	if not await wait_for(func(): return ui.adapter.connected and not ui.adapter.syncing and ui.snapshot.get("connectionReady", false), 20.0): return check(false, "The client reconnects to the same match")
	await ui.get_tree().create_timer(2.0).timeout
	if not await wait_ready(): return false
	var after: Array = ui.adapter.sent_requests.slice(1).filter(func(request): return request.get("type", "") == "action").map(func(request): return [request.action, int(request.get("id", -1))])
	var chosen: Array = ui.snapshot.prompt.get("chosen", [])
	print("SCENARIO discard reconnect: input=", ui.snapshot.prompt.get("inputKind", ""), " chosen=", chosen, " sent after drop=", after)
	if not check(not after.any(func(action): return action[1] == picks[1]), "The second pick never went out on its own: " + str(after)): return false
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputSelectCardsFromList" and not chosen.has("card:%d" % picks[1]) and chosen.size() <= 1, "Forge still asks, holding at most the first pick: " + str(chosen)): return false
	# Forge already holds the first pick, so the generic card window takes the question: it shows and
	# can change what Forge holds (the hand view only shows its own local marks).
	if not check(ui.hand_pick_staged.is_empty() and not ui.hand_pick_panel.visible and ui.modal.visible and ui.modal_panel is SelectionDialog, "The card window takes the question with Forge's pick, nothing marked locally"): return false
	await capture("reconnected")
	# The player picks what is still missing there and confirms.
	var window = ui.modal_panel
	for id in picks:
		if chosen.has("card:%d" % id): continue
		var row: int = window.options.map(func(option): return int(option.get("id", -1))).find(id)
		if not check(row >= 0, "The window offers the second card"): return false
		window.option_buttons[row].pressed.emit()
		if not await wait_ready(): return false
	if is_instance_valid(window) and ui.modal.visible and ui.modal_panel == window and not window.confirm_button.disabled: window.confirm_button.pressed.emit()
	if not await settle(): return false
	var graveyard: Array = zone("Graveyard").map(func(card): return int(card.id))
	return check(graveyard.has(picks[0]) and graveyard.has(picks[1]), "Forge discards exactly the two marked cards: " + str(zone("Graveyard").map(func(card): return card.name)))

## The YOU LOSE screen says how: Forge's loss reason and, for life, the damage of the final hit.
func loss_cause() -> bool:
	if not await wait_for(func(): return not ui.snapshot.stack.is_empty(), 20.0): return check(false, "Lightning Bolt waits on the stack")
	if ui.incoming_effect.showing(): ui.incoming_effect.resolve_button.pressed.emit()
	elif ui.snapshot.prompt.get("okEnabled", false): ui._intent("ok")
	if not await wait_for(func(): return is_instance_valid(ui.outcome_screen) and ui.outcome_screen.visible, 20.0): return check(false, "The loss opens YOU LOSE: " + str(ui.snapshot.players[0].get("loss", {})))
	var loss: Dictionary = ui.snapshot.players[0].get("loss", {})
	var status: String = ui.outcome_screen.status
	print("SCENARIO loss: ", loss, " / ", status)
	if not check(loss.get("reason", "") == "life" and loss.get("sources", []).any(func(source): return str(source.name) == "Lightning Bolt" and int(source.amount) == 3), "Forge's loss names the life reason and the Bolt's 3 damage: " + str(loss)): return false
	await ui.get_tree().create_timer(ui.outcome_screen.settle_time + 3.0).timeout
	await capture("lose")
	return check(status.contains("LIFE REACHED 0") and status.contains("LIGHTNING BOLT (3)"), "YOU LOSE says how: " + status)

## Stack responses matrix. Each matrix-* board puts one opponent item on the stack at your priority.
## For Everything, Smart and Only threats, the adapter's own rule is applied to Forge's real
## snapshot and must match `waits` (true = keeps the window, false = passes on its own). Then the
## seat really runs each waiting level (no pass reaches Forge), and the first passing level must
## pass Forge's priority itself.
const STACK_LEVELS := ["Everything", "Smart", "Only threats"]

func matrix_creature() -> bool: return await _stack_matrix([false, false, false])
func matrix_counter() -> bool: return await _stack_matrix([true, true, false])
func matrix_instant() -> bool: return await _stack_matrix([true, true, false])
func matrix_draw() -> bool: return await _stack_matrix([true, true, false]) # An instant: Smart keeps the window even for a draw notice.
func matrix_targeted() -> bool: return await _stack_matrix([true, true, true])
func matrix_wipe() -> bool: return await _stack_matrix([true, true, true])
func matrix_wipe_misses() -> bool: return await _stack_matrix([false, false, false])

func _stack_matrix(waits: Array) -> bool:
	const Live = preload("res://scripts/bridge/LiveAdapter.gd")
	var adapter = ui.adapter
	adapter.hold_auto_priority = true
	if not await wait_for(func(): return adapter.state.get("prompt", {}).get("inputKind", "") == "InputPassPriority" and not adapter.state.get("stack", []).is_empty() and int(adapter.state.stack[0].get("card", {}).get("owner", -1)) != 0 and adapter.state.get("connectionReady", false), 20.0):
		return check(false, "An opponent's item waits on this seat's priority: " + str(adapter.state.get("prompt", {}).get("inputKind", "")))
	var item: Dictionary = adapter.state.stack[0]
	var item_id := int(item.id)
	var row: Array = []
	for level in range(3): row.append(not Live.passes_automatically(adapter.state, level, level == 2))
	var facts := "canRespond=%s bridgeAutoPass=%s targetsLocal=%s effects=%s" % [adapter.state.get("canRespond", false), int(adapter.state.get("bridgeAutoPassId", -1)) == item_id, item.get("targetsLocal", false), adapter.state.get("targetedEffects", []).map(func(event): return event.get("kind", ""))]
	print("SCENARIO matrix %s: %s waits=%s want=%s %s" % [scenario, item.get("sourceName", ""), row, waits, facts])
	for level in range(3):
		if not check(row[level] == waits[level], "%s: %s should %s under %s (%s)" % [scenario, item.get("sourceName", ""), "wait" if waits[level] else "pass", STACK_LEVELS[level], facts]): return false
	# Real behavior: each waiting level holds Forge's priority, then a passing level passes it.
	adapter.sent_requests = []
	adapter.hold_auto_priority = false
	for level in range(3):
		if not waits[level]: continue
		adapter.stack_mode = level
		adapter.auto_resolve_all = level == 2
		await ui.get_tree().create_timer(1.2).timeout
		var passed: bool = adapter.sent_requests.any(func(request): return request.get("action", "") == "ok")
		if not check(not passed and not adapter.state.get("stack", []).is_empty() and int(adapter.state.stack[0].id) == item_id, "%s holds Forge's priority on %s" % [STACK_LEVELS[level], item.get("sourceName", "")]): return false
	var passing := waits.find(false)
	if passing < 0: return true
	adapter.stack_mode = passing
	adapter.auto_resolve_all = passing == 2
	if not await wait_for(func(): return adapter.sent_requests.any(func(request): return request.get("action", "") == "ok"), 3.0): return check(false, "%s passes Forge's priority on %s by itself" % [STACK_LEVELS[passing], item.get("sourceName", "")])
	return check(await wait_for(func(): return not adapter.state.get("stack", []).any(func(entry): return int(entry.id) == item_id), 10.0), "%s resolves after the pass" % item.get("sourceName", ""))

## A two-card library search: marks stay local, OK sends each exact instance to Forge in turn.
## cultivate-list makes the same picks in the plain list window; both must send the same instances.
func cultivate() -> bool:
	return await _cultivate(false)

func cultivate_list() -> bool:
	return await _cultivate(true)

func _cultivate(list: bool) -> bool:
	SelectionDialog.carousel_enabled = not list
	if not await tap("Forest", 3) or not await cast("Cultivate"): return false
	if not await resolve_to_choice(): return false
	var search: Control = ui.modal_panel
	if not check(search is SelectionDialog and search.carousel_mode != list, "Cultivate's search must open the %s" % ("plain list" if list else "carousel")): return false
	for index in range(20): await ui.get_tree().process_frame
	if not check(list or (ui.search_link.visible and ui._search_anchor() != null), "The carousel is linked to Cultivate on the stack"): return false
	# Forge's side: which exact copies the first Island and Swamp rows stand for.
	var wanted: Array = []
	var rows: Array = []
	for name in ["Island", "Swamp"]:
		for r in range(search.groups.size()):
			if search.options[search.groups[r][0]].get("name", "") == name:
				rows.append(r)
				wanted.append(int(search.options[search.groups[r][0]].id))
	if not check(wanted.size() == 2, "The search offers an Island and a Swamp"): return false
	var offered: Array = search.options.map(func(option): return int(option.get("id", -1)))
	var search_id = ui.snapshot.prompt.get("inputId", -1)
	ui.adapter.sent_requests = []
	if list:
		for r in rows:
			search._pick_row(r)
			if not await wait_ready(): return false
		await capture("picked-list")
		# Forge usually finishes at the second pick; press OK only if it is still waiting.
		if is_instance_valid(search) and ui.modal.visible and ui.modal_panel == search and not search.confirm_button.disabled: search.confirm_button.pressed.emit()
	else:
		for r in rows: search._stage_group(r)
		if not check(search.staged.size() == 2 and ui.snapshot.prompt.get("chosen", []).is_empty() and ui.adapter.sent_requests.is_empty(), "Two marks must stay local until OK: " + str(search.staged)): return false
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
	# The wire: the search's picks are exactly those instances, in the same order. Forge may finish
	# the search itself at its maximum, so OK is not required.
	var search_input = search_id
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputId", -1) != search_input or not ui.snapshot.asks.is_empty(), 40): return check(false, "The search finishes: " + str(ui.snapshot.prompt))
	var actions: Array = ui.adapter.sent_requests.filter(func(request): return request.get("action", "") == "card" and offered.has(int(request.get("id", -1)))).map(func(request): return int(request.id))
	if not check(actions == wanted, "Sent picks %s, want %s" % [actions, wanted]): return false
	if not await settle(): return false
	var found: Array = (zone("Battlefield") + zone("Hand")).map(func(card): return int(card.id))
	return check(found.has(wanted[0]) and found.has(wanted[1]) and ui.snapshot.players[0].libraryCount == 8, "Forge must fetch exactly the picked Island and Swamp instances: " + str(wanted))

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

func triggers_token_first() -> bool:
	return await _test_trigger_resolution_order(true)

func triggers_counter_first() -> bool:
	return await _test_trigger_resolution_order(false)

func _test_trigger_resolution_order(token_first: bool) -> bool:
	if not await pass_until(func(): return ui.snapshot.asks.any(func(ask): return ask.get("abilityOrder", false)), 60):
		return check(false, "The two end-step triggers must offer a simultaneous order")
	var ask: Dictionary = ui.snapshot.asks[0]
	var panel: Control = ui.modal_panel
	if not check(ui.modal.visible and is_instance_valid(panel) and panel.order_stack != null, "Forge's order opens in the stack builder"): return false
	var builder: Control = panel.order_stack
	var sources: Array = ask.options.map(func(option): return option.card.name)
	var wanted := ["Wedding Announcement", "Brokers Ascendancy"] if token_first else ["Brokers Ascendancy", "Wedding Announcement"]
	if not check(sources.size() == 2 and sources.has(wanted[0]) and sources.has(wanted[1]), "The builder offers exactly the two expected triggers"): return false
	ui.adapter.sent_requests = []
	var requests: int = ui.adapter.request_counter
	var first: int = builder.order[0]
	_drag_top_trigger(builder)
	if not check(builder.order[1] == first, "Dragging through the viewport moves the top trigger below the other one"): return false
	if sources[builder.order[0]] != wanted[0]:
		await ui.get_tree().process_frame
		_drag_top_trigger(builder)
	if not check(builder.order.map(func(index): return sources[index]) == wanted, "The chosen first trigger is the top row"): return false
	if not check(ui.adapter.request_counter == requests and ui.snapshot.asks[0].id == ask.id, "Dragging keeps the order local until confirmation"): return false
	await capture("ordered")
	panel.confirm_button.pressed.emit()
	return await _trigger_order_outcome(ask, wanted, token_first)

## triggers-plain: the same order as triggers-token-first, clicked in sequence without the stack builder.
func triggers_plain() -> bool:
	const PromptPanel = preload("res://scripts/ui/PromptPanel.gd")
	PromptPanel.stack_builder_enabled = false
	if not await pass_until(func(): return ui.snapshot.asks.any(func(ask): return ask.get("abilityOrder", false)), 60):
		return check(false, "The two end-step triggers must offer a simultaneous order")
	var ask: Dictionary = ui.snapshot.asks[0]
	var panel: Control = ui.modal_panel
	if not check(ui.modal.visible and is_instance_valid(panel) and panel.order_stack == null, "Without the builder the order is plain click-in-sequence"): return false
	var sources: Array = ask.options.map(func(option): return option.card.name)
	var wanted := ["Wedding Announcement", "Brokers Ascendancy"]
	ui.adapter.sent_requests = []
	for name in wanted:
		panel._toggle(sources.find(name))
	if not check(ui.adapter.sent_requests.is_empty(), "Clicking keeps the order local until confirmation"): return false
	await capture("ordered-plain")
	panel._submit()
	return await _trigger_order_outcome(ask, wanted, true)

## Shared by the builder and plain runs: one answer listing the triggers in the wanted order, and the
## token gets a counter exactly when Wedding Announcement resolved first.
func _trigger_order_outcome(ask: Dictionary, wanted: Array, token_first: bool) -> bool:
	if not await wait_ready(): return false
	var sources: Array = ask.options.map(func(option): return option.card.name)
	var answers: Array = ui.adapter.sent_requests.filter(func(request): return request.get("type", "") == "answer" and int(request.get("id", -1)) == int(ask.id))
	var sent: Array = (answers[0].value if not answers.is_empty() and answers[0].value is Array else []).map(func(index): return sources[int(index)])
	if not check(answers.size() == 1 and sent == wanted, "One answer with order %s, got %s" % [wanted, answers]): return false
	if not await pass_until(func():
		return (ui.snapshot.stack.is_empty() and not _wedding_token().is_empty()
			and counter(find_card("Grizzly Bears", "Battlefield"), "P1P1") == 1)
	, 80): return check(false, "Both abilities finish resolving and the existing Bears get a counter: " + JSON.stringify({
		"phase": ui.snapshot.game.phase, "prompt": ui.snapshot.prompt.get("inputKind"), "asks": ui.snapshot.asks.map(func(other): return other.kind),
		"board": zone("Battlefield").map(func(card): return [card.name, card.get("token"), card.get("counters")]),
		"log": ui.snapshot.log.slice(0, 10),
	}))
	var token := _wedding_token()
	return check(counter(token, "P1P1") == (1 if token_first else 0),
		"The token has a counter exactly when Wedding Announcement resolved first")

func _wedding_token() -> Dictionary:
	for card in zone("Battlefield"):
		if card.get("token", false) and str(card.name).begins_with("Human"): return card
	return {}

func _drag_top_trigger(builder: Control) -> void:
	const OrderStack = preload("res://scripts/ui/OrderStack.gd")
	var transform := builder.get_global_transform_with_canvas()
	var from := transform * Vector2(builder.size.x * 0.5, OrderStack.ROW_H * 0.5)
	var to := transform * Vector2(builder.size.x * 0.5, OrderStack.ROW_H * 1.5 + OrderStack.GAP)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	press.global_position = from
	ui.get_viewport().push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.global_position = to
	motion.relative = to - from
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	ui.get_viewport().push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = to
	release.global_position = to
	ui.get_viewport().push_input(release, true)

## "Choose one or more" modes hang off the card as one callout; picks stay local until Confirm,
## then the bridge feeds every pick to Forge's one-at-a-time mode prompts.
func concord() -> bool:
	return await _concord(false)

func concord_counters() -> bool:
	return await _concord(true)

## concord-popup: the same choice as concord-counters through the generic popup instead of the tether.
func concord_popup() -> bool:
	return await _concord(true, true)

func _concord(pick_counter: bool, popup: bool = false) -> bool:
	ui.interaction_panel.tethers_enabled = not popup
	for index in range(40):
		if not await wait_ready(): return false
		if not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].get("modeChoice", false): break
		if not await step(): return false
	if not check(not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].get("modeChoice", false), "Concord must ask for all its modes at once: " + str(ui.snapshot.asks)): return false
	for index in range(5): await ui.get_tree().process_frame
	var callout: Control = ui.interaction_panel.callout
	if popup:
		if not check(not callout.visible and ui.modal.visible and is_instance_valid(ui.modal_panel), "With tethers off, the modes open the generic popup"): return false
	else:
		if not check(callout.visible and not ui.modal.visible, "The modes must attach to the card, not open a popup"): return false
		if not check(callout.mode_buttons.size() == 3 and callout.yes_button.disabled, "Three modes, nothing confirmable before a pick"): return false
	var hand_before: int = zone("Hand").size()
	var bears := find_card("Grizzly Bears", "Battlefield")
	var counters_before := counter(bears, "P1P1")
	var ask_id := int(ui.snapshot.asks[0].id)
	var modes: Array = ui.snapshot.asks[0].options
	var selected_effect := "counter" if pick_counter else "draw a card"
	var picked: Array = []
	ui.adapter.sent_requests = []
	for fragment in ["spirit", selected_effect]:
		var index := modes.find_custom(func(mode): return str(mode.label).to_lower().contains(fragment))
		if not check(index >= 0, "Forge offers the %s mode" % fragment): return false
		picked.append(index)
		if popup: ui.modal_panel._toggle(index)
		else: callout.mode_buttons[index].pressed.emit()
	await capture("modes-popup" if popup else "modes")
	if not await wait_ready(): return false
	if not check(ui.snapshot.asks.size() == 1 and ui.snapshot.asks[0].get("modeChoice", false) and ui.adapter.sent_requests.is_empty(), "Picking modes must not answer Forge"): return false
	if popup: ui.modal_panel._submit()
	else: callout.yes_button.pressed.emit()
	if not await wait_ready(): return false
	# The wire: one answer to this ask naming exactly the picked modes, whichever presentation sent it.
	var answers: Array = ui.adapter.sent_requests.filter(func(request): return request.get("type", "") == "answer" and int(request.get("id", -1)) == ask_id)
	var sent: Array = (answers[0].value if not answers.is_empty() and answers[0].value is Array else []).map(func(value): return int(value))
	sent.sort()
	picked.sort()
	if not check(answers.size() == 1 and sent == picked, "One answer with modes %s, got %s" % [picked, answers]): return false
	for index in range(40):
		if not await wait_ready(): return false
		if zone("Battlefield").any(func(card): return str(card.name).contains("Spirit")) and ui.snapshot.stack.is_empty(): break
		if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets":
			if not check(pick_counter, "The unselected counter mode cannot ask for a target"): return false
			if not await select_named("Grizzly Bears"): return false
			continue
		if not await step(): return false
	if not check(zone("Battlefield").filter(func(card): return str(card.name).contains("Spirit")).size() == 1, "The Spirit mode creates exactly one token"): return false
	return check(zone("Hand").size() == hand_before + (0 if pick_counter else 1)
		and counter(find_card("Grizzly Bears", "Battlefield"), "P1P1") == counters_before + (1 if pick_counter else 0),
		"Only the chosen draw or counter mode takes effect")

func fiery_confluence() -> bool:
	if not await tap("Mountain", 4) or not await cast("Fiery Confluence"): return false
	for fragment in ["damage to each opponent", "damage to each opponent", "destroy target artifact"]:
		if not await pass_until(func(): return not ui.snapshot.asks.is_empty()): return check(false, "Forge offers each of the three selections separately")
		var ask: Dictionary = ui.snapshot.asks[0]
		if not check(not ask.get("modeChoice", false), "Repeatable modes use Forge's individual choices"): return false
		if not await _select_mode_control(ask, fragment): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets"): return check(false, "The chosen destroy mode asks for an artifact")
	if not await select_named("Sol Ring"): return false
	if not await settle(): return false
	return check(ui.snapshot.players[1].life == 36 and ui.snapshot.players[2].life == 36
		and ui.snapshot.players[1].zones.Graveyard.any(func(card): return card.name == "Sol Ring"),
		"Both repeats deal two damage to each opponent, and the third mode destroys Sol Ring")

func _select_mode_control(ask: Dictionary, fragment: String) -> bool:
	var modes: Array = ask.options
	var index := modes.find_custom(func(mode): return str(mode.label).to_lower().contains(fragment))
	if not check(index >= 0, "The current choice offers %s" % fragment): return false
	var tether: Control = ui.interaction_panel.callout
	if tether.visible and int(tether.mode_ask.get("id", -1)) == int(ask.id):
		tether.mode_buttons[index].pressed.emit()
		tether.yes_button.pressed.emit()
	elif ui.modal.visible and is_instance_valid(ui.modal_panel):
		ui.modal_panel.option_buttons[index].pressed.emit()
		ui.modal_panel.confirm_button.pressed.emit()
	else:
		return check(false, "The current choice has an active mode control")
	return await wait_ready()

func season_pawprints() -> bool:
	if not await tap("Island", 6) or not await cast("Season of Weaving"): return false
	var remaining_choices := [3, 2, 1]
	var selected := ["return each", "draw a card", "draw a card"]
	for i in range(selected.size()):
		if not await pass_until(func(): return not ui.snapshot.asks.is_empty()): return check(false, "Forge asks for the next affordable choice")
		var ask: Dictionary = ui.snapshot.asks[0]
		if not check(ask.options.size() == remaining_choices[i], "Forge filters modes as the five-pawprint budget is spent"): return false
		if not await _select_mode_control(ask, selected[i]): return false
	if not await pass_until(func(): return not find_card("Season of Weaving", "Graveyard").is_empty(), 60):
		return check(false, "Spending all five pawprints ends the chooser and resolves the spell")
	return check(not find_card("Grizzly Bears", "Hand").is_empty() and zone("Hand").size() == 3
		and not zone("Battlefield").any(func(card): return card.get("token", false)), "Forge returns the Bears, draws twice, and never applies the unselected copy mode")

func zero_modes() -> bool:
	if not await tap("Forest", 2) or not await cast("Call Damage Control"): return false
	if not await pass_until(func(): return not ui.snapshot.asks.is_empty()): return check(false, "Call Damage Control offers its mode choices")
	var ask: Dictionary = ui.snapshot.asks[0]
	if not check(ask.get("modeChoice", false) and int(ask.min) == 0, "Forge permits choosing zero modes"): return false
	var tether: Control = ui.interaction_panel.callout
	if not check(tether.visible and not tether.no_button.disabled and tether.no_button.visible, "The mode tether offers the empty choice"): return false
	await capture("choose-none")
	tether.no_button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.asks.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority", 28):
		return check(false, "Choosing zero modes finishes the mode decision: " + str(ui.snapshot.asks))
	if not await settle(): return false
	return check(find_card("Grizzly Bears", "Graveyard").get("name", "") == "Grizzly Bears"
		and find_card("Island", "Graveyard").get("name", "") == "Island"
		and not find_card("Call Damage Control", "Graveyard").is_empty(), "The spell resolves after zero choices, returning no cards")

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

## --- Probes for the next batch (print what Forge sends; replaced by real checks) ---
func dump(tag: String) -> void:
	var s: Dictionary = ui.snapshot
	var shown_prompt: Dictionary = s.prompt.duplicate()
	shown_prompt.erase("cards")
	print("SCENARIO ", tag, " prompt: ", JSON.stringify(shown_prompt).left(900))
	print("SCENARIO ", tag, " asks: ", JSON.stringify(s.asks).left(1200))
	print("SCENARIO ", tag, " stack: ", JSON.stringify(s.stack).left(600))
	print("SCENARIO ", tag, " ui: modal=", (ui.modal_panel.get_script().resource_path.get_file() if ui.modal.visible and is_instance_valid(ui.modal_panel) and ui.modal_panel.get_script() != null else "none"), " rail=", ui.interaction_panel.panel.visible, " tether=", ui.interaction_panel.callout.visible, " effect=", ui.incoming_effect.showing())
	await capture(tag)

func pass_until(test: Callable, limit: int = 120) -> bool:
	for index in range(limit):
		await ui.get_tree().create_timer(0.1).timeout
		if ui.snapshot.is_empty() or not ui.snapshot.get("connectionReady", false): continue
		if test.call(): return true
		if ui.incoming_effect.showing() and not test.call(): continue
		if ui.snapshot.asks.is_empty() and ui.snapshot.prompt.get("okEnabled", false) and ui.snapshot.prompt.get("inputKind", "") in ["InputPassPriority", "InputAttack", "InputBlock"]: ui._intent("ok")
	return false

## An opponent's X spell aimed at your things waits for you and its view names X ("X = 4").
func x_wipe() -> bool:
	var effect: Control = ui.incoming_effect
	if not await pass_until(func(): return effect.showing() and not ui.snapshot.stack.is_empty() and ui.snapshot.stack[0].has("xValue"), 300): return check(false, "The AI never cast an X spell at you: " + JSON.stringify(ui.snapshot.stack).left(300))
	for index in range(20): await ui.get_tree().process_frame
	var x := int(ui.snapshot.stack[0].xValue)
	var shown: String = effect.wipe_title.text if effect.wipe_card.visible else effect.title.text
	print("SCENARIO x: ", ui.snapshot.stack[0].get("sourceName", ""), " X=", x, " shown=", shown)
	await capture("x")
	return check(shown.contains("X = %d" % x), "The popup shows the X value: " + shown)

## Damage marked this turn shows under the stats in red as what the creature is right now: a 4/4
## Angel with 2 damage reads 4/2. Bolting the Craw Wurm adds the badge live.
func damage() -> bool:
	var angel := find_card("Serra Angel", "Battlefield")
	if not check(int(angel.get("damage", 0)) == 2 and int(ui.cards[int(angel.id)].data.get("damage", 0)) == 2, "The Angel's view carries its 2 damage"): return false
	if not await tap("Mountain") or not await cast("Lightning Bolt"): return false
	var wurm := find_card("Craw Wurm", "Battlefield")
	if not await select_named("Craw Wurm"): return false
	if not await pass_until(func(): return ui.snapshot.stack.is_empty() and int(find_card("Craw Wurm", "Battlefield").get("damage", 0)) == 3): return check(false, "Bolt marks 3 damage on the Wurm")
	for index in range(10): await ui.get_tree().process_frame
	await capture("damage")
	return check(int(ui.cards[int(wurm.id)].data.get("damage", 0)) == 3, "The Wurm's view shows its new damage")

## Combustible Gearhulk's "target opponent" is a tether off the Gearhulk: opponents as rows, the pick
## staged locally with a line to their portrait, sent only on Confirm.
func gearhulk() -> bool:
	if not await tap("Mountain", 6) or not await cast("Combustible Gearhulk"): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets"): return check(false, "The Gearhulk trigger must ask for a target")
	for index in range(10): await ui.get_tree().process_frame
	var panel: Control = ui.interaction_panel
	var tether: Control = panel.callout
	if not check(panel.target_tether and tether.visible and not panel.panel.visible and tether.mode_buttons.size() == 2, "The target choice is a tether with both opponents"): return false
	if not check(tether.line.text.contains("draw three cards"), "It shows the effect's text: " + tether.line.text): return false
	var players: Array = ui.snapshot.prompt.get("entities", []).filter(func(entity): return entity.get("kind", "") == "player")
	var row := players.map(func(entity): return int(entity.id)).find(2)
	if not check(row >= 0, "The tether lists the second opponent: " + str(players)): return false
	ui.adapter.sent_requests = []
	tether.mode_buttons[row].pressed.emit()
	for index in range(10): await ui.get_tree().process_frame
	if not check(ui.adapter.sent_requests.is_empty() and panel.target_staged.size() == 1 and ui.snapshot.prompt.get("chosen", []).is_empty(), "Picking stages the opponent locally"): return false
	await ui.get_tree().create_timer(0.3).timeout
	await capture("gearhulk")
	tether.yes_button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") != "InputSelectTargets"): return check(false, "Confirm sends the target")
	return _gearhulk_outcome()

## The same "target opponent" through the tether's player rows (gearhulk) and the rail's player
## buttons (gearhulk-rail): both pick the second opponent, send one player action for that seat and
## put the trigger on Forge's stack targeting that player.
func gearhulk_rail() -> bool:
	ui.interaction_panel.tethers_enabled = false
	if not await tap("Mountain", 6) or not await cast("Combustible Gearhulk"): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets"): return check(false, "The Gearhulk trigger must ask for a target")
	for index in range(10): await ui.get_tree().process_frame
	var panel: Control = ui.interaction_panel
	var players: Array = ui.snapshot.prompt.get("entities", []).filter(func(entity): return entity.get("kind", "") == "player")
	var row := players.map(func(entity): return int(entity.id)).find(2)
	if not check(not panel.target_tether and panel.panel.visible and players.size() == 2 and row >= 0 and panel.choices.get_child_count() == 2, "With tethers off, the rail offers both opponents as buttons: " + str(players)): return false
	await capture("gearhulk-rail")
	ui.adapter.sent_requests = []
	panel.choices.get_child(row).pressed.emit()
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") != "InputSelectTargets"): return check(false, "The rail sends the target")
	if not check(not panel.confirm_button.visible or panel.confirm_button.disabled or ui.snapshot.prompt.get("inputKind", "") != "InputSelectTargets", "One opponent finishes the choice"): return false
	return _gearhulk_outcome()

## Shared by both Gearhulk runs: one player pick for seat 2 on the wire, and Forge's trigger targets it.
func _gearhulk_outcome() -> bool:
	var picks: Array = ui.adapter.sent_requests.filter(func(request): return request.get("type", "") == "action" and request.get("action", "") in ["card", "player"])
	var second := int(ui.snapshot.players[2].get("engineId", -1))
	if not check(picks.size() == 1 and picks[0].action == "player" and int(picks[0].id) == second, "Sent exactly one player pick for the second opponent (engine %d): %s" % [second, picks]): return false
	var name := str(ui.snapshot.players[2].name)
	return check(ui.snapshot.log.any(func(entry): return entry.begins_with("Add To Stack:") and entry.contains("Combustible Gearhulk") and entry.contains(name))
		or ui.snapshot.stack.any(func(item): return item.get("targets", []).any(func(target): return str(target.get("name", "")) == name)),
		"Forge's trigger targets %s: %s / %s" % [name, ui.snapshot.log.slice(0, 6), JSON.stringify(ui.snapshot.stack).left(200)])

## Shivan Gorge's two abilities tether as rows that keep their text and draw costs as mana symbols.
func shivan_gorge() -> bool:
	ui._click_card(find_card("Shivan Gorge", "Battlefield").id)
	if not await wait_ready(): return false
	for index in range(10): await ui.get_tree().process_frame
	var tether: Control = ui.interaction_panel.callout
	if not check(tether.visible and not ui.modal.visible and tether.mode_buttons.size() == 2, "Shivan Gorge's abilities are a tether"): return false
	var damage_row: Control = tether.mode_buttons[1]
	if not check(damage_row.get_script() == preload("res://scripts/ui/AbilityOption.gd") and damage_row.effect_view.text.contains("1 damage") and damage_row.cost_view.text.contains("{2}{R}"), "The damage ability keeps its text with a symbol cost line: " + str([damage_row.get("description")])): return false
	await capture("gorge")
	return true

## Persistent Constrictor's "up to one target creature they control": a tether off the Constrictor;
## clicking their creature stages it with a line, Confirm puts the -1/-1 counter on it.
func constrictor() -> bool:
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 200): return check(false, "The Constrictor trigger must ask for a target")
	for index in range(10): await ui.get_tree().process_frame
	var panel: Control = ui.interaction_panel
	if not check(panel.target_tether and panel.callout.visible and not panel.panel.visible, "The target choice is a tether off the Constrictor"): return false
	var bears: Dictionary = {}
	for card in ui.snapshot.players[1].zones.Battlefield:
		if card.name == "Grizzly Bears": bears = card
	ui._click_card(int(bears.id))
	for index in range(10): await ui.get_tree().process_frame
	if not check(panel.target_staged.size() == 1 and int(panel.target_staged[0].id) == int(bears.id) and ui.snapshot.prompt.get("chosen", []).is_empty(), "Clicking their creature stages it locally"): return false
	await ui.get_tree().create_timer(0.3).timeout
	await capture("constrictor")
	panel.callout.yes_button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.players[1].zones.Battlefield.any(func(card): return card.name == "Grizzly Bears" and int(card.get("counters", {}).get("M1M1", 0)) == 1) or ui.snapshot.players[1].zones.Graveyard.any(func(card): return card.name == "Grizzly Bears")): return check(false, "Confirm puts the -1/-1 counter on the Bears")
	return true

## Scry shows only the cards you look at, face up, on a tether: Temple of Malice's scry 1 sends
## Lightning Bolt to the bottom; Preordain's scry 2 then offers the next two (proving it), keeps the
## Bears on top and bottoms the Wurm, so its draw is the Bears. Hidden library cards never appear.
func scry_order() -> bool:
	if not await tap("Island", 4) or not await cast("Foresee"): return false
	if not await pass_until(func(): return not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "scry"): return check(false, "Foresee opens a scry decision")
	var ask: Dictionary = ui.snapshot.asks[0]
	var shown: Array = ask.options.map(func(option): return option.card.name)
	if not check(shown == ["Lightning Bolt", "Grizzly Bears", "Craw Wurm", "Serra Angel"], "Foresee offers the top four cards in order and leaves the fifth hidden"): return false
	var tether: Control = ui.interaction_panel.callout
	if not check(tether.visible and not ui.modal.visible, "Library placement uses the existing tether"): return false
	tether.scry_toggles[2].pressed.emit()
	tether.scry_toggles[3].pressed.emit()
	tether.scry_order.move(1, 0)
	tether.scry_bottom_order.move(1, 0)
	await capture("split-order")
	tether.yes_button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.asks.is_empty() and ui.snapshot.stack.is_empty()): return false
	var drawn: Array = zone("Hand").filter(func(card): return card.name in ["Lightning Bolt", "Grizzly Bears", "Craw Wurm", "Serra Angel"]).map(func(card): return card.name)
	if not check(drawn == ["Grizzly Bears", "Lightning Bolt"], "Foresee draws the reordered top two cards: " + str(drawn)): return false
	if not await tap("Island") or not await cast("Index"): return false
	if not await pass_until(func(): return not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "order"): return check(false, "Index exposes the remaining library order")
	var remaining: Array = ui.snapshot.asks[0].options.map(func(option): return option.card.name)
	if not check(remaining == ["Forest", "Serra Angel", "Craw Wurm"], "Index sees the previously hidden Forest, then the newly ordered bottom cards: " + str(remaining)): return false
	submit_choice()
	return await settle()

func scry() -> bool:
	var tether: Control = ui.interaction_panel.callout
	ui._click_card(find_card("Temple of Malice").id)
	if not await pass_until(func(): return not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "scry"): return check(false, "Temple of Malice must ask to scry: " + JSON.stringify(ui.snapshot.asks).left(300))
	for index in range(10): await ui.get_tree().process_frame
	var ask: Dictionary = ui.snapshot.asks[0]
	if not check(ask.options.size() == 1 and ask.options[0].card.get("name", "") == "Lightning Bolt" and not ask.options[0].card.get("hidden", false), "Scry 1 offers only the top card, face up: " + str(ask.options.map(func(option): return option.label))): return false
	if not check(tether.visible and not ui.modal.visible and not tether.scry_ask.is_empty(), "The scry is a tether, not a popup"): return false
	if not check(ui.interaction_panel.callout_card == ui.cards.get(int(find_card("Temple of Malice", "Battlefield").get("id", -1))), "It hangs off Temple of Malice"): return false
	tether._flip_scry(0)
	await capture("temple")
	tether.yes_button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.asks.is_empty() and ui.snapshot.stack.is_empty()): return false
	await ui.get_tree().create_timer(0.6).timeout # Let the Temple trigger finish settling before casting.
	if not await tap("Island") or not await cast("Preordain"): return false
	if not await pass_until(func(): return not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "scry"): return check(false, "Preordain must ask to scry")
	for index in range(10): await ui.get_tree().process_frame
	ask = ui.snapshot.asks[0]
	var names: Array = ask.options.map(func(option): return str(option.card.get("name", "")))
	if not check(names.size() == 2 and names.has("Grizzly Bears") and names.has("Craw Wurm"), "Scry 2 offers the next two cards (the Bolt went to the bottom): " + str(names)): return false
	if not check(tether.visible and not ui.modal.visible, "A scry from a spell is a tether too (off the spell if it is on screen, else centered)"): return false
	tether._flip_scry(names.find("Craw Wurm"))
	await capture("preordain")
	tether.yes_button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.asks.is_empty() and ui.snapshot.stack.is_empty() and zone("Hand").any(func(card): return card.name == "Grizzly Bears")): return check(false, "Preordain should draw the kept Grizzly Bears: " + str(zone("Hand").map(func(card): return card.name)))
	return true

func scry_whole_library() -> bool:
	if not await tap("Island") or not await cast("Preordain"): return false
	if not await pass_until(func(): return not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "scry"): return check(false, "Preordain asks to scry")
	var tether: Control = ui.interaction_panel.callout
	if not check(tether.visible and tether.scry_toggles.size() == 2 and ui.snapshot.players[0].libraryCount == 2, "Both remaining cards are offered"): return false
	tether.scry_toggles[0].pressed.emit()
	tether.scry_toggles[1].pressed.emit()
	tether.scry_bottom_order.move(1, 0)
	tether.yes_button.pressed.emit()
	if not await pass_until(func(): return not find_card("Preordain", "Graveyard").is_empty(), 40): return false
	return check(not find_card("Craw Wurm", "Hand").is_empty() and ui.snapshot.log.any(func(entry): return entry.contains("scried 2 card(s) to the bottom")),
		"Forge draws the first reordered card and records both cards as sent to the bottom: " + str(ui.snapshot.log.slice(0, 10)))
## Plainscycling Angel of the Ruins: the library search is linked to your graveyard (the Angel went
## there to pay for the cycle), and picking a Plains puts it in your hand.
func plainscycling() -> bool:
	if not await tap("Plains", 2): return false
	ui._click_card(find_card("Angel of the Ruins").id)
	var tether: Control = ui.interaction_panel.callout
	for index in range(60):
		if not await wait_ready(): return false
		if ui.modal.visible and ui.modal_panel is SelectionDialog and ui.modal_panel.carousel_mode: break
		if tether.visible and not tether.mode_ask.is_empty():
			for i in range(tether.mode_ask.options.size()):
				if str(tether.mode_ask.options[i].get("label", "")).to_lower().contains("cycling"): tether.mode_buttons[i].pressed.emit()
			continue
		if not ui.snapshot.asks.is_empty(): submit_choice()
		await ui.get_tree().create_timer(0.2).timeout
	if not check(ui.modal.visible and ui.modal_panel is SelectionDialog and ui.modal_panel.carousel_mode, "Plainscycling opens the library search"): return false
	for index in range(20): await ui.get_tree().process_frame
	if not check(ui.search_link.visible and ui._search_anchor() == ui.hud_values[0].zones.Graveyard, "The search is linked to your graveyard, where the Angel went"): return false
	if not check(ui.modal_panel.carousel_source_box.visible and ui.modal_panel.carousel_source.data.get("name", "") == "Angel of the Ruins" and ui.modal_panel.carousel_source.size.y >= 400, "The Angel sits full size beside the carousel"): return false
	await capture("search")
	var search: Control = ui.modal_panel
	for r in range(search.groups.size()):
		if search.options[search.groups[r][0]].get("name", "") == "Plains": search._stage_group(r)
	search.confirm_button.pressed.emit()
	if not await pass_until(func(): return zone("Hand").any(func(card): return card.name == "Plains")): return check(false, "The Plains goes to your hand")
	return true

## Another player's reveal (their Lay of the Land finding a basic land) is a small notice on your
## screen: the source card, an arrow to the revealed card; no question, nothing waits on you.
func opponent_reveal() -> bool:
	var effect: Control = ui.incoming_effect
	var asked := false
	if not await pass_until(func():
		if not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "message": asked = true
		return effect.notice_panel.visible and str(effect.notice_active.get("kind", "")) == "reveal", 150): return check(false, "The reveal must arrive as a small notice (asked=%s) events=%s p1hand=%s stack=%s notices=%s" % [asked, JSON.stringify(ui.snapshot.get("targetedEffects", [])).left(400), ui.snapshot.players[1].get("handCount", -1), ui.snapshot.stack.size(), [effect.notice_active.get("kind", ""), effect.notices.size(), effect.notice_panel.visible]])
	if not check(not asked and not ui.modal.visible, "No question or popup for another player's reveal"): return false
	var revealed: Array = effect.notice_active.get("targets", []).map(func(target): return str(target.get("name", "")))
	if not check(revealed.size() == 1 and str(effect.notice_active.get("source", {}).get("name", "")) == "Lay of the Land", "The notice names the source and the revealed card: " + str(revealed)): return false
	await capture("notice")
	return true


## Combat reasons: your creatures that can't block are tagged before you try (Pacifism, tapped), and a
## refused block says why (Craw Wurm can't block the flying Serra Angel).
func combat_reasons() -> bool:
	var prompt: Dictionary = ui.snapshot.prompt
	var unable: Dictionary = prompt.get("cantBlock", {})
	var bears := find_card("Grizzly Bears", "Battlefield")
	var elves := find_card("Llanowar Elves", "Battlefield")
	var wurm := find_card("Craw Wurm", "Battlefield")
	print("SCENARIO cantBlock: ", unable)
	if not check(str(unable.get(str(bears.id), "")).contains("Pacifism") and str(unable.get(str(elves.id), "")).contains("tapped") and not unable.has(str(wurm.id)), "Pacifism'd Bears and tapped Elves are marked with their reasons; the Wurm is not"): return false
	for index in range(10): await ui.get_tree().process_frame
	if not check(str(ui.cards[int(bears.id)].data.get("unableTag", "")) == "CAN'T BLOCK" and str(ui.cards[int(wurm.id)].data.get("unableTag", "")).is_empty(), "The table tags them CAN'T BLOCK"): return false
	await capture("marked")
	var angel: Dictionary = {}
	var guide: Dictionary = {}
	for card in ui.snapshot.players[1].zones.Battlefield:
		if card.name == "Serra Angel": angel = card
		if card.name == "Goblin Guide": guide = card
	ui._click_card(int(angel.id))
	if not await wait_ready(): return false
	ui._click_card(int(wurm.id))
	for index in range(30):
		await ui.get_tree().process_frame
		if ui.explain_note != null and ui.explain_note.visible: break
	if not check(ui.explain_note != null and ui.explain_note.visible and ui.explain_label.text.contains("flying"), "A refused block says why: " + (ui.explain_label.text if ui.explain_label != null else "(no note)")): return false
	await capture("explained")
	ui._click_card(int(guide.id))
	if not await wait_ready(): return false
	ui._click_card(int(bears.id))
	for index in range(30): await ui.get_tree().process_frame
	return check(ui.explain_label.text.contains("Pacifism"), "Blocking with the Pacified Bears names Pacifism: " + ui.explain_label.text)

## Attack reasons: at Declare attackers, a defender and a summoning-sick creature are tagged
## CAN'T ATTACK with Forge's reason; a creature that can attack is not.
func attack_reasons() -> bool:
	for index in range(30):
		if ui.snapshot.prompt.get("inputKind", "") == "InputAttack": break
		if not await step() or not await wait_ready(): return false
	if not check(ui.snapshot.prompt.get("inputKind", "") == "InputAttack", "Reach attacker declaration"): return false
	var unable: Dictionary = ui.snapshot.prompt.get("cantAttack", {})
	print("SCENARIO cantAttack: ", unable)
	var wall := find_card("Wall of Stone", "Battlefield")
	var ogre := find_card("Gray Ogre", "Battlefield")
	var bears := find_card("Grizzly Bears", "Battlefield")
	if not check(str(unable.get(str(wall.id), "")).contains("defender") and str(unable.get(str(ogre.id), "")).contains("summoning sickness") and not unable.has(str(bears.id)), "The Wall (defender) and the new Ogre are marked with their reasons; the Bears are not"): return false
	for index in range(10): await ui.get_tree().process_frame
	if not check(str(ui.cards[int(ogre.id)].data.get("unableTag", "")) == "CAN'T ATTACK", "The table tags them CAN'T ATTACK"): return false
	await capture("marked")
	return true

## Another player's choice (the AI's Secluded Courtyard naming a creature type) is an information
## tether off the Courtyard once it is on their board; never a popup, OK only clears it.
func courtyard() -> bool:
	var panel: Control = ui.interaction_panel
	var asked := false
	if not await pass_until(func():
		if not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "message": asked = true
		return panel.info_tether.visible, 150): return check(false, "The choice must show as a tether (asked=%s, events=%s)" % [asked, JSON.stringify(ui.snapshot.get("targetedEffects", [])).left(300)])
	for index in range(10): await ui.get_tree().process_frame
	var courtyard: Dictionary = {}
	for card in ui.snapshot.players[1].zones.Battlefield:
		if card.name == "Secluded Courtyard": courtyard = card
	if not check(not asked and not ui.modal.visible, "No popup for another player's choice"): return false
	if not check(not courtyard.is_empty() and panel.info_card == ui.cards.get(int(courtyard.id)), "It hangs off the Courtyard on their board"): return false
	if not check(panel.info_tether.line.text.contains("chose"), "It says what they chose: " + panel.info_tether.line.text): return false
	await capture("choice")
	panel.info_tether.yes_button.pressed.emit()
	for index in range(5): await ui.get_tree().process_frame
	return check(not panel.info_tether.visible, "OK clears it")

## Maze of Ith clicked while declaring blockers is not a refused block: it queues with a note, the
## seat keeps the priority after blocks (even on a bot's turn) and Maze activates there, so the
## flying Angel's damage to Jace is prevented.
func maze() -> bool:
	ui._click_card(find_card("Maze of Ith", "Battlefield").id)
	for index in range(10): await ui.get_tree().process_frame
	if not await wait_ready(): return false
	await capture("queued")
	if not check(ui.deferred_activation == int(find_card("Maze of Ith", "Battlefield").id) and ui.explain_note.visible and not ui.explain_label.text.begins_with("✕"), "Clicking Maze of Ith while declaring blockers queues it with a note instead of a refused block: %s deferred=%s note=%s" % [ui.explain_label.text, ui.deferred_activation, ui.explain_note.visible]): return false
	ui._intent("ok")
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 80): return check(false, "Maze of Ith activates once blockers are declared: %s phase=%s deferred=%s log=%s" % [ui.snapshot.prompt.get("inputKind", ""), ui.snapshot.game.phase, ui.deferred_activation, ui.snapshot.log.slice(0, 6)])
	for index in range(10): await ui.get_tree().process_frame
	if not await select_named("Serra Angel"): return false
	if not await pass_until(func(): return ui.snapshot.log.any(func(line): return str(line).contains("Combat Damage") or str(line).contains("End of Combat")), 120): return check(false, "Combat ends")
	var jace: Dictionary = find_card("Jace Beleren", "Battlefield")
	return check(not jace.is_empty() and int(jace.get("counters", {}).get("LOYALTY", 0)) == 3, "Maze of Ith prevents the flying Angel's damage to Jace: " + str(jace.get("counters", {})))

## Duelist's Heritage ("you may have target attacking creature gain double strike") asks yes/no on
## its card before any target. No: nothing to pick and nothing gains double strike. Yes (heritage-yes):
## the target tether follows and Forge's own later "use it?" is answered from that Yes.
func heritage() -> bool:
	return await _heritage(false)

func heritage_yes() -> bool:
	return await _heritage(true)

func _heritage(use: bool) -> bool:
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputAttack", 100): return check(false, "Reach declare attackers")
	for name in ["Grizzly Bears", "Craw Wurm"]:
		ui._click_card(find_card(name, "Battlefield").id)
		ui._choose_player(1)
		if not await wait_ready(): return false
	ui._intent("ok")
	var heritage_id := int(find_card("Duelist's Heritage", "Battlefield").id)
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and int(ui.snapshot.prompt.get("cardId", -1)) == heritage_id, 60): return check(false, "Heritage first asks for an attacking creature")
	var panel: Control = ui.interaction_panel
	if not check(panel.target_tether and panel.callout.visible and panel.target_staged.is_empty(), "The target tether waits for the player's own pick"): return false
	await capture("target")
	if not await select_named("Craw Wurm"): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputConfirm" and int(ui.snapshot.prompt.get("cardId", -1)) == heritage_id, 80): return check(false, "Heritage asks Yes or No when it resolves")
	await capture("use")
	if not check(panel.callout.visible and not panel.target_tether and not panel.callout.no_button.disabled
			and panel.callout.line.text.to_lower().contains("craw wurm"), "The Yes/No tether names the targeted attacker and lets the player decline: " + str(ui.snapshot.prompt) + " / " + panel.callout.line.text): return false
	var button: Button = panel.callout.yes_button if use else panel.callout.no_button
	button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.stack.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority", 80): return check(false, "The trigger finishes after the player's answer")
	var wurm := find_card("Craw Wurm", "Battlefield")
	var bears := find_card("Grizzly Bears", "Battlefield")
	var target := "targeting [Craw Wurm (%d)]" % int(wurm.id)
	if not check(ui.snapshot.log.any(func(entry): return entry.begins_with("Add To Stack:") and entry.contains("Duelist's Heritage") and entry.contains(target)), "Forge puts Heritage on the stack targeting the Wurm's exact instance"): return false
	var strikers := [wurm, bears].filter(func(card): return card.get("keywords", []).has("DOUBLE_STRIKE")).map(func(card): return card.name)
	return check(strikers == (["Craw Wurm"] if use else []), "Double strike went to %s" % [strikers])
func no_legal_blocks() -> bool:
	var prompt: Dictionary = ui.snapshot.prompt
	if not check(prompt.get("noLegalBlocks", false) and ui.interaction_panel.panel.visible, "Forge pauses the attack at the no-blockers decision"): return false
	if not check(ui.interaction_panel.confirm_button.text == "Continue without blockers", "The combat rail offers a clear way to continue"): return false
	var bears := find_card("Grizzly Bears", "Battlefield")
	if not check(str(prompt.get("cantBlock", {}).get(str(bears.id), "")).contains("flying"), "The Bears' block restriction explains flying"): return false
	await capture("no-blockers")
	if not check(int(find_card("Jace Beleren", "Battlefield").get("counters", {}).get("LOYALTY", 0)) == 5 and ui.snapshot.prompt.get("noLegalBlocks", false), "Combat waits before damage"): return false
	ui.interaction_panel.confirm_button.pressed.emit()
	return check(await pass_until(func(): return int(find_card("Jace Beleren", "Battlefield").get("counters", {}).get("LOYALTY", 0)) == 1, 80), "The unblocked Serra Angel deals four damage to Jace after confirmation")

func play_siege_dragons() -> bool:
	if not await tap("Plains", 4) or not await cast("Citadel Siege"): return false
	if not await pass_until(func(): return not ui.snapshot.asks.is_empty(), 80): return false
	return await choose_named("Dragons")

## The same real target decision through the tether (siege-targets) and through the generic rail
## (siege-targets-rail): both must send Forge the same Bears instance and leave the same board.
func siege_targets() -> bool:
	return await _siege_targets(false)

func siege_targets_rail() -> bool:
	return await _siege_targets(true)

func _siege_targets(rail: bool) -> bool:
	ui.interaction_panel.tethers_enabled = not rail
	if not await play_siege_dragons(): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 160): return check(false, "No target prompt for the shrouded creature, then a choice between two Bears")
	for index in range(5): await ui.get_tree().process_frame
	var bears: Array = ui.snapshot.players[2].zones.Battlefield.filter(func(card): return card.name == "Grizzly Bears")
	bears.sort_custom(func(a, b): return int(a.counters.P1P1) < int(b.counters.P1P1))
	var chosen := int(bears[1].id)
	var other := int(bears[0].id)
	# Forge's side of the decision: exactly the second opponent's two Bears, nothing picked yet.
	var offered: Array = ui.snapshot.prompt.selectable.map(func(id): return int(id))
	offered.sort()
	var expected := [chosen, other]
	expected.sort()
	if not check(int(ui.snapshot.game.activePlayer) == int(ui.snapshot.players[2].id) and offered == expected and ui.snapshot.prompt.get("chosen", []).is_empty(), "Forge offers only the second opponent's two Bears: " + str(offered)): return false
	var panel: Control = ui.interaction_panel
	if rail:
		if not check(not panel.target_tether and panel.panel.visible and not panel.callout.visible, "With tethers off, the generic rail takes the target decision"): return false
	elif not check(panel.target_tether and panel.callout.visible, "The tether takes the target decision"): return false
	await capture("rail" if rail else "tether")
	ui.adapter.sent_requests = []
	var view: Control = ui.cards[chosen]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.get_global_transform_with_canvas() * (view.size * 0.5)
	click.global_position = click.position
	ui.get_viewport().push_input(click, true)
	click.pressed = false
	ui.get_viewport().push_input(click, true)
	if rail:
		if not check(ui.target_staged.is_empty(), "The rail stages nothing locally"): return false
	else:
		if not check(ui.target_staged.map(func(target): return int(target.id)) == [chosen] and ui.adapter.sent_requests.is_empty(), "The battlefield click stages the intended Bears instance without sending"): return false
		panel.callout.yes_button.pressed.emit()
	if not await pass_until(func(): return not ui.snapshot.stack.is_empty() and ui.snapshot.stack[0].get("sourceName", "") == "Citadel Siege", 40): return check(false, "The chosen target puts the Siege trigger on the stack")
	# The wire: one card action naming the chosen instance, whichever presentation sent it.
	var picks: Array = ui.adapter.sent_requests.filter(func(request): return request.get("type", "") == "action" and request.get("action", "") in ["card", "player"])
	var actions: Array = ui.adapter.sent_requests.map(func(request): return str(request.get("action", request.get("type", ""))))
	if not check(picks.size() == 1 and int(picks[0].get("id", -1)) == chosen, "Sent exactly one pick for the chosen Bears: " + str(actions) + " " + str(picks)): return false
	if not check(ui.snapshot.stack[0].targets.map(func(target): return int(target.id)) == [chosen], "Forge's Siege trigger targets the same instance"): return false
	# Siege taps at the beginning of combat; the AI may attack with the other Bears in the same update,
	# so judge each by why it is tapped: Siege's target never attacks, the other only taps by attacking.
	var bear := func(id: int) -> Dictionary:
		var found: Array = ui.snapshot.players[2].zones.Battlefield.filter(func(card): return int(card.id) == id)
		return found[0] if not found.is_empty() else {}
	var attacked := func(id: int) -> bool: return ui.snapshot.log.any(func(entry): return str(entry).begins_with("Combat:") and str(entry).contains("(%d)" % id))
	if not await pass_until(func(): return bear.call(chosen).get("tapped", false) or bear.call(other).get("tapped", false), 60): return check(false, "Siege taps a Bears: " + str(ui.snapshot.log.slice(0, 8)))
	return check(bear.call(chosen).get("tapped", false) and not attacked.call(chosen) and (not bear.call(other).get("tapped", true) or attacked.call(other)),
		"Forge taps only the selected Bears: chosen=%s other=%s log=%s" % [bear.call(chosen).get("tapped"), bear.call(other).get("tapped"), ui.snapshot.log.slice(0, 8)])

## A permanent's ability whose legal targets are off the table (cards in a graveyard): the tether
## declines at once and the generic card window takes it. Picking the second of two
## identical Bears sends that exact instance, and Forge exiles it and leaves the other.
func ooze_graveyard_target() -> bool:
	ui.adapter.sent_requests = []
	ui._click_card(find_card("Scavenging Ooze", "Battlefield").id)
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 40): return check(false, "Ooze asks for a graveyard target: " + str(ui.snapshot.prompt))
	for index in range(5): await ui.get_tree().process_frame
	var graveyard: Array = ui.snapshot.players[1].zones.Graveyard.filter(func(card): return card.name == "Grizzly Bears")
	if not check(graveyard.size() == 2, "Two Bears in AI 1's graveyard"): return false
	var chosen := int(graveyard[1].id)
	var other := int(graveyard[0].id)
	var offered: Array = ui.snapshot.prompt.selectable.map(func(id): return int(id))
	if not check(offered.has(chosen) and offered.has(other), "Forge offers both graveyard Bears: " + str(offered)): return false
	var panel: Control = ui.interaction_panel
	# The generic floor for targets off the table is the card window, opened straight away.
	if not check(not panel.target_tether and not panel.callout.visible and ui.modal.visible and ui.modal_panel is SelectionDialog, "No tether: the card window takes the decision: tether=%s callout=%s rail=%s modal=%s" % [panel.target_tether, panel.callout.visible, panel.panel.visible, (ui.modal_panel.get_script().resource_path.get_file() if ui.modal.visible and is_instance_valid(ui.modal_panel) else "none")]): return false
	await capture("browser")
	ui.adapter.sent_requests = []
	var dialog = ui.modal_panel
	# Target windows list each instance; click the row for the chosen copy.
	var row := -1
	for index in range(dialog.options.size()):
		if int(dialog.options[index].get("id", -1)) == chosen: row = index
	if not check(row >= 0, "The window lists the chosen Bears instance: " + str(dialog.options.map(func(option): return [option.get("name", ""), option.get("id", -1)]))): return false
	dialog.option_buttons[row].pressed.emit()
	if not await wait_ready(): return false
	if is_instance_valid(dialog) and dialog is SelectionDialog and ui.modal.visible and not dialog.confirm_button.disabled: dialog.confirm_button.pressed.emit()
	if not await pass_until(func(): return str(ui.snapshot.prompt.get("inputKind", "")).begins_with("InputPayMana"), 30): return check(false, "Forge asks for {G} after the target")
	if ui.modal.visible and ui.modal_panel is ManaPaymentDialog: ui.modal_panel.sources_button.pressed.emit()
	if not await tap("Forest"): return false
	if not await pass_until(func(): return ui.snapshot.log.any(func(entry): return entry.begins_with("Resolve Stack: Scavenging Ooze")), 60): return check(false, "The Ooze ability resolves: " + str(ui.snapshot.prompt))
	var picks: Array = ui.adapter.sent_requests.filter(func(request): return request.get("type", "") == "action" and request.get("action", "") == "card" and offered.has(int(request.get("id", -1))))
	if not check(picks.size() == 1, "One target pick sent: " + str(ui.adapter.sent_requests.map(func(request): return [request.get("action", request.get("type", "")), request.get("id", -1)]))): return false
	var sent := int(picks[0].id)
	var left: Array = ui.snapshot.players[1].zones.Graveyard.map(func(card): return int(card.id))
	var exiled: Array = ui.snapshot.players[1].zones.Exile.map(func(card): return int(card.id))
	return check(sent == chosen and exiled == [chosen] and left == [other], "Forge exiles exactly the chosen Bears instance: sent=%d chosen=%d graveyard=%s exile=%s" % [sent, chosen, left, exiled])

func siege_ward() -> bool:
	if not await play_siege_dragons(): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 120): return check(false, "Dragons asks before targeting the sole creature")
	if not check(ui.interaction_panel.target_tether and ui.snapshot.prompt.selectable.size() == 1, "The existing tether offers the sole legal target"): return false
	await capture("sole-target")
	if not check(ui.snapshot.prompt.get("chosen", []).is_empty() and ui.snapshot.stack.is_empty(), "Forge waits before ward goes on the stack"): return false
	if not await select_named("Stella Lee, Wild Card"): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputPayManaOfCostPayment", 120): return false
	if not check(ui.modal.visible and ui.modal_panel is ManaPaymentDialog, "Ward opens the existing payment popup"): return false
	await capture("ward")
	if not check(ui.modal_panel.cancel_button.text == "Skip ward payment", "Ward payment explains what is being declined"): return false
	var explanation: String = ui.snapshot.prompt.get("wardContext", "")
	if not check(explanation.contains("Citadel Siege") and explanation.contains("Stella Lee") and explanation.contains("counters it"), "Ward names the source, target and consequence"): return false
	var first_resolutions: int = ui.snapshot.log.filter(func(entry): return entry.begins_with("Resolve Stack: Citadel Siege")).size()
	ui.modal_panel.sources_button.pressed.emit()
	if not await tap("Plains"): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("wardMana", "") == "{3}", 30):
		return check(false, "After paying one mana, Forge reports exactly three still due: " + str(ui.snapshot.prompt.get("wardMana", "")))
	if not check(ui.modal.visible and ui.modal_panel is ManaPaymentDialog and not ui.modal_panel.cancel_button.disabled, "The player can still skip after partial payment"): return false
	await capture("partial-ward")
	ui.modal_panel.cancel_button.pressed.emit()
	if not await pass_until(func(): return int(ui.snapshot.game.activePlayer) == int(ui.snapshot.players[2].id) and ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 160): return check(false, "Dragons offers a target again on the next opponent's turn")
	if not check(ui.snapshot.log.filter(func(entry): return entry.begins_with("Resolve Stack: Citadel Siege")).size() <= first_resolutions, "Skipping ward prevents the first Siege trigger from resolving"): return false
	if not await select_named("Stella Lee, Wild Card"): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputPayManaOfCostPayment", 120): return check(false, "The second ward payment follows target confirmation")
	for index in range(4):
		if ui.modal.visible and ui.modal_panel is ManaPaymentDialog: ui.modal_panel.sources_button.pressed.emit()
		if not await tap("Plains"): return false
	return check(await pass_until(func():
		var second: Dictionary = ui.snapshot.players[2].zones.Battlefield.filter(func(card): return card.name == "Stella Lee, Wild Card")[0]
		return second.tapped and not ui.snapshot.log.any(func(entry): return entry.begins_with("Combat:") and entry.contains("Stella Lee") and entry.contains("(%s)" % second.id))
	, 80), "Paid ward lets Siege tap the second Stella before she can attack")

func skate() -> bool:
	if not await tap("Island", 5) or not await cast("Deepglow Skate"): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 100): return check(false, "Deepglow Skate's trigger asks for targets")
	for index in range(10): await ui.get_tree().process_frame
	if not check(ui.interaction_panel.target_tether, "The targets are a tether off the Skate"): return false
	# Checked sending: a pick Forge refuses stops the send and is unmarked, never a silent wait.
	# Skate targets permanents only, so a player is refused.
	ui.target_staged = [{"kind": "player", "id": 1, "name": "AI 1"}]
	ui.interaction_panel.set_target_staged(ui.target_staged)
	ui._commit_targets()
	var started := Time.get_ticks_msec()
	while ui.target_committing and Time.get_ticks_msec() - started < 6000: await ui.get_tree().process_frame
	if not check(not ui.target_committing and ui.target_staged.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", "A refused pick ends the send and is unmarked"): return false
	if not await wait_ready(): return false # The refusal resyncs the table first.
	for index in range(10): await ui.get_tree().process_frame
	ui.adapter.sent_requests = []
	for name in ["Grizzly Bears", "Jace Beleren"]:
		ui._click_card(find_card(name, "Battlefield").id)
		for index in range(5): await ui.get_tree().process_frame
	if not check(ui.interaction_panel.target_staged.size() == 2, "Both permanents are staged"): return false
	ui.interaction_panel.callout.yes_button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.stack.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority", 80): return check(false, "Confirm sends both targets and the trigger resolves: " + str(ui.snapshot.prompt.get("chosen", [])))
	return _skate_outcome([int(find_card("Grizzly Bears", "Battlefield").id), int(find_card("Jace Beleren", "Battlefield").id)])

## Deepglow Skate's two targets through the rail (skate-rail; the tether run is skate): each click
## is its own pick on the wire, and Forge doubles the same two permanents' counters.
func skate_rail() -> bool:
	ui.interaction_panel.tethers_enabled = false
	if not await tap("Island", 5) or not await cast("Deepglow Skate"): return false
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 100): return check(false, "Deepglow Skate's trigger asks for targets")
	for index in range(10): await ui.get_tree().process_frame
	var panel: Control = ui.interaction_panel
	if not check(not panel.target_tether and panel.panel.visible, "With tethers off, the rail takes the targets"): return false
	var wanted := [int(find_card("Grizzly Bears", "Battlefield").id), int(find_card("Jace Beleren", "Battlefield").id)]
	ui.adapter.sent_requests = []
	for id in wanted:
		ui._click_card(id)
		if not await wait_ready(): return false
	if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and not panel.confirm_button.disabled: panel.confirm_button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.stack.is_empty() and ui.snapshot.prompt.get("inputKind", "") == "InputPassPriority", 80): return check(false, "The rail's picks resolve the trigger: " + str(ui.snapshot.prompt.get("chosen", [])))
	return _skate_outcome(wanted)

## Shared by both Skate runs: the two picks on the wire in order, and both counters doubled.
func _skate_outcome(wanted: Array) -> bool:
	var picks: Array = ui.adapter.sent_requests.filter(func(request): return request.get("type", "") == "action" and request.get("action", "") in ["card", "player"]).map(func(request): return int(request.get("id", -1)))
	if not check(picks == wanted, "Sent exactly the two picks %s, got %s" % [wanted, picks]): return false
	var bears := int(find_card("Grizzly Bears", "Battlefield").get("counters", {}).get("P1P1", 0))
	var jace := int(find_card("Jace Beleren", "Battlefield").get("counters", {}).get("LOYALTY", 0))
	return check(bears == 4 and jace == 6, "Counters doubled: Bears %d (want 4), Jace %d (want 6)" % [bears, jace])

## A real input replacement during a staged send. Standard Bearer makes Forge offer only Flagbearers
## first; picking one ends that input and Forge asks again for the rest. Staging both Bearers and
## confirming sends the first; the second, still queued, must never reach the replacement input.
## The player then picks it again through the ordinary control and the ability resolves on both.
func flagbearer_replaced() -> bool:
	var invoker := int(find_card("Bane's Invoker", "Battlefield").id)
	ui._click_card(invoker)
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 40): return check(false, "Bane's Invoker asks for targets: " + str(ui.snapshot.prompt))
	for index in range(10): await ui.get_tree().process_frame
	var bearers: Array = ui.snapshot.players[1].zones.Battlefield.filter(func(card): return card.name == "Standard Bearer").map(func(card): return int(card.id))
	var first_input = ui.snapshot.prompt.get("inputId", -1)
	var offered: Array = ui.snapshot.prompt.selectable.map(func(id): return int(id))
	offered.sort()
	bearers.sort()
	print("SCENARIO flagbearer first input: ", first_input, " offered=", offered, " min/max=", ui.snapshot.prompt.get("selMin"), "/", ui.snapshot.prompt.get("selMax"), " tether=", ui.interaction_panel.target_tether)
	if not check(offered == bearers and int(ui.snapshot.prompt.get("selMax", 0)) >= 2, "Forge first offers only the two Flagbearers, up to two"): return false
	if not check(ui.interaction_panel.target_tether, "The targets are a tether off Bane's Invoker"): return false
	# They start as one ×2 pile. A real click on the pile stages one copy, which leaves the pile;
	# a second click on what is left stages the other.
	if not check(ui.cards[bearers[0]].position.distance_to(ui.cards[bearers[1]].position) < ui.cards[bearers[0]].size.x * 0.5, "The two Bearers start as one pile"): return false
	for round in range(2):
		var left: Array = bearers.filter(func(id): return not ui.target_staged.any(func(target): return int(target.id) == id))
		click_view(left[0])
		for index in range(10): await ui.get_tree().process_frame
		if not check(ui.target_staged.size() == round + 1, "Click %d on the pile stages one more Bearer: %s" % [round + 1, ui.target_staged]): return false
	var staged: Array = ui.target_staged.map(func(target): return int(target.id))
	staged.sort()
	if not check(staged == bearers, "Both Bearers are staged locally"): return false
	if not check(ui.cards[bearers[0]].position.distance_to(ui.cards[bearers[1]].position) >= ui.cards[bearers[0]].size.x * 0.9, "Staged copies leave the pile"): return false
	if not check(bearers.all(func(id): return int(ui.cards[id].data.get("stackCount", 1)) == 1), "Split copies show no pile badge: " + str(bearers.map(func(id): return ui.cards[id].data.get("stackCount", 1)))): return false
	bearers = ui.target_staged.map(func(target): return int(target.id)) # Send order.
	await capture("staged")
	ui.adapter.sent_requests = []
	ui.interaction_panel.callout.yes_button.pressed.emit()
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputId", -1) != first_input, 40): return check(false, "Forge replaces the input after the first Bearer: " + str(ui.snapshot.prompt))
	# Give a stale queued pick every chance to go out.
	await ui.get_tree().create_timer(2.5).timeout
	if not await wait_ready(): return false
	var picks: Array = ui.adapter.sent_requests.filter(func(request): return request.get("type", "") == "action" and request.get("action", "") in ["card", "player", "ok"]).map(func(request): return [request.action, int(request.get("id", -1))])
	var prompt: Dictionary = ui.snapshot.prompt
	print("SCENARIO flagbearer replacement: ", prompt.get("inputKind", ""), " input=", prompt.get("inputId", -1), " chosen=", prompt.get("chosen", []), " offered=", prompt.get("selectable", []), " sent=", picks)
	if not check(picks == [["card", bearers[0]]], "Only the first Bearer was sent; the queued one never reached the new input: " + str(picks)): return false
	if not check(prompt.get("inputKind", "") == "InputSelectTargets" and prompt.get("chosen", []).has("card:%d" % bearers[0]) and not prompt.get("chosen", []).has("card:%d" % bearers[1]), "The replacement input holds only the accepted Bearer"): return false
	if not check(not ui.target_committing and ui.target_staged.is_empty(), "The stale send ended and nothing stays staged"): return false
	if not check(ui.cards[bearers[0]].position.distance_to(ui.cards[bearers[1]].position) >= ui.cards[bearers[0]].size.x * 0.9, "The accepted Bearer stays out of the pile, so the other is clickable"): return false
	if not check(prompt.get("selectable", []).map(func(id): return int(id)).has(bearers[1]), "The second Bearer is still a legal pick"): return false
	await capture("replaced")
	# The player picks it again through whatever control now shows the question.
	if not await select_named_id(bearers[1]): return false
	if not await pass_until(func(): return str(ui.snapshot.prompt.get("inputKind", "")).begins_with("InputPayMana"), 40): return check(false, "Forge asks for the cost after targets: " + str(ui.snapshot.prompt))
	if ui.modal.visible and ui.modal_panel is ManaPaymentDialog: ui.modal_panel.sources_button.pressed.emit()
	if not await tap("Plains", 8): return false
	if not await pass_until(func(): return ui.snapshot.log.any(func(entry): return entry.begins_with("Resolve Stack: Bane's Invoker")), 80): return check(false, "The ability resolves")
	var pumped: Array = ui.snapshot.players[1].zones.Battlefield.filter(func(card): return bearers.has(int(card.id)) and int(card.get("power", 0)) == 3).map(func(card): return int(card.id))
	pumped.sort()
	bearers.sort()
	return check(pumped == bearers and int(find_card("Grizzly Bears", "Battlefield").get("power", 0)) == 2, "Both Bearers got +2/+2 and nothing else did: " + str(pumped))

## Waits frame by frame (no passing, unlike pass_until) until the test holds or the time runs out.
func wait_for(test: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		if test.call(): return true
		await ui.get_tree().process_frame
	return false

## A real left click at the middle of this card's view, through the viewport.
func click_view(id: int) -> void:
	var view: Control = ui.cards[id]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = view.get_global_transform_with_canvas() * (view.size * 0.5)
	click.global_position = click.position
	ui.get_viewport().push_input(click, true)
	click.pressed = false
	ui.get_viewport().push_input(click, true)

## Picks one exact instance on the current target question with a real click, through the tether or the rail.
func select_named_id(id: int) -> bool:
	for index in range(10): await ui.get_tree().process_frame
	if not check(ui.snapshot.prompt.get("selectable", []).map(func(value): return int(value)).has(id), "Instance %d is a legal target" % id): return false
	click_view(id)
	for index in range(5): await ui.get_tree().process_frame
	if ui.interaction_panel.target_tether:
		if not check(not ui.interaction_panel.callout.yes_button.disabled, "The tether's Confirm enables once the target is staged"): return false
		ui.interaction_panel.callout.yes_button.pressed.emit()
	if not await wait_ready(): return false
	if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and ui.interaction_panel.panel.visible and not ui.interaction_panel.confirm_button.disabled:
		ui.interaction_panel.confirm_button.pressed.emit()
	return await wait_ready()

func optional_target() -> bool:
	ui.adapter.auto_resolve_all = true
	ui._click_card(find_card("Yawgmoth, Thran Physician", "Battlefield").id)
	for index in range(40):
		if not await wait_ready(): return false
		if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets": break
		if not await step(): return false
	var prompt: Dictionary = ui.snapshot.prompt
	var tether: Control = ui.interaction_panel.callout
	var opponents: Array = ui.snapshot.players[1].zones.Battlefield
	var wurm: Dictionary = opponents.filter(func(card): return card.name == "Craw Wurm")[0]
	if not check(prompt.get("inputKind", "") == "InputSelectTargets" and int(prompt.selMin) == 0
		and prompt.selectable.any(func(id): return int(id) == int(wurm.id))
		and ui.interaction_panel.target_tether and not tether.yes_button.disabled, "Yawgmoth offers an explicit empty target choice: " + str({
			"input": prompt.get("inputKind"), "min": prompt.get("selMin"), "selectable": prompt.get("selectable"),
			"wurm": wurm.id, "tether": ui.interaction_panel.target_tether, "disabled": tether.yes_button.disabled,
			"log": ui.snapshot.log.slice(0, 5),
		})): return false
	await ui.get_tree().create_timer(0.3).timeout
	if not check(ui.snapshot.prompt.get("inputId", -1) == prompt.get("inputId", -2), "Auto-resolve leaves the target decision to the player"): return false
	tether.yes_button.pressed.emit()
	if not await settle(): return false
	return check(ui.snapshot.players[0].life == 39 and not find_card("Island", "Hand").is_empty()
		and not find_card("Grizzly Bears", "Graveyard").is_empty()
		and ui.cards.has(int(wurm.id)) and counter(ui.cards[int(wurm.id)].data, "M1M1") == 0,
		"The empty target still spends the cost and draws, without putting a counter on the Wurm")

## Chaos Warp puts Outpost Siege onto the battlefield: its "Khans or Dragons" choice shows the
## Siege (not a blank card) and what each mode does, and picking Dragons lands the Siege.
func outpost() -> bool:
	if not await tap("Mountain", 3) or not await cast("Chaos Warp"): return false
	if not await select_named("Treasure Token"): return false
	if not await pass_until(func(): return not ui.snapshot.asks.is_empty(), 100): return check(false, "Chaos Warp reveals the top card")
	if ui.snapshot.asks[0].kind == "message" and not press_card_tether(): submit_choice()
	if not await pass_until(func(): return not ui.snapshot.asks.is_empty() and ui.snapshot.asks[0].kind == "choose", 100): return check(false, "Outpost Siege asks Khans or Dragons")
	for index in range(20): await ui.get_tree().process_frame
	var ask: Dictionary = ui.snapshot.asks[0]
	var labels: Array = ask.options.map(func(option): return str(option.get("label", "")))
	if not check(ask.options.all(func(option): return str(option.get("card", {}).get("name", "")) == "Outpost Siege"), "Both options show Outpost Siege, not a hidden card"): return false
	if not check(labels[0].begins_with("Khans —") and labels[0].contains("upkeep") and labels[1].begins_with("Dragons —") and labels[1].contains("damage"), "Each option says what it does: " + str(labels)): return false
	if not check(ui.modal.visible and str(ui.modal_panel.ask.get("sourceCard", {}).get("name", "")) == "Outpost Siege", "The popup shows the Siege beside its modes"): return false
	await capture("modes")
	ui.modal_panel._toggle(1)
	ui.modal_panel._submit()
	if not await pass_until(func(): return not find_card("Outpost Siege", "Battlefield").is_empty() and ui.snapshot.asks.is_empty(), 100): return check(false, "Outpost Siege enters with Dragons")
	return true
func monument() -> bool:
	if not await tap("Mountain", 2): return false
	for index in range(10): await ui.get_tree().process_frame
	var ogre := find_card("Gray Ogre")
	var giant := find_card("Hill Giant")
	var krenko := find_card("Krenko, Mob Boss", "Command")
	if not check(str(ogre.get("effectiveCost", "")) == "{1}{R}", "The bridge reports the Monument's reduction: " + str(ogre.get("effectiveCost"))): return false
	if not check(str(krenko.get("effectiveCost", "")) == "{1}{R}{R}", "The commander's cost carries the reduction too: " + str(krenko.get("effectiveCost"))): return false
	if not check(ui._ready_now(ogre, "Hand") and not ui._ready_now(giant, "Hand"), "Floating RR pays the reduced Ogre but not the Giant"): return false
	ui.ui_layout.mana_overlay = 1.0
	ui._apply_table_style()
	await capture("ready")
	return true

## Never a dead end: with the target tether gone (as when the table doesn't recognise a question),
## the guard shows Forge's raw question after a few seconds and saves a bug report with Forge's
## board export; its buttons answer Forge (the Bears get the -1/-1 counter).
func guard() -> bool:
	if not await pass_until(func(): return ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets", 200): return check(false, "The Constrictor trigger must ask for a target")
	var guard_view: Control = ui.decision_guard
	var started := Time.get_ticks_msec()
	while not guard_view.box.visible and Time.get_ticks_msec() - started < 9000:
		ui.interaction_panel.callout.hide()
		ui.interaction_panel.panel.hide()
		ui.primary.disabled = true # "Up to one" also lets OK answer: take every control away.
		ui.cancel_button.disabled = true
		await ui.get_tree().process_frame
	if not check(guard_view.box.visible and Time.get_ticks_msec() - started >= 3500, "The guard shows Forge's question once nothing has answered it for a few seconds"): return false
	var report: String = guard_view.last_report
	for index in range(50):
		if FileAccess.file_exists(report.path_join("board.state")): break
		await ui.get_tree().create_timer(0.1).timeout
	for file in ["snapshot.json", "history.json", "ui.json", "notes.txt", "board.state"] + ([] if DisplayServer.get_name() == "headless" else ["screen.png"]):
		if not check(FileAccess.file_exists(report.path_join(file)), "The report has " + file + ": " + report): return false
	var board := FileAccess.get_file_as_string(report.path_join("board.state"))
	if not check(board.contains("Persistent Constrictor") and board.contains("Grizzly Bears"), "board.state is Forge's board export"): return false
	print("SCENARIO report: ", report)
	await capture("fallback")
	var bears: Array = guard_view.body.find_children("*", "Button", true, false).filter(func(button): return button.text == "Grizzly Bears")
	if not check(bears.size() == 1, "The fallback lists the legal targets"): return false
	bears[0].pressed.emit()
	if not await pass_until(func(): return ui.snapshot.players[1].zones.Battlefield.any(func(card): return card.name == "Grizzly Bears" and int(card.get("counters", {}).get("M1M1", 0)) == 1) or ui.snapshot.players[1].zones.Graveyard.any(func(card): return card.name == "Grizzly Bears"), 100): return check(false, "The fallback's pick reaches Forge")
	return check(not guard_view.box.visible, "The fallback closes once answered")


## Card-shape sweep (tools/shape-sweep.mjs boards): cast the one card in hand and answer every
## question through the table's own controls, the way a player would (step(): tethers, popups,
## the rail). Fails if nothing on screen can answer Forge, the stuck guard steps in, or the card
## never resolves. Which choice is made doesn't matter; that every question is answerable does.
func shape_probe() -> bool:
	var hand: Array = zone("Hand")
	if not check(hand.size() == 1, "A shape board holds one card in hand"): return false
	var card: Dictionary = hand[0]
	print("SHAPE card: ", card.name)
	ui._click_card(int(card.id))
	var cast := false
	for index in range(90):
		if not await wait_ready(): return false
		var state: Dictionary = ui.snapshot
		if not ui.decision_guard.last_report.is_empty():
			return check(false, "SHAPE %s: the stuck guard had to step in (%s). Report: %s" % [card.name, str(state.prompt.get("inputKind", "")), ui.decision_guard.last_report])
		var in_hand: bool = zone("Hand").any(func(entry): return int(entry.id) == int(card.id))
		if not in_hand: cast = true
		var idle: bool = state.asks.is_empty() and state.prompt.get("inputKind", "") == "InputPassPriority"
		if idle and in_hand and not cast and index > 2:
			print("SHAPE skipped: ", card.name, " can't be cast on this board")
			return true
		if idle and cast and state.stack.is_empty():
			print("SHAPE resolved: ", card.name)
			await capture("resolved")
			return true
		if idle and not state.stack.is_empty():
			# Our spell (or a trigger) is waiting to resolve: pass priority like the Resolve button.
			if ui.incoming_effect.showing(): ui.incoming_effect.resolve_button.pressed.emit()
			else: ui._intent("ok")
			continue
		if ui.snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and ui.interaction_panel.target_tether:
			# Stage the first legal target (or player) on the tether, then Confirm, as a player would.
			var legal: Array = state.prompt.get("selectable", [])
			var players: Array = state.prompt.get("entities", []).filter(func(entity): return entity.get("kind", "") == "player")
			if ui.interaction_panel.target_staged.is_empty() and int(state.prompt.get("selMin", 1)) > 0:
				if not legal.is_empty(): ui._click_card(int(legal[0]))
				elif not players.is_empty(): ui.interaction_panel.callout.mode_buttons[0].pressed.emit()
				for frame in range(5): await ui.get_tree().process_frame
			if not ui.interaction_panel.callout.yes_button.disabled:
				ui.interaction_panel.callout.yes_button.pressed.emit()
				continue
		var kind := str(state.prompt.get("inputKind", ""))
		if kind.begins_with("InputPayMana") and state.asks.is_empty():
			# Pay like a player: click the floating mana symbols, else tap a land.
			var pool: Dictionary = state.players[0].get("mana", {})
			var keys: Array = preload("res://scripts/ui/ManaCounter.gd").KEYS
			var paid := false
			for key in pool:
				if int(pool[key]) > 0 and keys.has(key):
					ui._use_mana(keys.find(key))
					paid = true
					break
			if not paid:
				var lands: Array = zone("Battlefield").filter(func(entry): return str(entry.get("typeLine", "")).contains("Land") and not entry.get("tapped", false))
				if lands.is_empty(): return check(false, "SHAPE %s: nothing left to pay with" % card.name)
				ui._click_card(int(lands[0].id))
			continue
		if kind.begins_with("InputSelect") and state.asks.is_empty() and not ui.modal.visible and not ui.interaction_panel.target_tether and not state.prompt.get("okEnabled", false):
			# A required pick from the table (a spell's target from the rail): click the first legal card.
			var chosen: Array = state.prompt.get("chosen", [])
			var open_picks: Array = state.prompt.get("selectable", []).filter(func(id): return not chosen.has("card:" + str(int(id))) and ui.cards.has(int(id)) and ui.cards[int(id)].is_visible_in_tree())
			if not open_picks.is_empty():
				ui._click_card(int(open_picks[0]))
				continue
		if not await step():
			await capture("stuck")
			return check(false, "SHAPE %s: no control on screen answers %s" % [card.name, JSON.stringify(state.prompt).left(300)])
	await capture("timeout")
	return check(false, "SHAPE %s never resolved: %s asks=%s stack=%s" % [card.name, str(ui.snapshot.prompt.get("inputKind", "")), ui.snapshot.asks.map(func(ask): return ask.kind), ui.snapshot.stack.size()])
