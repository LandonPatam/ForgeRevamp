extends Control
signal hovered(data: Dictionary)
signal unhovered
signal picked(data: Dictionary, double_click: bool)
signal inspect_requested(data: Dictionary)
signal drag_started(view: Control, pointer: Vector2)
signal drag_moved(view: Control, pointer: Vector2)
signal drag_finished(view: Control, cancelled: bool)
const P = preload("res://scripts/ui/Palette.gd")
const Face = preload("res://scripts/ui/CardFace.gd")
const Perspective = preload("res://scripts/ui/card_perspective.gdshader")
const Back = preload("res://assets/black-lotus-back.tres")
const REVEAL_SECONDS := 0.28
var reveal_animation: Tween
var reveal_progress := 1.0:
	set(value):
		reveal_progress = value
		if visual != null:
			visual.material.set_shader_parameter("reveal_progress", value)
var data: Dictionary = {}
var selected := false
var inspection := false
var zone_browser := false
## The lifted copy of a hand card keeps the hand overlays its original draws at rest.
var hand_copy := false
var resting_position := Vector2.ZERO
var hover_active := false
var animation: Tween
var tap_animation: Tween
var tap_target := 0.0
var tap_pointer := Vector2.INF
const TAP_SECONDS := 0.16
var settle_target: Array = []
var face: Control
var trait_layer: Control
## Power/toughness draws one z-step above every card on the board, so a neighbor's trait icons never cover it.
var stats_layer: Control
## The magnified preview lists traits underneath instead of hanging icons.
var show_traits := true
const TRAITS_PER_ROW := 4
const STATS_HEIGHT := 22.0
const STATS_FONT := 16.0
const TraitIcons = preload("res://scripts/ui/TraitIcons.gd")
const ManaCounter = preload("res://scripts/ui/ManaCounter.gd")
const ManaPips = preload("res://scripts/ui/ManaPips.gd")
## Table settings: mana-cost pips across your hand cards, and a glow on cards Forge says you can play now.
static var mana_overlay := false
static var playable_glow := true
const PLAYABLE_GLOW := Color("b48cff")
## Teal: the mana you have already tapped pays for it, so it can be played right now.
const READY_GLOW := Color("3fe6d4")
const PICK_DISCARD := Color("ff3b3b")
var surface: SubViewport
var visual: TextureRect
var table_angle := true
var hand_mode := false
var base_rotation := 0.0
var resting_z := 0
var hand_hover_amount := 0.0
var press_pending := false
var pile_gesture := false
## Mouse button that started the current press (right-drag or Shift + left-drag move piles).
var press_button := MOUSE_BUTTON_LEFT
var drag_active := false
var press_pointer := Vector2.ZERO
var last_pointer := Vector2.ZERO
var held_seconds := 0.0
var press_double_click := false
var drop_pointer := Vector2.INF
var rejection := 0.0
var rejection_tween: Tween
const HOLD_SECONDS := 0.18
const DRAG_DISTANCE := 8.0

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	surface = SubViewport.new()
	surface.size = Vector2i(640, 872)
	surface.transparent_bg = true
	surface.disable_3d = true
	surface.handle_input_locally = false
	surface.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(surface)
	face = Face.new()
	face.position = Vector2(32, 32)
	face.size = Vector2(576, 808)
	surface.add_child(face)
	visual = TextureRect.new()
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	visual.texture = surface.get_texture()
	var projection := ShaderMaterial.new()
	projection.shader = Perspective
	projection.set_shader_parameter("back_texture", Back.atlas)
	var atlas_size: Vector2 = Back.atlas.get_size()
	projection.set_shader_parameter("back_region", Vector4(Back.region.position.x / atlas_size.x, Back.region.position.y / atlas_size.y, Back.region.size.x / atlas_size.x, Back.region.size.y / atlas_size.y))
	visual.material = projection
	add_child(visual)
	# Trait icons hang off the card's bottom-left edge, outside the cached face.
	trait_layer = Control.new()
	trait_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trait_layer.draw.connect(_draw_traits)
	add_child(trait_layer)
	stats_layer = Control.new()
	stats_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_layer.z_index = 1
	stats_layer.draw.connect(_draw_stats)
	add_child(stats_layer)
	_refresh_face()
	mouse_entered.connect(_mouse_enter)
	mouse_exited.connect(_mouse_exit)
	resized.connect(_arrange)
	_arrange()
	set_process_input(false)

