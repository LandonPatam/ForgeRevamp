extends RefCounted

func run(ui: Control, directory: String = "") -> void:
	var source = preload("res://scripts/ui/CardView.gd").new()
	source.inspection = true
	ui.add_child(source)
	source.size = ui.TABLE_CARD_SIZE
	source.update_card({"id": 9900, "name": "Erebor Heirloom", "imageKey": "c:Fellwar Stone|SLD|3"})
	source.hover_active = true
	var resolutions := [Vector2i(1600, 1000), Vector2i(1280, 800)] if not directory.is_empty() else [Vector2i(ui.size)]
	for resolution in resolutions:
		if not directory.is_empty():
			ui.capture_size = resolution
			ui.get_window().size = resolution
			await ui.get_tree().process_frame
			await ui.get_tree().process_frame
		for on_right in [false, true]:
			source.position = Vector2(ui.size.x - 180 if on_right else 60, 120)
			ui._card_hovered(source.data, source)
			ui._sync_raised_card()
			var preview: Rect2 = ui.inspection.get_global_rect()
			assert(ui.inspection.visible)
			assert(is_equal_approx(preview.size.y, clampf(ui.size.y * 0.42, 360, 440) * 1.25), "Hover preview must grow by 25 percent")
			assert(absf(preview.get_center().y - ui.size.y * 0.5) < 1, "Hover preview must be vertically centered")
			assert((preview.get_center().x < ui.size.x * 0.5) == on_right, "Hover preview must appear opposite the card")
			assert(preview.position.x >= 0 and preview.end.x <= ui.size.x and preview.position.y >= 0 and preview.end.y <= ui.size.y)
			assert(ui.inspection.mouse_filter == Control.MOUSE_FILTER_IGNORE)
			if on_right:
				assert(preview.position.x >= ui.mana_pool.get_global_rect().end.x + 15, "Left-side magnification must leave the mana counter lane visible")
			if not directory.is_empty():
				await ui._save_frame(directory.path_join("hover-preview-%s-%s.png" % ["left" if on_right else "right", resolution.x]))
		if not directory.is_empty():
			var pixels: Image = source.surface.get_texture().get_image()
			assert(pixels.get_pixel(33, 33).a < 0.01, "Complete images must be transparent beyond their rounded corners")
			assert(pixels.get_pixel(320, 436).a > 0.99, "Rounding must preserve the card artwork")
	ui._card_unhovered(source)
	source.queue_free()
	if not directory.is_empty():
		ui.capture_size = Vector2i(1600, 1000)
		ui.get_window().size = ui.capture_size
	await ui.get_tree().process_frame
	print("PASS: larger centered opposite-side previews, flavor-name artwork and rounded image corners")
