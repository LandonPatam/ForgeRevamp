extends RefCounted

func run(ui: Control, directory: String = "") -> void:
	var popup = preload("res://scripts/ui/IncomingEffect.gd").new()
	ui.add_child(popup)
	popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var unrelated := {"connectionReady": true, "prompt": {"inputKind": "InputPassPriority", "okEnabled": true}, "stack": [{"id": 8000, "targetsLocal": false, "card": {"id": 8001, "name": "Giant Growth"}, "targets": [{"id": 8002, "kind": "card", "name": "Another player's creature"}]}]}
	popup.present(unrelated)
	assert(not popup.panel.visible and popup.active.is_empty(), "Targeting someone else must not demand a local acknowledgment")
	popup.review()
	assert(popup.panel.visible, "An unrelated effect remains available for explicit review when responding")
	popup.reset()
	# A targeted player shows as a portrait tile with their name, never a word-wrapped "Y o u".
	var at_player := {"connectionReady": true, "prompt": {"inputKind": "InputPassPriority"}, "players": [{"id": 0, "engineId": 41, "name": "Landon", "avatar": 3, "life": 40}], "stack": [], "targetedEffects": [{"id": 1, "stackId": 8100, "controllerName": "Opponent", "source": {"id": 8101, "name": "Lightning Bolt"}, "targets": [{"id": 41, "kind": "player", "name": "Landon"}]}]}
	popup.present({"stack": [], "targetedEffects": []})
	popup.present(at_player)
	var tile: Control = popup.target_cards.get_child(0)
	assert(tile.has_meta("player_target") and tile.get_node("Portrait").portrait != null, "A targeted player shows their Forge portrait")
	assert(tile.get_node("PlayerName").text.begins_with("Landon") and tile.get_node("PlayerName").autowrap_mode == TextServer.AUTOWRAP_OFF, "The player's name sits under the portrait on one line")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("incoming-player-target.png"))
	popup.reset()
	var acknowledged: Array[int] = []
	popup.acknowledged.connect(func(stack_id): acknowledged.append(stack_id))
	popup.present({"stack": [], "targetedEffects": []})
	var event := {"id": 1, "stackId": 9900, "controllerName": "Opponent", "source": {"id": 9901, "name": "Mortify", "imageKey": "c:Mortify|ACR|1", "text": "Destroy target creature or enchantment.", "typeLine": "Instant", "color": "B"}, "targets": [{"id": 9902, "kind": "card", "name": "Atraxa, Praetors' Voice"}]}
	var state := {"stack": [], "targetedEffects": [event]}
	popup.present(state)
	assert(popup.active.id == 1 and popup.panel.visible, "A fast targeted spell must show even after it has left the stack")
	assert(popup.title.text == "Mortify" and popup.targets.text.contains("Atraxa") and popup.face.face.full_image != null)
	popup.face.mouse_entered.emit()
	assert(popup.hover_preview.visible and popup.hover_preview.data.id == 9901 and popup.hover_preview.size.y >= 450, "Hovering the spell must show its normal enlarged preview")
	popup.face.mouse_exited.emit()
	assert(not popup.hover_preview.visible)
	var target: Control = popup.target_cards.get_child(0)
	target.mouse_entered.emit()
	assert(popup.hover_preview.visible and popup.hover_preview.data.id == 9902, "Hovering a target must magnify that exact target")
	popup._hide_hover(popup.face)
	assert(popup.hover_preview.visible, "A previous card's exit must not hide the new preview")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("incoming-target-hover-1600.png"))
	target.mouse_exited.emit()
	popup.remaining = 5
	popup.present(state)
	assert(popup.remaining == 5 and popup.waiting.is_empty(), "Repeated snapshots must not repeat or restart the popup")
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("incoming-mortify-1600.png"))
		ui.capture_size = Vector2i(1280, 800)
		ui.get_window().size = ui.capture_size
		await ui.get_tree().process_frame
		await ui._save_frame(directory.path_join("incoming-mortify-1280.png"))
		assert(popup.panel.get_global_rect().end.x <= ui.size.x and popup.panel.get_global_rect().end.y < ui.size.y)
		target.mouse_entered.emit()
		await ui._save_frame(directory.path_join("incoming-target-hover-1280.png"))
		assert(popup.get_global_rect().encloses(popup.hover_preview.get_global_rect()), "Popup hover must fit the smaller viewport")
		target.mouse_exited.emit()
	var target_data: Dictionary = target.data.duplicate(true)
	target.update_card({"id": 9902, "hidden": true})
	target.mouse_entered.emit()
	assert(not popup.hover_preview.visible, "Hidden targets must not disclose a magnified face")
	target.update_card(target_data)
	var second: Dictionary = event.duplicate(true)
	second.id = 2
	second.stackId = 9910
	state.targetedEffects.append(second)
	popup.present(state)
	assert(popup.waiting.size() == 1)
	popup.dismiss()
	assert(popup.active.id == 2 and not popup.hover_preview.visible)
	assert(acknowledged == [9900], "Popup acknowledgment must identify the dismissed effect, not the next queued effect")
	popup.dismiss()
	popup.present(state)
	assert(popup.active.is_empty() and not popup.panel.visible, "Dismissed events must not reappear on reconnect snapshots")
	popup.reset()
	popup.present(state)
	assert(popup.active.is_empty(), "Initial connections must not replay old resolved spells")
	popup.reset()
	state.stack = [{"id": 9910}]
	popup.present(state)
	assert(popup.active.id == 2, "An ongoing targeted spell should be visible on initial connection")
	popup.face.mouse_entered.emit()
	popup.blocked = func(): return true
	popup._process(20)
	assert(not popup.panel.visible and popup.remaining == 8 and not popup.hover_preview.visible, "Required dialogs must pause notification expiry and hide magnification")
	popup.reset()
	popup.blocked = Callable()
	popup.present({"stack": [], "targetedEffects": []})
	popup.present({"stack": [], "targetedEffects": [event]})
	var wipe := {"id": 3, "stackId": 9920, "kind": "massRemoval", "controllerName": "Opponent", "source": {"id": 9921, "name": "Toxic Deluge", "text": "As an additional cost to cast this spell, pay X life.\nAll creatures get -X/-X until end of turn.", "typeLine": "Sorcery"}, "targets": []}
	popup.present({"stack": [], "targetedEffects": [event, wipe]})
	assert(popup.active.id == 3 and popup.eyebrow.text == "BOARD-WIDE EFFECT" and not popup.effect_arrow.visible and not popup.targets_scroll.visible, "An untargeted wipe must interrupt older notices with its own card popup")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("board-wipe-notice-1280.png"))
	popup.dismiss()
	assert(popup.active.id == 1, "Interrupted targeted notices must remain available after the board wipe notice")
	popup.reset()
	var many: Dictionary = event.duplicate(true)
	many.id = 4
	many.targets = []
	many.effectText = "A complete line of rules explaining this interaction.\n".repeat(30)
	for index in range(15): many.targets.append({"id": 10000 + index, "kind": "card", "name": "Affected card %d" % index})
	popup.present({"stack": [{"id": 9900}], "targetedEffects": [many]})
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	assert(popup.target_cards.get_child_count() == 15 and popup.targets_scroll.navigation.visible and not popup.rules_pages.visible, "Effect galleries retain every target without duplicating the source card's printed rules")
	popup.targets_scroll.next.pressed.emit()
	assert(popup.targets_scroll.page == 1 and popup.target_cards.get_child(popup.targets_scroll.page_size).visible, "Later affected cards are accessible without scrolling")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("incoming-many-cards-paged-1280.png"))
	assert(popup.panel.get_global_rect().end.y <= ui.size.y and popup.panel.get_global_rect().end.x <= ui.size.x, "Multi-card effect and long rules fit the viewport: " + str([popup.panel.get_global_rect(), ui.size, popup.panel.get_combined_minimum_size(), popup.rules.size, popup.rules_pages.scroll.size]))
	popup.queue_free()
	if not directory.is_empty():
		ui.capture_size = Vector2i(1600, 1000)
		ui.get_window().size = ui.capture_size
	await ui.get_tree().process_frame
	print("PASS: incoming spell image/target, fast resolution, deduplication, queue, reconnect and dialog suspension")
