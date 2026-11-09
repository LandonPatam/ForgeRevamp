extends SceneTree
const Computer = preload("res://scripts/app/ComputerMenu.gd")
var computer: Control
var content: Control
var fixture: SubViewport
var game: Control
var capture_root := "res://artifacts"

func _initialize() -> void:
	_run.call_deferred()

func _frames() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _error(actual: Image, expected: Image) -> float:
	if actual.get_size() != expected.get_size(): return 1.0
	var total := 0.0
	var count := 0
	# Include the outermost pixels as well as a grid across the whole viewport.
	for y in range(0, actual.get_height(), 8):
		for x in range(0, actual.get_width(), 8):
			var a := actual.get_pixel(x, y)
			var b := expected.get_pixel(x, y)
			total += (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			count += 1
	return total / count

func _run() -> void:
	content = Control.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(content)
	computer = Computer.new()
	computer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(computer)
	computer.present_menu()
	await _frames()
	for uv in [Vector2(0.15, 0.20), Vector2(0.5, 0.5), Vector2(0.80, 0.75), Vector2(0.25, 0.80)]:
		var point: Vector3 = computer.world.screen_point(uv)
		var recovered: Vector2 = computer.world.screen_uv(computer.world.camera.unproject_position(point))
		if recovered.distance_to(uv) > 0.001:
			push_error("Curved CRT hit testing must follow the projected glass surface")
			quit(1)
			return
	if computer.world.screen_point(Vector2(0.5, 0.5)).z <= computer.world.SCREEN_CENTER.z + 0.05:
		push_error("The CRT should bow outward at the center")
		quit(1)
		return
	for dimensions in [Vector2i(1600, 1000), Vector2i(1600, 900), Vector2i(1920, 800)]:
		root.size = dimensions
		computer.show()
		computer.reset_launch()
		await _frames()
		fixture = SubViewport.new()
		fixture.size = dimensions
		fixture.disable_3d = true
		fixture.gui_disable_input = true
		fixture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(fixture)
		game = Control.new()
		game.size = dimensions
		fixture.add_child(game)
		var pattern := ColorRect.new()
		pattern.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var shader := Shader.new()
		shader.code = """shader_type canvas_item;
void fragment() {
    vec3 color = vec3(0.12 + UV.x * 0.6, 0.14 + UV.y * 0.6, 0.34);
    if (fract(UV.x * 16.0) < 0.04 || fract(UV.y * 10.0) < 0.04) { color = vec3(0.8); }
    if (UV.x < 0.025) { color = vec3(0.9, 0.1, 0.2); }
    if (UV.x > 0.975) { color = vec3(0.1, 0.8, 0.3); }
    if (UV.y < 0.025) { color = vec3(0.2, 0.4, 0.9); }
    if (UV.y > 0.975) { color = vec3(0.9, 0.7, 0.1); }
    COLOR = vec4(color, 1.0);
}"""
		var material := ShaderMaterial.new()
		material.shader = shader
		pattern.material = material
		game.add_child(pattern)
		await _frames()
		await computer.zoom_into_game(fixture.get_texture())
		await _frames()
		var before: Image = root.get_texture().get_image()
		var expected := fixture.get_texture().get_image()
		var before_error := _error(before, expected)
		before.save_png(capture_root.path_join("zoom-%dx%d-before.png" % [dimensions.x, dimensions.y]))
		game.reparent(content, false)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.position = Vector2.ZERO
		computer.hide()
		await _frames()
		var after := root.get_texture().get_image()
		var handoff_error := _error(before, after)
		after.save_png(capture_root.path_join("zoom-%dx%d-after.png" % [dimensions.x, dimensions.y]))
		print("ZOOM %dx%d: final image error %.6f; handoff error %.6f" % [dimensions.x, dimensions.y, before_error, handoff_error])
		if before_error > 0.008 or handoff_error > 0.008:
			push_error("Monitor zoom must fill all edges before the fullscreen handoff")
			quit(1)
			return
		# Returning from a game (park or End Game's FORMAT A:) must leave the
		# resting monitor sampling its own UVs, not the window's screen space.
		await computer.world.zoom_out(fixture.get_texture(), Vector2(dimensions))
		var resting: ShaderMaterial = computer.world.screen_material
		if resting != computer.world.crt_material or not is_zero_approx(resting.get_shader_parameter("projection_blend")) or not is_zero_approx(resting.get_shader_parameter("physical_glass")):
			push_error("Zooming out of a game must restore the monitor's own glass UVs")
			quit(1)
			return
		# Reverse the handoff: fullscreen content becomes the exact same texture
		# on the monitor before the camera starts pulling out to reveal the PC.
		game.reparent(fixture, false)
		game.size = dimensions
		computer.show()
		computer.prepare_startup_pullback(fixture.get_texture())
		if computer.world.screen.scale != Vector3.ONE or computer.world.screen_material != computer.world.crt_material:
			push_error("Startup must stay on the physical depth-tested CRT")
			quit(1)
			return
		await _frames()
		var retreat := root.get_texture().get_image()
		var retreat_error := _error(after, retreat)
		retreat.save_png(capture_root.path_join("startup-zoom-%dx%d-handoff.png" % [dimensions.x, dimensions.y]))
		print("STARTUP PULLBACK %dx%d: handoff error %.6f" % [dimensions.x, dimensions.y, retreat_error])
		if retreat_error > 0.008:
			push_error("Startup pullback must match fullscreen pixels before camera movement")
			quit(1)
			return
		var anchored := [false]
		computer.startup_pullback_started.connect(func():
			await create_timer(0.65).timeout
			anchored[0] = computer.world.screen.scale == Vector3.ONE and computer.world.screen_material == computer.world.crt_material and is_zero_approx(computer.world.screen_material.get_shader_parameter("projection_blend"))
			var middle := root.get_texture().get_image()
			middle.save_png(capture_root.path_join("startup-zoom-%dx%d-middle.png" % [dimensions.x, dimensions.y])), CONNECT_ONE_SHOT)
		await computer.pullback_startup(fixture.get_texture())
		if not anchored[0]:
			push_error("The image must settle into fixed glass UVs before the casing is revealed")
			quit(1)
			return
		if not computer.world.camera.transform.is_equal_approx(computer.world.home_transform) or computer.phase != "idle":
			push_error("Startup pullback must finish at the PC with normal menu controls")
			quit(1)
			return
		fixture.remove_child(game)
		game.queue_free()
		root.remove_child(fixture)
		fixture.queue_free()
	print("PASS: monitor zoom continuity at 16:10, 16:9 and ultrawide (rendered pixels before/after handoff)")
	quit()
