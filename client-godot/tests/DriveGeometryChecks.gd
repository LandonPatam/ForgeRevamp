extends SceneTree
## Local procedural fixture: same home camera, no engine or installed deck data.
const Computer = preload("res://scripts/app/ComputerMenu.gd")
class FixtureImages extends Node:
	signal available(key: String)
	func request_texture(_data: Dictionary) -> Texture2D: return null
var computer: Control
var prefix := "drive-after"

func _until(condition: Callable) -> void:
	var limit := Time.get_ticks_msec() + 6000
	while not condition.call() and Time.get_ticks_msec() < limit: await process_frame
	assert(condition.call(), "Drive fixture motion reached its expected stage")

func _initialize() -> void:
	_run.call_deferred()

func _frames() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _capture(name: String) -> void:
	await _frames()
	var frame := root.get_texture().get_image()
	frame.save_png("res://artifacts/" + name + ".png")
	var bounds := Rect2(computer.world.camera.unproject_position(Vector3(-1.4, -0.15, 0.90)), Vector2.ZERO)
	for point in [Vector3(1.42, -0.15, 0.90), Vector3(-1.4, -0.64, 0.90), Vector3(1.42, -0.64, 0.90)]:
		bounds = bounds.expand(computer.world.camera.unproject_position(point))
	frame.get_region(Rect2i(bounds.grow(10))).save_png("res://artifacts/" + name + "-detail.png")

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--drive-before": prefix = "drive-before"
	computer = Computer.new()
	var images := FixtureImages.new()
	root.add_child(images)
	computer.images = images
	computer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(computer)
	computer.present_menu()
	computer.console.present({"name": "DRIVE ALIGNMENT", "sections": {"Commander": [], "Main": []}}, 3, false, "DRIVE ALIGNMENT")
	for dimensions in [Vector2i(1280, 800), Vector2i(1600, 1000)]:
		root.size = dimensions
		await _frames()
		for dark in [false, true]:
			computer.set_dark_mode(dark, false, false)
			await create_timer(0.2).timeout
			await _capture("%s-%dx%d-%s" % [prefix, dimensions.x, dimensions.y, "dark" if dark else "light"])
	if prefix == "drive-after": await _motion_checks()
	print("PASS: drive geometry captures")
	quit()

