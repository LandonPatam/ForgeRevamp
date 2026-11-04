extends Control
signal quit_requested
signal verification_started
const Segments = preload("res://scripts/app/StartupSegments.gd")
const INK := Color("70d6bc")
const DIM := Color("3d8373")
const DARK := Color("061712")
const RED := Color("e78276")
const STAGES := ["starting", "cards", "catalog", "connecting", "ready", "online", "complete"]
const VALUES := [0.0, 0.08, 0.55, 0.82, 0.90, 0.95, 1.0]
# Visual estimates ease forward while a real milestone is in progress. These
# never mark a service ready, and cannot reach 100% without complete().
const ESTIMATE_CAPS := [0.0, 0.72, 0.84, 0.90, 0.94, 0.97]
const ESTIMATE_SECONDS := [1.0, 18.0, 6.0, 5.0, 5.0, 5.0]
const SERVICES := ["FORGE RUNTIME", "CARD RULES DATABASE", "CARD / PRINTING CATALOG", "DECK LIBRARY SERVICE", "CLIENT CONNECTION", "COMMANDER DECKS"]
var progress: Control
var quit_button: Button
var font: SystemFont
var failed := false
var phase := "connecting"
var stage_index := 0
var target := 0.0
var title := "INITIALIZING FORGE"
var detail := "Preparing the game library."
var elapsed := 0.0
var layout_scale := 1.0
var layout_origin := Vector2.ZERO
var completion_generation := 0
var completion_tween: Tween
var stage_elapsed := 0.0
var stage_start_value := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono"])
	font.font_weight = 500
	font.font_italic = false
	progress = Segments.new()
	add_child(progress)
	quit_button = Button.new()
	quit_button.text = "[ ESC - QUIT ]"
	quit_button.add_theme_font_override("font", font)
	for state in ["normal", "hover", "pressed", "focus"]:
		quit_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	quit_button.add_theme_color_override("font_color", INK)
	quit_button.add_theme_color_override("font_hover_color", Color.WHITE)
	quit_button.pressed.connect(func(): quit_requested.emit())
	add_child(quit_button)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	layout_scale = minf(size.x / 1280.0, size.y / 800.0)
	layout_origin = (size - Vector2(1280, 800) * layout_scale) * 0.5
	pivot_offset = size * 0.5
	if progress == null: return
	progress.position = layout_origin + Vector2(84, 642) * layout_scale
	progress.size = Vector2(1112, 24) * layout_scale
	quit_button.position = layout_origin + Vector2(1030, 694) * layout_scale
	quit_button.size = Vector2(180, 30) * layout_scale
	quit_button.add_theme_font_size_override("font_size", maxi(12, roundi(15 * layout_scale)))
	queue_redraw()

func present(heading: String, message: String, stage: String) -> void:
	if stage == "failed":
		failed = true
		phase = "failed"
		completion_generation += 1
		if completion_tween != null: completion_tween.kill()
		scale = Vector2.ONE
		modulate = Color.WHITE
		progress.hide()
		title = heading.to_upper()
		detail = message
		queue_redraw()
		return
	var next_index := STAGES.find(stage)
	if failed or phase != "connecting" or next_index < stage_index: return
	if next_index >= ESTIMATE_CAPS.size(): return # Only complete() authorizes 100%.
	if next_index != stage_index:
		stage_elapsed = 0.0
		stage_start_value = progress.value
	stage_index = maxi(0, next_index)
	target = VALUES[stage_index]
	title = heading.to_upper()
	detail = message
	queue_redraw()

func complete() -> bool:
	completion_generation += 1
	var generation := completion_generation
	failed = false
	phase = "verifying"
	stage_index = 6
	target = 1.0
	progress.show()
	completion_tween = create_tween()
	completion_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	completion_tween.tween_property(progress, "value", 1.0, maxf(0.65, (1.0 - progress.value) / 0.28))
	while completion_tween.is_running(): await get_tree().process_frame
	if generation != completion_generation: return false
	phase = "verified"
	title = "SYSTEM CHECK COMPLETE"
	detail = "All services connected. Opening Commander console."
	verification_started.emit()
	await get_tree().create_timer(0.85).timeout
	return generation == completion_generation

func _process(delta: float) -> void:
	elapsed += delta
	if progress == null: return
	if phase == "connecting" and not failed:
		stage_elapsed += delta
		var base := maxf(stage_start_value, target)
		var estimate := lerpf(base, maxf(base, ESTIMATE_CAPS[stage_index]), 1.0 - exp(-stage_elapsed / ESTIMATE_SECONDS[stage_index]))
		var goal := maxf(progress.value, estimate)
		progress.value = move_toward(progress.value, goal, delta * 0.22)
	queue_redraw()

func _text(at: Vector2, text: String, font_size: int = 17, ink: Color = INK) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)

func _panel(rect: Rect2, heading: String) -> void:
	draw_rect(rect, DIM, false, 1.0)
	draw_rect(Rect2(rect.position + Vector2(12, -11), Vector2(heading.length() * 10 + 20, 23)), DARK)
	_text(rect.position + Vector2(22, 6), heading, 17)

