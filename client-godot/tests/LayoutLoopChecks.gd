extends RefCounted
var failed := false
class PollProbe extends "res://scripts/bridge/StateAdapter.gd":
	var polls := 0
	func poll(_delta: float) -> void: polls += 1

func run(ui: Control) -> void:
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(300, 140)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(400, 400)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	# An unstable minimum-size callback changes its request after every native
	# layout pass, scheduling another container sort in the same frame.
	var resize_count: Array = [0]
	var oscillate := func():
		if content.is_set_as_top_level(): return
		resize_count[0] += 1
		content.custom_minimum_size.x = 500 if content.custom_minimum_size.x < 450 else 400
	scroll.sort_children.connect(oscillate)
	content.custom_minimum_size.x = 500
	for frame in range(70):
		await ui.get_tree().process_frame
		if ui.layout_paused: break
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	_expect(ui.layout_paused and ui.layout_guard.paused, "A real container feedback loop must trip the guard")
	if not ui.layout_paused:
		ui.get_tree().quit(1)
		return
	_expect(is_instance_valid(ui.layout_recovery) and not content.visible, "Recovery must replace interaction with the unstable display")
	_expect(resize_count[0] <= 70, "The sizing storm must stop before filling the deferred queue")
	var transport = ui.adapter
	var probe := PollProbe.new()
	ui.adapter = probe
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	_expect(probe.polls > 0, "The transport must keep polling while presentation is paused")
	ui.adapter = transport
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--layout-recovery-capture="):
			await RenderingServer.frame_post_draw
			ui.get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--layout-recovery-capture="))
	var latest: Dictionary = saved.duplicate(true)
	latest.game.turn = 123
	var label_before: String = ui.turn_label.text
	ui._apply_state(latest)
	_expect(ui.snapshot.game.turn == 123 and ui.turn_label.text == label_before, "Paused layout must retain new state without updating stale controls")
	var sends: Array = []
	var listener := func(value): sends.append(value)
	ui.adapter.state_changed.connect(listener)
	ui._intent("advance")
	ui.adapter.state_changed.disconnect(listener)
	_expect(sends.is_empty(), "Paused display must reject stale game actions")
	_click_retry(ui)
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	_expect(ui.layout_paused and ui.layout_recovery.visible, "A retry while the loop persists must pause safely again")
	scroll.sort_children.disconnect(oscillate)
	_click_retry(ui)
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	_expect(not ui.layout_paused and not content.is_set_as_top_level() and content.visible, "Retry must restore normal container ownership and visibility")
	_expect(ui.turn_label.text == "Turn 123", "Retry must display the newest authoritative snapshot")
	scroll.queue_free()
	ui._apply_state(saved)
	await ui.get_tree().process_frame
	if failed:
		ui.get_tree().quit(1)
		return
	print("PASS: real layout loop interrupted, state retained, stale input blocked and newest state restored")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _click_retry(ui: Control) -> void:
	if DisplayServer.get_name() == "headless":
		ui.layout_retry_button.pressed.emit()
		return
	var point: Vector2 = ui.layout_retry_button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		ui.get_viewport().push_input(event)
