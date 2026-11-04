extends RefCounted
const Surface = preload("res://scripts/app/ScaledSurface.gd")

func check(host: Control, value: bool, message: String) -> bool:
	if value: return true
	push_error(message)
	host.get_tree().quit(1)
	return false

func pixel(host: Control, surface: Control) -> Color:
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	await RenderingServer.frame_post_draw
	return surface.viewport.get_texture().get_image().get_pixel(8, 8)

func run(host: Control) -> bool:
	var surface := Surface.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(surface)
	var paint := ColorRect.new()
	paint.color = Color.RED
	surface.attach(paint)
	surface.hide()
	if not check(host, surface.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "A hidden UI surface suspends drawing"): return false
	surface.render_when_hidden = true
	if not check(host, surface.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "A borrowed CRT texture keeps rendering while its UI is hidden"): return false
	if DisplayServer.get_name() != "headless":
		if not check(host, (await pixel(host, surface)).is_equal_approx(Color.RED), "A hidden CRT source renders its initial frame"): return false
		paint.color = Color.BLUE
		if not check(host, (await pixel(host, surface)).is_equal_approx(Color.BLUE), "A borrowed offscreen texture receives fresh frames"): return false
	surface.render_when_hidden = false
	paint.color = Color.GREEN
	if DisplayServer.get_name() != "headless":
		if not check(host, (await pixel(host, surface)).is_equal_approx(Color.BLUE), "A suspended UI retains its last rendered frame"): return false
	surface.show()
	if not check(host, surface.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Showing a UI restores continuous rendering"): return false
	if DisplayServer.get_name() != "headless":
		if not check(host, (await pixel(host, surface)).is_equal_approx(Color.GREEN), "Resuming renders changes made while the UI was suspended"): return false
	surface.queue_free()
	await host.get_tree().process_frame
	print("PASS: hidden UI render suspension, fresh CRT preview frames and resume")
	return true