func update_card(value: Dictionary) -> void:
	if data == value:
		return
	var changed_tap: bool = data.get("tapped", false) != value.get("tapped", false)
	data = value.duplicate(true)
	_refresh_face()
	if changed_tap:
		_animate_tap()

func _refresh_face() -> void:
	if face != null:
		face.stats_on_face = not show_traits
		if face.refresh(data, selected):
			surface.render_target_update_mode = SubViewport.UPDATE_ONCE
	_redraw_layers()

## Mana symbol for each color the permanent chose as it entered, hanging off the top-right corner.
func _draw_chosen_colors() -> void:
	var unit := size.x / 144.0
	var radius: float = 9.0 * unit * (face.badge_scale if face != null else 1.0)
	var codes: Array = data.get("chosenColors", [])
	for i in range(codes.size()):
		var index: int = ManaCounter.KEYS.find(str(codes[i]))
		if index < 0: continue
		var center := Vector2(size.x - radius * 0.55, radius * 0.55 + i * (radius * 2.0 + 2.0 * unit))
		trait_layer.draw_circle(center + Vector2(0, radius * 0.06), radius, Color(0, 0, 0, 0.55))
		trait_layer.draw_circle(center, radius, ManaCounter.FILLS[index])
		var glyph := String.chr(ManaCounter.GLYPHS[index])
		var glyph_size: int = maxi(6, int(radius * 1.15))
		var width: float = ManaCounter.ICON_FONT.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size).x
		var baseline := center + Vector2(-width * 0.5, (ManaCounter.ICON_FONT.get_ascent(glyph_size) - ManaCounter.ICON_FONT.get_descent(glyph_size)) * 0.5)
		trait_layer.draw_string(ManaCounter.ICON_FONT, baseline, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, glyph_size, Color("17191a"))

## Your playable cards glow purple; hand cards can also show their cost as large mana pips.
func _draw_hand_overlays() -> void:
	if (inspection and not hand_copy) or data.get("faceDown", false): return
	var unit := size.x / 144.0
	var body := Rect2(Vector2.ZERO, size)
	var pick_mark := int(data.get("pickMark", 0))
	if pick_mark > 0:
		# Picked from the hand for a Forge selection: tinted all over (red to discard) with a strong rim.
		var tint: Color = PICK_DISCARD if pick_mark == 2 else PLAYABLE_GLOW
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(tint, 0.4)
		fill.set_corner_radius_all(int(7 * unit))
		fill.anti_aliasing = true
		trait_layer.draw_style_box(fill, body)
		for ring in range(4):
			var rim := StyleBoxFlat.new()
			rim.bg_color = Color.TRANSPARENT
			rim.border_color = Color(tint, 1.0 - ring * 0.22)
			rim.set_border_width_all(maxi(2, int(round(3.0 * unit))))
			rim.set_corner_radius_all(int((7 + ring * 2) * unit))
			rim.anti_aliasing = true
			trait_layer.draw_style_box(rim, body.grow((1.0 + ring * 2.4) * unit))
	elif data.get("pickBlocked", false):
		var shade := StyleBoxFlat.new()
		shade.bg_color = Color(0, 0, 0, 0.6)
		shade.set_corner_radius_all(int(7 * unit))
		trait_layer.draw_style_box(shade, body)
	if pick_mark == 0 and playable_glow and data.get("playable", false):
		for ring in range(4):
			var grow := (1.5 + ring * 2.2) * unit
			var box := StyleBoxFlat.new()
			box.bg_color = Color.TRANSPARENT
			box.border_color = Color(READY_GLOW if data.get("ready", false) else PLAYABLE_GLOW, 0.85 - ring * 0.2)
			box.set_border_width_all(maxi(1, int(round(2.2 * unit))))
			box.set_corner_radius_all(int((7 + ring * 2) * unit))
			box.anti_aliasing = true
			trait_layer.draw_style_box(box, body.grow(grow))
	if mana_overlay and data.get("zone", "") == "Hand":
		var margin := 6.0 * unit
		ManaPips.draw(trait_layer, str(data.get("manaCost", "")), Vector2(margin, 24.0 * unit), 13.0 * unit, size.x - margin * 2.0)

