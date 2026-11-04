extends RefCounted
## Presentation fixtures cover the capture matrix without starting extra engines.

func run(driver: RefCounted) -> bool:
	var app: Control = driver.app
	var menu: Control = app.computer
	var original_size: Vector2i = app.get_window().size
	var original_dark: bool = menu.dark_mode
	var info := {"name": "Atraxa menu test", "turn": 7, "phase": "Main 1", "life": 32}
	for dimensions in [Vector2i(1280, 800), Vector2i(1600, 1000)]:
		app.get_window().size = dimensions
		for night in [false, true]:
			menu.set_dark_mode(night, false, false)
			menu.set_session_info(info)
			await app.get_tree().create_timer(0.15).timeout
			var raw: Image
			if DisplayServer.get_name() != "headless": raw = menu.session_disk.disk.cover.texture.get_image()
			var stopped := [false]
			var began := Time.get_ticks_msec()
			menu.format_session_disk(func(): return stopped[0])
			var prefix := "format-%dx%d-%s" % [dimensions.x, dimensions.y, "dark" if night else "light"]
			if not await driver.until(func(): return is_instance_valid(menu.format_log), "matrix on-screen format"): return false
			await driver.capture(prefix + "-approach")
			if not driver.check(menu.world.drive_format_active and not menu.world.disk.visible, "Drive is amber while no floppy moves"): return false
			await driver.capture(prefix + "-entering")
			var terminal: Control = menu.format_log
			if not await driver.until(func(): return terminal.done_count >= 2, "matrix format progress"): return false
			if not driver._console_safe(terminal): return false
			if raw != null:
				if not driver.check(menu.session_disk.disk.cover.texture.get_image().get_data() == raw.get_data(), "Strike-through never modifies the raw session face"): return false
			await driver.capture(prefix + "-progress")
			stopped[0] = true
			if not await driver.until(func(): return terminal.complete and terminal.value == 1, "matrix session erased"): return false
			await driver.capture(prefix + "-erased")
			if not await driver.until(func(): return menu.phase == "idle", "matrix empty drive"): return false
			if not driver.check(menu.session_disk == null and not menu.world.disk.visible and not menu.world.drive_format_active and driver._silent_tree(menu), "Matrix format is silent and consumes only the session disk"): return false
			await driver.capture(prefix + "-empty")
			print("FORMAT DURATION: %s %.2fs" % [prefix, (Time.get_ticks_msec() - began) / 1000.0])
	# Resize during approach, then interrupt while the physical disk is moving.
	menu.set_session_info(info)
	await app.get_tree().process_frame
	menu.format_session_disk(func(): return true)
	await app.get_tree().create_timer(0.1).timeout
	app.get_window().size = Vector2i(1440, 900)
	if not await driver.until(func(): return is_instance_valid(menu.format_log), "resize keeps the on-screen format running"): return false
	if not driver.check(menu.session_disk.modulate.a == 0.0, "Resize cannot reveal the consumed disk caption or controls"): return false
	menu.reset_launch()
	await app.get_tree().create_timer(0.2).timeout
	if not driver.check(menu.phase == "idle" and menu.session_disk == null and menu.format_log == null and not menu.world.disk.visible and not menu.world.drive_format_active and menu.shelf.enabled, "Interrupted format clears disk, materials, activity and input locks"): return false
	app.get_window().size = original_size
	menu.set_dark_mode(original_dark, false, false)
	# Let the native resize and projected key hit areas settle before the next
	# test measures a 30ms key downstroke.
	await app.get_tree().create_timer(0.3).timeout
	menu._position_play_button()
	app._update_status()
	print("PASS: format cleanup gate, timeout, silent capture matrix, resize and interruption")
	return true
