extends RefCounted
## Rendered regression: a lifted face must contain pixels, including during rapid
## hover changes, the return animation, hand scrolling and selection refreshes.
var ui: Control
var checked_frames := 0
var failed := false

func run(table: Control) -> void:
	ui = table
	var root := ui.get_tree().root
	root.size = Vector2i(1600, 1000)
	ui.synthetic_hover = true
	await ui.get_tree().create_timer(0.4).timeout
	for crowded in [false, true]:
		if crowded:
			for i in range(8): ui._intent("draw")
			ui._scroll_hand(100)
		await ui.get_tree().create_timer(0.3).timeout
		var ids: Array = []
		for card in ui._ordered_hand():
			if ui.cards[card.id].visible: ids.append(card.id)
		for reverse_order in [false, true]:
			if reverse_order: ids.reverse()
			for id in ids:
				for other in ids:
					if ui.cards[other].hover_active: ui.cards[other]._on_exit()
				ui.cards[id]._on_enter()
				# One frame between hovers exercises overlapping lift/return tweens;
				# the slower sweep also exercises their completed poses.
				for frame in range(1 if reverse_order else 12):
					await RenderingServer.frame_post_draw
					_check_faces(ids)
					await ui.get_tree().process_frame
				if failed: return
			for id in ids:
				if ui.cards[id].hover_active: ui.cards[id]._on_exit()
			for frame in range(15):
				await RenderingServer.frame_post_draw
				_check_faces(ids)
				await ui.get_tree().process_frame
			if failed: return
		# A selected face can repaint while its original visual is hidden.
		var source: Control = ui.cards[ids.back()]
		source._on_enter()
		source.set_selected(true)
		await ui.get_tree().process_frame
		await RenderingServer.frame_post_draw
		_check_faces(ids)
		var copy: Control = ui.hand_copies[source.data.id]
		var original_image: Image = source.visual.texture.get_image()
		var lifted_image: Image = copy.visual.texture.get_image()
		if original_image.get_data() != lifted_image.get_data():
			_fail("Lifted face did not retain the current selected artwork")
		if failed: return
		if not crowded:
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--hand-hover-capture="):
					root.get_texture().get_image().save_png(arg.trim_prefix("--hand-hover-capture="))
		source.set_selected(false)
		source._on_exit()
	print("PASS: hand hover rendered faces across %d frames (slow/rapid sweeps, return, scrolling, selection)" % checked_frames)
	ui.get_tree().quit()

func _check_faces(ids: Array) -> void:
	checked_frames += 1
	for id in ids:
		var source: Control = ui.cards[id]
		var copy: Control = ui.hand_copies[id]
		var face: Control = copy if copy.visible else source
		if not face.visual.is_visible_in_tree():
			_fail("Hand card %s has no visible face" % id)
			return
		var image: Image = face.visual.texture.get_image()
		# Sample the opaque printed card, away from its shadow margin and text.
		for point in [Vector2i(320, 100), Vector2i(100, 400), Vector2i(500, 700)]:
			if image.get_pixelv(point).a < 0.9:
				_fail("Hand card %s has a blank face during hover (frame %s)" % [id, checked_frames])
				return

func _fail(message: String) -> void:
	failed = true
	push_error(message)
	ui.get_tree().quit(1)
