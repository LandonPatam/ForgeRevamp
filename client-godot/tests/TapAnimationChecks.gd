extends RefCounted

func run(ui: Control, rendered: bool = false) -> void:
	var phase_style: StyleBox = ui.phase_labels[0]["Main 1"].get_theme_stylebox("normal")
	ui._update_turn_steps()
	assert(ui.phase_labels[0]["Main 1"].get_theme_stylebox("normal") == phase_style, "Unchanged table updates must reuse phase styling during animation")
	var view = preload("res://scripts/ui/CardView.gd").new()
	ui.add_child(view)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.update_card({"id": 9901, "name": "Island", "tapped": false})
	view.settle(Vector2(400, 300), ui.TABLE_CARD_SIZE, false, true)
	view.surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.update_card({"id": 9901, "name": "Island", "tapped": true})
	assert(view.surface.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Tap metadata must reuse the cached card face")
	var turn: Tween = view.tap_animation
	turn.pause()
	turn.custom_step(view.TAP_SECONDS * 0.25)
	var first_angle: float = view.rotation
	assert(first_angle > 0 and first_angle < PI * 0.125, "Tap must ease into its rotation")
	# A real turn changes the row footprint and can move the pointer outside the card.
	view.settle(Vector2(440, 300), ui.TABLE_CARD_SIZE)
	view._on_enter()
	view._on_exit()
	assert(view.tap_animation == turn, "Layout and hover must preserve the ongoing tap tween")
	view._on_enter()
	var hover_motion: Tween = view.animation
	view._mouse_exit()
	assert(view.hover_active and view.animation == hover_motion, "Rotation beneath a stationary pointer must not bounce the hover pose")
	turn.custom_step(view.TAP_SECONDS * 0.25)
	assert(is_equal_approx(view.rotation, PI * 0.25), "Tap must reach 45 degrees halfway through")
	var before_reverse: float = view.rotation
	view.update_card({"id": 9901, "name": "Island", "tapped": false})
	assert(is_equal_approx(view.rotation, before_reverse), "Untapping mid-turn must start from the visible angle")
	var reverse: Tween = view.tap_animation
	reverse.pause()
	reverse.custom_step(view.TAP_SECONDS * 0.5)
	assert(view.rotation > 0 and view.rotation < before_reverse)
	reverse.custom_step(view.TAP_SECONDS * 0.5 + 0.01)
	assert(is_zero_approx(view.rotation), "Untap must finish upright")
	view.update_card({"id": 9901, "name": "Island", "tapped": true})
	view.tap_animation.pause()
	view.tap_animation.custom_step(view.TAP_SECONDS + 0.01)
	assert(is_equal_approx(view.rotation, PI * 0.5), "Tap must finish at 90 degrees")
	view.settle(Vector2(400, 300), ui.TABLE_CARD_SIZE, false, true)
	assert(view.tap_animation == null, "Immediate placement must stop any rotation tween")
	if rendered:
		# Warm the viewport before measuring; startup/shader compilation is not a tap.
		await ui.get_tree().create_timer(0.2).timeout
		ui.cards[3]._on_enter()
		await ui.get_tree().create_timer(0.2).timeout
		var samples: Array[float] = []
		for cycle in range(3):
			# Exercise the real table, selection, row reflow and raised hover copy.
			ui._click_card(3)
			var elapsed := 0.0
			var published := false
			while elapsed < 0.35:
				await ui.get_tree().process_frame
				var delta: float = ui.get_process_delta_time()
				samples.append(delta * 1000)
				elapsed += delta
				if elapsed > 0.1 and not published:
					ui.adapter._publish()
					published = true
			assert(is_equal_approx(ui.cards[3].rotation, PI * 0.5 if ui.cards[3].data.tapped else 0.0))
		ui.cards[3]._on_exit()
		ui._reset()
		samples.sort()
		print("Tap frame times (ms): median=%.2f p95=%.2f max=%.2f frames=%s" % [samples[samples.size() / 2], samples[int(samples.size() * 0.95)], samples.back(), samples.size()])
	view.queue_free()
	await ui.get_tree().process_frame
	print("PASS: continuous tap/untap rotation through layout, hover and mid-turn reversal")
