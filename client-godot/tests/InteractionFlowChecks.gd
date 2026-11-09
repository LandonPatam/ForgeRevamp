extends RefCounted
const Flow = preload("res://scripts/ui/InteractionFlow.gd")

func run(ui: Control, directory: String = "") -> void:
	var state := {"connectionReady": true, "game": {}, "asks": [], "pendingDraws": [], "stack": [], "autoPassStackId": -1, "prompt": {"inputKind": "InputSelectTargets", "message": "Choose up to two creatures to return to their owners' hands.", "okEnabled": false, "cancelEnabled": true, "cancelLabel": "Cancel", "cards": [{"id": 91}], "entities": [{"id": 1, "kind": "player", "name": "Opponent"}]}}
	var panel = preload("res://scripts/ui/InteractionPanel.gd").new()
	ui.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.present(state, false)
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	assert(panel.panel.size.y < 400, "Contextual controls must stay compact so the board remains playable")
	assert(panel.panel.visible and panel.heading.text == "Choose targets" and panel.confirm_button.disabled)
	var actions: Array = []
	panel.action_requested.connect(func(action): actions.append(action))
	panel.entity_selected.connect(func(action, id): actions.append([action, id]))
	panel.choices.get_child(0).pressed.emit()
	assert(actions == [["player", 1]])
	state.prompt.okEnabled = true
	panel.present(state, false)
	panel.confirm_button.pressed.emit()
	assert(actions.back() == "ok", "Board-side confirmation must use the current native engine input")
	state.prompt.selMin = 0
	state.prompt.chosen = []
	panel.present(state, false)
	assert(panel.confirm_button.text == "Choose none" and not panel.confirm_button.disabled, "An optional empty board selection must clearly offer choosing no targets")
	state.prompt.erase("selMin")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("contextual-target-actions.png"))
	state.prompt.inputKind = "InputSelectEntitiesFromList"
	state.prompt.message = "Atraxa, Praetors' Voice (100)\n\nChoose any number of permanents and/or players for proliferate"
	state.prompt.selectionShortcut = "MINE"
	state.prompt.sourceCard = {"id": 100, "name": "Atraxa, Praetors' Voice", "text": "At the beginning of your end step, proliferate."}
	state.prompt.chosen = []
	state.prompt.selMin = 0
	state.stack = [{"id": 100, "text": "Proliferate"}]
	panel.present(state, false)
	var attention = preload("res://scripts/ui/StackAttention.gd").new()
	attention.stack = ui.stack_box
	attention.decision = panel
	attention.capture_phase = 1
	ui.add_child(attention)
	attention.present(state)
	assert(attention.attention_target() == panel.panel, "A rail decision must receive the pulse instead of the covered stack underneath")
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	if not directory.is_empty(): await ui._save_frame(directory.path_join("proliferate-panel-layout.png"))
	var column: Control = panel.panel.get_child(0)
	var previous_bottom := 0.0
	for child in column.get_children():
		if not child.visible: continue
		assert(child.position.y >= previous_bottom, "Decision text, source card and actions must not overlap")
		previous_bottom = child.position.y + child.size.y
	assert(panel.panel.get_global_rect().end.y <= ui.size.y, "Proliferate actions must fit on screen")
	var preview_top: float = panel.source_view.get_global_rect().position.y
	assert(preview_top >= panel.help.get_global_rect().end.y + 8, "Source preview must reserve space for its visual edges below the instructions")
	if not directory.is_empty():
		var original_size: Vector2i = ui.get_window().size
		ui.capture_size = Vector2i(1280, 800)
		ui.get_window().size = Vector2i(1280, 800)
		await ui.get_tree().process_frame
		await ui.get_tree().process_frame
		await ui.get_tree().process_frame
		await ui._save_frame(directory.path_join("proliferate-panel-layout-1280.png"))
		assert(ui.size == Vector2(1280, 800) and panel.panel.get_global_rect().end.y <= ui.size.y - 20, "The source preview and actions remain accessible at 1280 by 800")
		ui.capture_size = original_size
		ui.get_window().size = original_size
		await ui.get_tree().process_frame
	state.prompt.inputKind = "InputBlock"
	panel.present(state, false)
	assert(attention.attention_target() == panel.panel, "Combat decisions sharing the rail also redirect the pulse")
	state.prompt.erase("selectionShortcut")
	state.prompt.erase("sourceCard")
	state.prompt.inputKind = "InputSelectTargets"
	panel.present(state, false)
	assert(attention.attention_target() == panel.panel, "Target decisions in the rail also redirect the pulse")
	state.prompt.inputKind = "InputConfirm"
	state.prompt.cancelEnabled = true
	panel.present(state, false)
	assert(attention.attention_target() == ui.stack_box, "Decisions away from the rail retain the stack cue")
	attention.queue_free()
	state.stack = []
	for kind in ["InputAttack", "InputBlock", "InputConfirm", "InputPayManaOfCostPayment", "InputSelectCardsForConvokeOrImprovise", "InputUnusualCardDecision"]:
		state.prompt.inputKind = kind
		panel.present(state, false)
		assert(panel.panel.visible, "Every native decision needs a board-side fallback")
	state.connectionReady = false
	panel.present(state, false)
	assert(panel.confirm_button.disabled and panel.cancel_button.disabled)
	state.connectionReady = true
	state.prompt.inputKind = "InputConfirm"
	state.prompt.cancelEnabled = false
	assert(Flow.describe(state).is_empty(), "OK-only confirmations use the rail instead of another center menu")
	state.prompt.cancelEnabled = true
	panel.present(state, true)
	assert(not panel.panel.visible, "Required modals must have exclusive interaction controls")
	state.prompt.inputKind = "InputPassPriority"
	assert(Flow.describe(state).is_empty(), "An empty stack must not become a resolution prompt")
	var item := {"id": 500, "sourceId": 501, "sourceName": "Fathom Mage", "controllerName": "Opponent", "ability": true, "text": "Fathom Mage — draw a card.", "card": {"id": 501, "name": "Fathom Mage", "text": "Several different printed abilities."}, "targets": []}
	state.stack = [item]
	state.pendingCastId = 501
	assert(Flow.describe(state).is_empty(), "A provisional cast must finish its payment before offering resolution")
	state.pendingCastId = -1
	panel.present(state, false)
	assert(not panel.panel.visible, "Routine stack resolution must not create an extra center action panel")
	var popup = preload("res://scripts/ui/IncomingEffect.gd").new()
	panel.present(state, true)
	ui.add_child(popup)
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup.present(state)
	assert(not popup.panel.visible, "Routine abilities remain in the stack rail until explicitly reviewed")
	popup.review()
	assert(popup.panel.visible and popup.active.stackId == 500 and popup.rules.text == item.text, "Any pending ability needs its actual effect text and source, without a targeted-event special case")
	assert(not popup.targets_scroll.visible and popup.resolve_button.text != "Close", "A pending effect offers its accept button, not Close")
	var acknowledged: Array = []
	popup.acknowledged.connect(func(id): acknowledged.append(id))
	popup.browse_button.pressed.emit()
	popup._process(0)
	assert(not popup.panel.visible and acknowledged.is_empty(), "Respond must expose the board without passing priority")
	popup.present(state)
	popup._process(0)
	assert(not popup.panel.visible, "Repeated snapshots must preserve the response window")
	popup.review()
	assert(popup.panel.visible and acknowledged.is_empty())
	state.targetedEffects = [{"id": 8, "stackId": 500, "kind": "targeted", "source": item.card, "effectText": item.text, "targets": []}]
	popup.present(state)
	assert(popup.waiting.is_empty() and popup.active.id == 8, "A late retained notice must upgrade the current effect, not create a duplicate popup")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("general-ability-response.png"))
	popup.resolve_button.pressed.emit()
	popup.present(state)
	assert(acknowledged == [500] and popup.active.is_empty(), "Resolve must acknowledge once without re-opening the same effect")
	state.targetedEffects[0].id = 9
	popup.present(state)
	assert(popup.active.is_empty(), "A late notice for an acknowledged spell must not reappear")
	state.autoPassStackId = 500
	assert(Flow.describe(state).is_empty(), "Automatic local effects must not demand another resolution click")
	popup.reset()
	state.targetedEffects = []
	popup.present(state)
	popup.review()
	popup.respond()
	var resolved := state.duplicate(true)
	resolved.stack = []
	popup.present(resolved)
	assert(popup.active.is_empty() and not popup.panel.visible, "Reviewed response notices must stay closed after resolution or countering")
	popup.reset()
	state.targetedEffects = []
	popup.present(state)
	assert(popup.active.is_empty())
	popup.queue_free()
	# Reproduce the app's two navigation buttons above the turn header. The
	# combat controls must flow below the header rather than cover it at y=172.
	var navigation: Array = []
	for title in ["Main menu", "End game"]:
		var button := Button.new()
		button.text = title
		button.custom_minimum_size.y = 46
		ui.rail.add_child(button)
		ui.rail.move_child(button, navigation.size())
		navigation.append(button)
	panel.rail_host = ui.decision_scroll
	ui.decision_scroll.show()
	ui.stack_scroll.hide()
	ui.rail_space.hide()
	# Live combat hides the ordinary priority/footer controls while the
	# decision owns the rail. Match that layout in this mock-table fixture.
	var ordinary_controls: Array = [ui.stack_header, ui.prompt_body, ui.primary, ui.cancel_button].filter(func(control): return is_instance_valid(control))
	var ordinary_visibility: Array = ordinary_controls.map(func(control): return control.visible)
	for control in ordinary_controls: control.hide()
	state.stack = []
	state.prompt = {"inputKind": "InputAttack", "message": "Select creatures to attack Bot 1 or select player/card you wish to attack.", "cancelEnabled": true, "cancelLabel": "Alpha Strike", "okEnabled": true, "okLabel": "Skip attacking", "chosen": ["card:1"]}
	panel.present(state, false)
	for frame in range(5): await ui.get_tree().process_frame
	assert(panel.panel.get_parent() == ui.decision_scroll, "Combat decisions must be hosted by the sidebar's scroll layout")
	assert(panel.panel.get_global_rect().position.y > ui.phase_title.get_global_rect().end.y, "Attacker actions must stay below the turn and phase headers with app navigation present")
	assert(panel.confirm_button.get_global_rect().end.y <= ui.decision_scroll.get_global_rect().end.y, "Skip attacking must remain reachable inside the sidebar")
	assert(absf(panel.panel.get_global_rect().end.y - ui.decision_scroll.get_global_rect().end.y) < 4, "Short attacker decisions must sit at the bottom of the available rail")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("attacker-sidebar-layout.png"))
	var original_size: Vector2i = ui.get_window().size
	var original_ui_size: Vector2 = ui.size
	var original_capture: Vector2i = ui.capture_size
	state.combat = [{"attacker": 1}]
	for dimensions in [Vector2i(2560, 1440), Vector2i(1280, 800), Vector2i(1600, 1000)]:
		ui.capture_size = dimensions
		ui.get_window().size = dimensions
		await ui.get_tree().create_timer(0.2).timeout
		ui.size = Vector2(dimensions)
		ui.decision_scroll.hide()
		panel.present(state, false)
		ui.decision_scroll.show()
		for frame in range(8): await ui.get_tree().process_frame
		for update in range(3):
			panel.present(state, false)
			for frame in range(2): await ui.get_tree().process_frame
		var host_rect: Rect2 = ui.decision_scroll.get_global_rect()
		assert(host_rect.encloses(panel.confirm_button.get_global_rect()) and host_rect.encloses(panel.cancel_button.get_global_rect()), "Attacker controls must remain inside the scroll viewport immediately after showing it at " + str(dimensions))
		assert(panel.confirm_button.text == "Confirm attacks" and not panel.confirm_button.disabled)
		if not directory.is_empty(): await ui._save_frame(directory.path_join("attacker-visible-%s.png" % dimensions.y))
		var before_clicks: int = actions.size()
		var point: Vector2 = panel.confirm_button.get_global_rect().get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		ui.get_viewport().push_input(motion)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = point
		press.global_position = point
		press.pressed = true
		ui.get_viewport().push_input(press)
		press = press.duplicate()
		press.pressed = false
		ui.get_viewport().push_input(press)
		await ui.get_tree().process_frame
		assert(actions.size() == before_clicks + 1 and actions.back() == "ok", "Confirm attacks must accept a real pointer click without moving a battlefield card at %s: point=%s hovered=%s button=%s host=%s panel=%s content=%s viewport=%s actions=%s" % [dimensions, point, ui.get_viewport().gui_get_hovered_control(), panel.confirm_button, host_rect, panel.panel.get_global_rect(), panel.panel.get_child(0).get_global_rect(), ui.get_viewport_rect(), actions])
	ui.capture_size = original_capture
	ui.get_window().size = original_size
	ui.size = original_ui_size
	await ui.get_tree().create_timer(0.2).timeout
	state.combat = []
	for kind in ["InputBlock", "InputSelectEntitiesFromList", "InputSelectCardsFromList"]:
		state.prompt.inputKind = kind
		if kind.begins_with("InputSelect"):
			state.prompt.selectionShortcut = "MINE"
			state.prompt.sourceCard = {"id": 100, "name": "Atraxa, Praetors' Voice", "text": "Proliferate"}
		panel.present(state, false)
		for frame in range(4): await ui.get_tree().process_frame
		assert(panel.panel.get_parent() == ui.decision_scroll and panel.panel.get_global_rect().position.y > ui.phase_title.get_global_rect().end.y, "Every native sidebar decision must follow navigation and the phase header: " + kind)
	state.prompt.erase("selectionShortcut")
	state.prompt.erase("sourceCard")
	state.prompt.inputKind = "InputSelectTargets"
	state.prompt.sourceCard = {"id": 100, "name": "Terminate", "text": "Destroy target creature."}
	state.prompt.message = "Select target creature to destroy"
	state.stack = []
	panel.present(state, false)
	for frame in range(4): await ui.get_tree().process_frame
	assert(panel.panel.get_parent() == ui.decision_scroll, "Choosing targets must not cover the board")
	assert(panel.panel.get_global_rect().position.x >= ui.board_scroller.get_global_rect().end.x, "The target prompt sits entirely beside the board")
	assert(not panel.keeps_stack_visible(), "An empty stack gives the decision the whole rail")
	assert(panel.confirm_button.get_global_rect().end.y < panel.source_view.get_global_rect().position.y, "Confirm comes before the source card, so it stays in view")
	ui.decision_scroll.get_v_scroll_bar().value = 0
	if not directory.is_empty(): await ui._save_frame(directory.path_join("target-prompt-in-rail.png"))
	state.stack = [{"id": 501, "sourceId": 502, "text": "Counter target spell.", "card": {"id": 502, "name": "Counterspell"}}]
	panel.present(state, false)
	assert(panel.keeps_stack_visible(), "A spell on the stack can be the target, so the stack stays in the rail")
	state.stack = []
	state.prompt.erase("sourceCard")
	state.prompt.inputKind = "InputConfirm"
	state.prompt.cancelEnabled = true
	panel.present(state, false)
	assert(panel.panel.get_parent() == panel, "Decisions that pick nothing on the board may leave the rail host")
	assert(panel.source_frame.get_index() == 3, "Back on the board the source card returns above the actions")
	panel.present(state, true)
	var recipient_ask := {"id": 99990, "min": 0, "max": 1, "title": "Choose recipients. " + "Long effect instructions. ".repeat(100), "options": [{"cardId": 1, "controllerId": 0}], "localPlayerId": 0}
	ui.board_choice.present(recipient_ask, {}, true)
	for frame in range(6): await ui.get_tree().process_frame
	assert(ui.board_choice.panel.get_parent() == ui.decision_scroll and ui.decision_scroll.visible and not ui.stack_scroll.visible, "Callback recipient effects must share the same exclusive sidebar slot")
	assert(ui.board_choice.panel.get_global_rect().position.y > ui.phase_title.get_global_rect().end.y, "Recipient effects must not cover the phase heading")
	var scrollbar: VScrollBar = ui.decision_scroll.get_v_scroll_bar()
	assert(scrollbar.max_value > scrollbar.page, "Long decisions must scroll instead of overlapping the sidebar footer")
	ui.decision_scroll.scroll_vertical = int(scrollbar.max_value)
	for frame in range(3): await ui.get_tree().process_frame
	assert(ui.decision_scroll.get_global_rect().intersects(ui.board_choice.confirm_button.get_global_rect()), "Scrolling must make the final recipient action reachable")
	recipient_ask = recipient_ask.duplicate(true)
	recipient_ask.id = 99991
	recipient_ask.title = "Proliferate: choose recipients"
	ui.board_choice.present(recipient_ask, {}, true)
	for frame in range(4): await ui.get_tree().process_frame
	assert(ui.decision_scroll.scroll_vertical == 0, "New decisions must start at the top rather than inherit the previous scroll")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("recipient-sidebar-layout.png"))
	ui.board_choice.hide()
	assert(not ui.board_choice.panel.visible and not ui.decision_scroll.visible, "Finished recipient effects must release the sidebar slot")
	ui.decision_scroll.hide()
	ui.stack_scroll.show()
	ui.rail_space.show()
	for index in range(ordinary_controls.size()): ordinary_controls[index].visible = ordinary_visibility[index]
	for button in navigation: button.queue_free()
	panel.queue_free()
	await ui.get_tree().process_frame
	print("PASS: required native decisions, board targeting, stack galleries and explicit effect review without routine popups")