func _borderless_box(radius: int) -> StyleBoxFlat:
	var box := P.box(Color("11171e"), Color.TRANSPARENT, radius, 0)
	box.set_border_width_all(0)
	return box

func _trait_badge_size() -> float:
	return 30.0 * size.x / 144.0 * (face.badge_scale if face != null else 1.0)

## Starts just past a full trait row and hangs off the bottom-right edge, so the two never overlap.
func stats_rect(text: String, font_size: int) -> Rect2:
	var unit := size.x / 144.0
	var badge := _trait_badge_size()
	var left := -badge * 0.5 + TRAITS_PER_ROW * badge + (TRAITS_PER_ROW - 1) * 2.0 * unit + 2.0 * unit
	var width: float = get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0 * unit
	var height: float = STATS_HEIGHT * unit
	return Rect2(left, size.y - height * 0.5, width, height)

func _redraw_layers() -> void:
	if trait_layer != null: trait_layer.queue_redraw()
	if stats_layer != null: stats_layer.queue_redraw()

func _draw_stats() -> void:
	if data.get("zone", "") != "Battlefield" or data.get("hidden", false) or not show_traits or not data.has("power"): return
	var text := str(data.get("stats", ""))
	var font_size: int = maxi(8, int(STATS_FONT * size.x / 144.0))
	var rect := stats_rect(text, font_size)
	var font := get_theme_default_font()
	stats_layer.draw_style_box(_borderless_box(int(rect.size.y * 0.25)), rect)
	var baseline: float = rect.get_center().y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	stats_layer.draw_string(font, Vector2(rect.position.x, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, Color.WHITE)
	# Damage marked this turn: what it is right now (power / toughness left), red, just under the stats.
	var damage := int(data.get("damage", 0))
	if damage > 0:
		var now := "%d/%d" % [int(data.get("power", 0)), int(data.get("toughness", 0)) - damage]
		var hurt := stats_rect(now, font_size)
		hurt.position.y = rect.end.y + 2.0 * size.x / 144.0
		hurt.position.x = rect.position.x + (rect.size.x - hurt.size.x) * 0.5
		var box := _borderless_box(int(hurt.size.y * 0.25))
		box.bg_color = Color("8a1c1c")
		stats_layer.draw_style_box(box, hurt)
		var hurt_baseline: float = hurt.get_center().y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
		stats_layer.draw_string(font, Vector2(hurt.position.x, hurt_baseline), now, HORIZONTAL_ALIGNMENT_CENTER, hurt.size.x, font_size, Color("ffd6d6"))

func _draw_traits() -> void:
	if data.get("hidden", false): return
	if data.get("zone", "") != "Battlefield":
		_draw_hand_overlays()
		return
	if data.get("faceDown", false): return
	_draw_chosen_colors()
	if not show_traits: return
	var keys: Array = Face.trait_keys(data.get("keywords", []))
	if keys.is_empty(): return
	var unit := size.x / 144.0
	var badge := _trait_badge_size()
	var half: float = badge * 0.5
	var font := get_theme_default_font()
	for i in range(keys.size()):
		var column := i % TRAITS_PER_ROW
		var row := i / TRAITS_PER_ROW
		var rect := Rect2(-half + column * (badge + 2.0 * unit), size.y - half + row * (badge + 2.0 * unit), badge, badge)
		trait_layer.draw_style_box(_borderless_box(int(badge * 0.3)), rect)
		if TraitIcons.draw_icon(trait_layer, keys[i], rect.grow(-badge * 0.12), Face.trait_color(keys[i])): continue
		var label: String = Face.trait_icon(keys[i])
		trait_layer.draw_string(font, rect.position + Vector2(0, badge * 0.7), label, HORIZONTAL_ALIGNMENT_CENTER, badge, maxi(6, int(badge * 0.46)), Face.trait_color(keys[i]))

func _arrange() -> void:
	pivot_offset = size * Vector2(0.5, 1.0) if hand_mode else size * 0.5
	# Trait badges are already doubled; small cards get only a slight extra boost so four still fit a row.
	if face != null and size.x > 0 and face.set_badge_scale(clampf(150.0 / size.x, 1.0, 1.15)):
		surface.render_target_update_mode = SubViewport.UPDATE_ONCE
	_redraw_layers()
	if visual != null:
		var ratio := size / Vector2(144, 202)
		if inspection: ratio = Vector2.ONE * minf(ratio.x, ratio.y)
		visual.position = (size - Vector2(144, 202) * ratio) * 0.5 - Vector2(8, 8) * ratio
		visual.size = Vector2(160, 218) * ratio
		visual.material.set_shader_parameter("surface_size", visual.size)
		visual.material.set_shader_parameter("tilt", 0.0)

func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	_refresh_face()

func _mouse_enter() -> void:
	if not hand_mode and not holds_tap_hover():
		_on_enter()

func _mouse_exit() -> void:
	if not hand_mode and not holds_tap_hover():
		_on_exit()

func holds_tap_hover() -> bool:
	# Rotation changes the hit rectangle even when the mouse has not moved.
	return not hand_mode and tap_animation != null and tap_animation.is_valid() and tap_pointer.is_finite() and get_global_mouse_position().distance_to(tap_pointer) < 2.0

func _finish_tap_hover() -> void:
	tap_pointer = Vector2.INF
	if hover_active and not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		_mouse_exit()

func _on_enter() -> void:
	if inspection or drag_active or drop_pointer.is_finite() or reveal_progress < 1.0:
		return
	hover_active = true
	if not zone_browser: visual.hide()
	queue_redraw()
	z_index = resting_z * 2 if hand_mode else 30
	_animate_pose()
	hovered.emit(data)

func _on_exit() -> void:
	if inspection or drag_active:
		return
	hover_active = false
	if not hand_mode:
		visual.show()
	queue_redraw()
	z_index = resting_z * 2 if hand_mode else resting_z
	_animate_pose()
	unhovered.emit()

func _animate_pose() -> void:
	settle_target.clear()
	if not is_inside_tree() or inspection or zone_browser or drag_active:
		return
	if animation != null:
		animation.kill()
	animation = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if hand_mode:
		_stop_tap_animation()
		animation.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		animation.tween_property(self, "hand_hover_amount", 1.0 if hover_active else 0.0, 0.10 if hover_active else 0.14)
		animation.tween_property(self, "rotation", base_rotation, 0.16)
		animation.tween_property(self, "scale", Vector2.ONE, 0.16)
		animation.tween_property(self, "position", resting_position, 0.16)
		return
	_animate_tap()
	var factor := 1.0
	if hover_active:
		factor *= 1.08
	animation.tween_property(self, "scale", Vector2.ONE * factor, 0.15)
	animation.tween_property(self, "position", resting_position + Vector2(0, -12 if hover_active else 0), TAP_SECONDS if tap_animation != null and tap_animation.is_running() else 0.15)

func reveal_from_library() -> void:
	if reveal_animation != null and reveal_animation.is_valid():
		return
	reveal_progress = 0.0
	reveal_animation = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reveal_animation.tween_property(self, "reveal_progress", 1.0, REVEAL_SECONDS)

func _stop_tap_animation() -> void:
	tap_pointer = Vector2.INF
	if tap_animation != null:
		tap_animation.kill()
		tap_animation = null

func _animate_tap() -> void:
	if not is_inside_tree() or inspection or drag_active or hand_mode:
		return
	var target := PI * 0.5 if data.get("tapped", false) else 0.0
	# Layout snapshots and hover hit-area changes must never restart a turn in progress.
	if tap_animation != null and tap_animation.is_valid() and is_equal_approx(tap_target, target):
		return
	_stop_tap_animation()
	tap_target = target
	if is_equal_approx(rotation, target):
		return
	tap_animation = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tap_pointer = get_global_mouse_position()
	tap_animation.tween_property(self, "rotation", target, TAP_SECONDS)
	tap_animation.finished.connect(_finish_tap_hover)

func settle(at: Vector2, dimensions: Vector2, enter: bool = false, immediate: bool = false) -> void:
	var target: Array = [at, dimensions, hand_mode, base_rotation, hover_active, data.get("tapped", false)]
	var unchanged := settle_target == target
	resting_position = at
	size = dimensions
	if not enter and not immediate and unchanged:
		return
	if immediate:
		_stop_tap_animation()
		if animation != null:
			animation.kill()
		position = at
		rotation = base_rotation if hand_mode else (PI * 0.5 if data.get("tapped", false) else 0.0)
		scale = Vector2.ONE
		settle_target = target
		return
	if enter:
		position = at + Vector2(0, 18)
		modulate.a = 0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.22)
	_animate_pose()
	settle_target = target

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not _can_drag_pile():
			inspect_requested.emit(data)
			accept_event()
			return
	if inspection:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		press_button = event.button_index
		pile_gesture = event.button_index == MOUSE_BUTTON_RIGHT or (event.shift_pressed and _pile_movable())
		press_pending = true
		press_pointer = event.global_position
		last_pointer = press_pointer
		held_seconds = 0.0
		press_double_click = event.double_click
		set_process_input(true)
		accept_event()