func _motion_checks() -> void:
	var world: Node3D = computer.world
	assert(world.DRIVE_CENTER == Vector3(0.5975, -0.39, 0.83) and world.PLAY_CENTER == Vector3(-1.04, -0.39, 0.858) and world.SETTINGS_CENTER == Vector3(-0.49, -0.39, 0.858), "Drive feed follows the centered slot while physical keys remain fixed")
	var settings_gap: float = world.DRIVE_OUTLINE[1].x - (world.SETTINGS_CENTER.x + 0.15)
	var case_gap: float = 3.07 * 0.5 - world.DRIVE_OUTLINE[0].x
	assert(absf(settings_gap - case_gap) < 0.0001, "Drive has equal margins to SETTINGS and the fascia edge")
	assert(world.led.position == Vector3(1.335, -0.39, 0.884) and is_equal_approx(world.led.position.y, world.DRIVE_CENTER.y), "Drive LED sits on the slot centerline in the right margin")
	var throat: Array[Vector3] = world._recess_contour(world.DRIVE_OUTLINE, world.DRIVE_INSET, world.DRIVE_THROAT_Z)
	assert(throat[0].is_equal_approx(Vector3(1.0915, -0.364, 0.715)) and throat[3].is_equal_approx(Vector3(0.1115, -0.356, 0.715)) and throat[6].is_equal_approx(Vector3(0.1035, -0.416, 0.715)), "The fitted throat translates with the centered slot")
	var left_gap: float = world.DRIVE_CENTER.x - 0.46 - throat[5].x
	var right_gap: float = throat[0].x - (world.DRIVE_CENTER.x + 0.46)
	assert(absf(left_gap - right_gap) < 0.0001 and left_gap > 0.02 and left_gap < 0.04, "The inserted disk has equal small clearance on both sides of its slot")
	assert(not world.has_node("DecorativeEjectKey") and not world.has_node("EjectMoldedRecess"), "No eject keycap or pocket remains")
	assert(absf(rad_to_deg(world.drive_bevel_angle) - 45.0) < 0.1, "Every recess side has the same approximately 45 degree draft")
	var mesh: ArrayMesh = world.get_node("DriveMoldedRecess").mesh
	var arrays := mesh.surface_get_arrays(0)
	for normal in arrays[Mesh.ARRAY_NORMAL]: assert(absf(normal.length() - 1.0) < 0.0001, "Rounded edges use unit analytic normals")
	assert(arrays[Mesh.ARRAY_VERTEX].size() <= 600, "Continuous slot removes the stepped mesh")
	print("DRIVE PROFILE: bevel %.4f degrees; depth %.4f; rounds %.3f / %.3f; %d vertices" % [rad_to_deg(world.drive_bevel_angle), world.DRIVE_BEVEL_DEPTH, world.DRIVE_EDGE_RADIUS, world.DRIVE_INNER_RADIUS, arrays[Mesh.ARRAY_VERTEX].size()])
	var deck := {"id": "drive-fixture", "name": "Drive alignment", "cover": {}, "sections": {}}
	computer.set_decks([deck], "drive-fixture")
	for dimensions in [Vector2i(1280, 800), Vector2i(1600, 1000)]:
		root.size = dimensions
		for dark in [false, true]:
			computer.set_dark_mode(dark, false, false)
			for path in ["play", "resume", "format"]:
				computer.reset_launch()
				computer.set_session_info({"name": "Drive alignment", "turn": 7, "phase": "Main 1", "life": 32})
				await _frames()
				if path == "play": computer.begin_launch(deck, {"human": {"name": "You"}, "bots": []})
				elif path == "resume": computer.insert_session_disk()
				else: computer.format_session_disk(func(): return true)
				var name := "drive-%s-%dx%d-%s" % [path, dimensions.x, dimensions.y, "dark" if dark else "light"]
				await _until(func(): return world.disk.visible and world.disk.position.z < 1.8 and world.disk.position.z > 1.55)
				_assert_alignment(world)
				await _capture(name + "-aligned")
				await _until(func(): return world.disk.position.z < 1.27)
				_assert_alignment(world)
				assert(not world.drive_door.visible, "Flap opens before the disk crosses the fascia")
				await _capture(name + "-contact")
				await _until(func(): return world.disk.position.z < 0.85)
				_assert_alignment(world)
				assert(not world.drive_door.visible, "Flap remains clear during feeding")
				await _capture(name + "-seated")
				await _until(func(): return not world.disk.visible)
				if path == "format": await _until(func(): return computer.phase == "idle")
				assert(world.drive_door.visible, "Flap closes after the disk clears it")
				computer.reset_launch()
				# The same helper also handles the reverse trip without a flap
				# crossing the disk while it emerges from the drive.
				world.eject_deck(Rect2(100, 200, 180, 180), 0.0)
				await _until(func(): return world.disk.position.z > 0.3)
				assert(not world.drive_door.visible, "Ejection opens the flap before overlap")
				await _until(func(): return not world.disk.visible)
				assert(world.drive_door.visible, "Ejection leaves a closed, empty drive")
				computer.set_session_info({})
	print("PASS: locked aperture, draft, normals, early alignment and flap clearance for play/resume/format/ejection")

func _assert_alignment(world: Node3D) -> void:
	assert((world.disk.quaternion * Vector3.LEFT).dot(Vector3.FORWARD) > 0.99999 and (world.disk.quaternion * Vector3.BACK).dot(Vector3.UP) > 0.99999, "Disk finishes turning before the straight feed and matches the fixed insertion axis")
	assert(absf(world.disk.position.x - world.DRIVE_CENTER.x) < 0.0001 and absf(world.disk.position.y + 0.39) < 0.0001, "Feed center follows the centered drive axis")
	assert(world.disk.position.x - 0.46 > 0.1035 and world.disk.position.x + 0.46 < 1.0915 and world.disk.position.y - 0.0184 > -0.424 and world.disk.position.y + 0.0184 < -0.356, "Disk clears both sides and top/bottom of the centered throat")
