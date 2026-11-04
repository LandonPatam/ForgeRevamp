extends RefCounted

func run(ui: Control, directory: String = "") -> void:
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var saved_selection: Dictionary = ui.selected.duplicate(true)
	var fixture: Dictionary = saved.duplicate(true)
	var card: Dictionary = saved.players[0].zones.Battlefield[0].duplicate(true)
	fixture.stack = [
		{"id": 9210, "sourceId": 9211, "sourceName": "Counterspell", "controllerName": "You", "ability": false, "trigger": false, "card": card, "text": "Counter target spell.", "targetsLocal": false, "targets": [{"kind": "stack", "name": "Mira's creature spell"}]},
		{"id": 9212, "sourceId": 9213, "sourceName": "Atraxa, Praetors' Voice", "controllerName": "Mira", "ability": true, "trigger": true, "card": card, "text": "At the beginning of your end step, proliferate.", "targetsLocal": false, "targets": []},
		{"id": 9214, "sourceId": 9215, "sourceName": "Dreadship Reef", "controllerName": "Thorne", "ability": true, "trigger": false, "card": card, "text": "Put a storage counter on Dreadship Reef.", "targetsLocal": false, "targets": []}
	]
	ui._apply_state(fixture)
	await ui.get_tree().process_frame
	var entry: Button = ui.stack_box.entries[9210]
	assert(entry.heading.text.contains("CAST") and entry.next_to_resolve and entry.targets_label.text.contains("Mira's creature spell"))
	assert(ui.stack_box.entries[9212].heading.text.contains("TRIGGER") and ui.stack_box.entries[9214].heading.text.contains("ACTIVATE"), "The feed must distinguish real triggers from activated abilities")
	var selection: Array = []
	var listener := func(value): selection.append(int(value.id))
	ui.stack_box.item_selected.connect(listener)
	entry.pressed.emit()
	assert(selection == [9210], "A feed click must preserve the exact stack entry ID")
	ui._apply_state(fixture)
	assert(ui.stack_box.entries[9210] == entry, "Snapshot updates must retain feed widgets instead of replaying their entrance animation")
	if not directory.is_empty():
		await ui.get_tree().create_timer(0.25).timeout
		await ui._save_frame(directory.path_join("crt-stack-activity-feed.png"))
	fixture.stack.pop_front()
	ui._apply_state(fixture)
	assert(not ui.stack_box.entries.has(9210) and ui.stack_box.entries[9212].next_to_resolve, "Resolved entries must leave the feed and promote the next item")
	ui.stack_box.item_selected.disconnect(listener)
	ui.selected = saved_selection
	ui._apply_state(saved)
	assert(ui.stack_box.idle.visible == saved.stack.is_empty())
	await ui.get_tree().process_frame
	print("PASS: CRT stack labels, exact stack IDs, snapshot stability, promotion and idle state")