## Right-dragging an untapped pile moves all of it; a plain right-click still inspects.
func _can_drag_pile() -> bool:
	return not press_pending and _pile_movable()

func _pile_movable() -> bool:
	return not inspection and not zone_browser and can_drag() and data.get("zone", "") == "Battlefield" and int(data.get("pileSize", 1)) > 1 and not data.get("tapped", false)

func can_drag() -> bool:
	return not data.get("hidden", false) and data.get("owner", -1) == 0 and (data.get("zone", "") in ["Battlefield", "Hand"] or (zone_browser and data.get("zone", "") in ["Command", "Graveyard", "Exile"]) or (data.get("zone", "") == "Stack" and data.get("pendingCast", false)))

func _process(delta: float) -> void:
	if rejection > 0:
		queue_redraw()
	if drop_pointer.is_finite() and get_global_mouse_position().distance_to(drop_pointer) > DRAG_DISTANCE:
		drop_pointer = Vector2.INF
	if press_pending and not drag_active:
		held_seconds += delta
		if held_seconds >= HOLD_SECONDS and can_drag() and not pile_gesture:
			_begin_drag()

func reject_action() -> void:
	if rejection_tween != null: rejection_tween.kill()
	rejection = 1.0
	_arrange()
	var original: Vector2 = visual.position
	rejection_tween = create_tween()
	for x in [-7, 6, -4, 3, 0]:
		rejection_tween.tween_property(visual, "position", original + Vector2(x, 0), 0.045)
	rejection_tween.tween_property(self, "rejection", 0.0, 0.35)
	rejection_tween.tween_callback(queue_redraw)