func _row(y: float, label: String, value: String, ready: bool = false) -> void:
	_text(Vector2(94, y), label, 18, DIM)
	_text(Vector2(328, y), value, 18, INK if ready else DIM)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("020b08"))
	if font == null: return
	draw_set_transform(layout_origin, 0.0, Vector2.ONE * layout_scale)
	var bounds := Rect2(40, 48, 1200, 704)
	draw_rect(bounds.grow(5), Color(0.12, 0.43, 0.34, 0.14), false, 6)
	draw_rect(bounds, DARK)
	draw_rect(bounds, INK, false, 2)
	draw_rect(bounds.grow(-7), DIM, false, 1)
	_text(Vector2(64, 81), "ForgeCheck 1.0", 23)
	_text(Vector2(774, 81), "COMMANDER SYSTEM DIAGNOSTICS", 18, DIM)
	draw_line(Vector2(48, 97), Vector2(1232, 97), DIM)
	var active := 0 if stage_index < 2 else (1 if stage_index < 4 else (2 if stage_index < 6 else 3))
	var tabs := ["SYSTEM", "SERVICES", "LIBRARY", "STATUS"]
	for index in range(4):
		var x := 82.0 + index * 192.0
		if index == active: draw_rect(Rect2(x - 12, 106, 150, 27), INK)
		_text(Vector2(x, 126), tabs[index], 18, DARK if index == active else DIM)
	_text(Vector2(1025, 126), "MODE: BOOT", 15, DIM)
	draw_line(Vector2(48, 143), Vector2(1232, 143), DIM)
	_panel(Rect2(72, 167, 1136, 225), "CONFIGURATION INFORMATION")
	_row(208, "Operating mode", "COMMANDER", true)
	_row(239, "Forge runtime", "RUNNING" if stage_index >= 1 else "INITIALIZING", stage_index >= 1)
	_row(270, "Rules database", "LOADED" if stage_index >= 2 else "WAITING", stage_index >= 2)
	_row(301, "Card catalog", "INDEXED" if stage_index >= 3 else "WAITING", stage_index >= 3)
	_row(332, "Saved decks", "AVAILABLE" if stage_index >= 6 else "WAITING", stage_index >= 6)
	_row(363, "Client link", "UNAVAILABLE" if failed else ("CONNECTED" if stage_index >= 5 else "CONNECTING"), stage_index >= 5 and not failed)
	draw_line(Vector2(730, 185), Vector2(730, 376), DIM)
	_text(Vector2(756, 209), "STARTUP MONITOR", 19)
	_text(Vector2(756, 246), "SERVICES   %d / 6 READY" % stage_index, 17)
	_text(Vector2(756, 277), "STATE      " + ("HALTED" if failed else ("READY" if phase == "verified" else "CHECKING")), 17, RED if failed else INK)
	var seconds := int(elapsed)
	_text(Vector2(756, 308), "ELAPSED    %02d:%02d" % [seconds / 60, seconds % 60], 17, DIM)
	_text(Vector2(756, 339), "TRANSPORT  " + ("OFFLINE" if failed else ("ONLINE" if stage_index >= 5 else "STANDBY")), 17, DIM)
	_text(Vector2(756, 370), "FORMAT     COMMANDER", 17, DIM)
	_panel(Rect2(72, 420, 1136, 164), "SERVICE INITIALIZATION LOG")
	for index in range(SERVICES.size()):
		var done := index < stage_index
		var current := index == stage_index
		var state := "OK" if done else ("FAIL" if current and failed else (".." if current else "--"))
		var color := RED if current and failed else (INK if done or current else DIM)
		var y := 451.0 + index * 22.0
		_text(Vector2(94, y), "%02d  %-28s" % [index + 1, SERVICES[index]], 17, color)
		_text(Vector2(673, y), ". . . . . . . . . . . . . . .", 16, DIM)
		_text(Vector2(1110, y), "[" + state + "]", 17, color)
	_text(Vector2(74, 618), title.left(84) + (" _" if int(elapsed * 2) % 2 == 0 and phase == "connecting" else ""), 17, RED if failed else INK)
	_text(Vector2(1122, 618), "%03d%%" % floori(progress.value * 100), 22, RED if failed else INK)
	draw_rect(Rect2(72, 632, 1136, 44), RED if failed else DIM, false, 1)
	if failed: _text(Vector2(91, 660), "INITIALIZATION HALTED - CHECK THE MESSAGE BELOW", 17, RED)
	draw_multiline_string(font, Vector2(74, 704), detail, HORIZONTAL_ALIGNMENT_LEFT, 930, 14, -1, RED if failed else DIM)
	draw_line(Vector2(48, 724), Vector2(1232, 724), DIM)
	_text(Vector2(74, 740), "FORGE / " + ("CONNECTION REQUIRED" if failed else ("ALL SYSTEMS READY" if phase == "verified" else "PLEASE WAIT - STARTING SERVICES")), 12, DIM)
	# Fine phosphor rows across the terminal, without a separate image panel.
	for y in range(52, 730, 3):
		draw_line(Vector2(48, y), Vector2(1232, y), Color(0.0, 0.02, 0.015, 0.13), 1)

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		quit_requested.emit()
		get_viewport().set_input_as_handled()
