extends RefCounted

func run(app: Control, driver: RefCounted, baseline: bool) -> void:
	var menu: Control = app.computer
	menu.shelf.enabled = false
	menu.shelf.elapsed = 0
	menu.world.set_key_hover(true, false)
	menu.world.set_key_hover(false, false)
	var prefix := "night-before" if baseline else "night-after"
	for dimensions in [Vector2i(1600, 1000), Vector2i(1280, 800), Vector2i(1920, 800)]:
		app.get_window().size = dimensions
		await app.get_tree().create_timer(0.3).timeout
		for dark in [false, true]:
			menu.set_dark_mode(dark, false, false)
			await app.get_tree().create_timer(0.15).timeout
			await driver.capture("%s-%s-%dx%d" % [prefix, "dark" if dark else "light", dimensions.x, dimensions.y])
	if not baseline:
		var original: Dictionary = {}
		# Off-screen carousel disks have no face texture until they are first shown.
		var built: Array = menu.shelf.tiles.filter(func(tile): return tile.cover.texture != null)
		for tile in built:
			original[tile.get_instance_id()] = {"texture": tile.cover.texture, "bytes": tile.cover.texture.get_image().get_data()}
		for cycle in range(4):
			menu.set_dark_mode(true, true, false)
			await app.get_tree().create_timer(0.09).timeout
			assert(menu.darkness > 0 and menu.darkness <= 1, "The existing room tween drives night lighting")
			menu.set_dark_mode(false, true, false)
			await app.get_tree().create_timer(menu.LIGHTING_SECONDS + 0.15).timeout
			_check_daylight(menu)
		for tile in built:
			assert(tile.cover.texture == original[tile.get_instance_id()].texture and tile.cover.texture.get_image().get_data() == original[tile.get_instance_id()].bytes, "Night presentation never modifies the shared insertion/color-sampling texture")
		var day := await _timing(app)
		menu.set_dark_mode(true, false, false)
		await app.get_tree().create_timer(0.15).timeout
		var night := await _timing(app)
		print("NIGHT FRAME TIMING ms: daylight ", day, "; night ", night)
		assert(night.median <= day.median + 2.0, "Night lighting must not add a noticeable frame-time increase")
		assert(not menu.world.night_rim.shadow_enabled and not menu.world.monitor_light.shadow_enabled, "Night lighting adds no shadow maps")
		assert(menu.world.night_rim.light_energy > 0 and menu.world.monitor_light.light_energy > 0, "The real night lights are enabled")
		menu.set_dark_mode(false, false, false)
		await app.get_tree().process_frame
		await app.get_tree().process_frame
		_check_daylight(menu)
		await driver.capture("night-daylight-restored")
	print("PASS: night lighting captures")
	app.get_tree().quit()

func _check_daylight(menu: Control) -> void:
	assert(menu.darkness == 0 and menu.world.night_rim.light_energy == 0 and menu.world.monitor_light.light_energy == 0, "Night lights return exactly to zero")
	assert(menu.world.room_floor.material_override == menu.world.floor_material, "Daylight uses the exact original floor material")
	assert(is_equal_approx(menu.world.room_environment.ambient_light_energy, 0.62) and is_equal_approx(menu.world.room_key.light_energy, 0.65) and is_equal_approx(menu.world.room_fill.light_energy, 0.35), "Original daylight lighting is preserved")
	assert(float(menu.world.crt_material.get_shader_parameter("night_amount")) == 0 and float(menu.world.zoom_material.get_shader_parameter("night_amount")) == 0, "CRT night emission has no daylight effect")
	for tile in menu.shelf.tiles:
		assert(tile.cover.material == null and tile.night_amount == 0 and (tile.face_view == null or tile.face_view.render_target_update_mode != SubViewport.UPDATE_ALWAYS), "Daylight removes disk presentation shading without continuous face repaints")
	for copy in menu.shelf.copies: assert(copy.material == null and copy.night_amount == 0, "Wrapped copies also return to original daylight rendering")

func _timing(app: Control) -> Dictionary:
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in range(120):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if frame > 8: samples.append((now - previous) / 1000.0)
		previous = now
	samples.sort()
	return {"median": samples[samples.size() / 2], "p95": samples[int(samples.size() * 0.95)]}