func _draw() -> void:
	if rejection <= 0: return
	for ring in range(7, 0, -1):
		var frame := P.box(Color.TRANSPARENT, Color(1, 0.12, 0.16, rejection * (0.65 if ring == 1 else 0.08)), 8, 0)
		frame.set_border_width_all(2)
		draw_style_box(frame, Rect2(Vector2(-ring, -ring), size + Vector2.ONE * ring * 2))

func _begin_drag() -> void:
	if not press_pending or drag_active or not can_drag():
		return
	# Leave the hover pose before handing the real node to the table's free-movement layer.
	if hover_active:
		_on_exit()
	drag_active = true
	if reveal_animation != null:
		reveal_animation.kill()
	reveal_progress = 1.0
	_stop_tap_animation()
	if animation != null:
		animation.kill()
	drag_started.emit(self, press_pointer)
	drag_moved.emit(self, last_pointer)

func _input(event: InputEvent) -> void:
	if not press_pending:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish_press(true)
	elif event is InputEventMouseMotion:
		last_pointer = event.global_position
		if not drag_active and press_pointer.distance_to(last_pointer) >= DRAG_DISTANCE:
			_begin_drag()
		if drag_active:
			drag_moved.emit(self, last_pointer)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == press_button and not event.pressed:
		last_pointer = event.global_position
		get_viewport().set_input_as_handled()
		_finish_press(false)

func _finish_press(cancelled: bool) -> void:
	var was_drag := drag_active
	press_pending = false
	drag_active = false
	set_process_input(false)
	if was_drag:
		drag_finished.emit(self, cancelled)
	elif not cancelled:
		if press_button == MOUSE_BUTTON_RIGHT: inspect_requested.emit(data)
		else: picked.emit(data, press_double_click)
