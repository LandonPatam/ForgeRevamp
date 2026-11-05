extends Control
signal decision(action: String)
signal card_chosen(id: int)
signal inspect_requested(card: Dictionary)
signal hand_confirmed
const P = preload("res://scripts/ui/Palette.gd")
const Card = preload("res://scripts/ui/CardView.gd")
var shade: ColorRect
var heading: Label
var hint: Label
var display_font: FontVariation
var fan: Control
var selection_overlay: Control
var actions: HBoxContainer
var view_button: Button
var mulligan_button: Button
var keep_button: Button
var views: Array[Control] = []
var poses: Array[Transform2D] = []
var hand_ids: Array = []
var hovered := -1
var input_kind := ""
var active := false
var viewing_board := false
var submitted := false
var can_keep := false
var can_mulligan := false
var input_ready := false
var synthetic_hover := false
var empty_bottom := false
var show_keep_return_count := false
const EXIT_SECONDS := 0.4
var exit_tween: Tween
var keep_requested := false
var layout_scale := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.008, 0.012, 0.018, 0.92)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	display_font = P.display_font()
	heading = _label("Opening Hand", 64, Color.WHITE)
	heading.add_theme_font_override("font", display_font)
	hint = _label("", 24, Color.WHITE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_stylebox_override("normal", P.box(Color("381b22"), Color("ff6969"), 8, 10))
	hint.z_index = 60
	fan = Control.new()
	fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fan)
	selection_overlay = preload("res://scripts/ui/MulliganSelection.gd").new()
	selection_overlay.opening = self
	fan.add_child(selection_overlay)
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	add_child(actions)
	view_button = _button("View Battlefield", _toggle_board, Color("34363a"))
	mulligan_button = _button("Mulligan", func(): submit("cancel"), Color("34363a"))
	keep_button = _button("Keep Hand", func(): submit("ok"), Color("127d99"))
	resized.connect(_layout)
	hide()

func _label(value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result

func _button(value: String, callback: Callable, color: Color) -> Button:
	var result := Button.new()
	result.text = value
	P.style_menu_button(result, color == Color("127d99"))
	result.custom_minimum_size = Vector2(220, 54)
	result.add_theme_font_override("font", display_font)
	result.add_theme_font_size_override("font_size", 20)
	result.pressed.connect(callback)
	actions.add_child(result)
	return result

func present(state: Dictionary) -> void:
	var kind: String = state.get("prompt", {}).get("inputKind", "")
	var complete: bool = state.get("openingHandComplete", false)
	var wanted := not complete and kind in ["InputConfirmMulligan", "InputLondonMulligan"]
	if not wanted:
		if exit_tween != null and exit_tween.is_running(): return
		if active and not complete and kind in ["", "InputLockUI"] and not state.get("game", {}).get("gameOver", false):
			input_ready = false
			_update_buttons()
			return
		if active and (complete or keep_requested) and not state.get("game", {}).get("gameOver", false):
			_fade_to_battlefield()
		else:
			reset()
		return
	if exit_tween != null:
		exit_tween.kill()
		exit_tween = null
		modulate.a = 1.0
		keep_requested = false
	view_button.disabled = false
	var hand: Array = state.players[0].zones.Hand.filter(func(card): return not card.get("hidden", false))
	var ids: Array = hand.map(func(card): return card.id)
	var changed := ids != hand_ids or kind != input_kind
	if not active or changed:
		submitted = false
	if not active:
		viewing_board = false
	active = true
	input_kind = kind
	input_ready = state.get("connectionReady", false) and state.get("asks", []).is_empty()
	can_keep = state.prompt.get("okEnabled", false)
	can_mulligan = state.prompt.get("cancelEnabled", false)
	var chosen: Array = state.prompt.get("chosen", [])
	# London enables OK when the required count is met. If nothing is selected,
	# that means Forge requires zero cards; acknowledge only this empty selection.
	empty_bottom = kind == "InputLondonMulligan" and can_keep and chosen.is_empty()
	hint.text = state.prompt.get("message", "Hover over a card to read it.")
	show_keep_return_count = kind == "InputConfirmMulligan" and state.prompt.has("mulliganReturnCount")
	if show_keep_return_count:
		var count := int(state.prompt.mulliganReturnCount)
		hint.text = "Keep this hand: return %d %s to the bottom of your library." % [count, "card" if count == 1 else "cards"] if count > 0 else "Keep this hand: no cards to return to your library."
		show_keep_return_count = count > 0
	keep_button.tooltip_text = hint.text
	mulligan_button.tooltip_text = hint.text
	keep_button.text = "Confirm Selection" if kind == "InputLondonMulligan" else "Keep Hand"
	mulligan_button.text = "Auto Choose" if kind == "InputLondonMulligan" else "Mulligan"
	keep_button.visible = not empty_bottom
	mulligan_button.visible = not empty_bottom
	if ids != hand_ids:
		for view in views:
			fan.remove_child(view)
			view.queue_free()
		views.clear()
		hand_ids = ids
		hovered = -1
		for card in hand:
			var view := Card.new()
			view.inspection = true
			view.table_angle = false
			view.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fan.add_child(view)
			views.append(view)
	for i in range(hand.size()):
		views[i].update_card(hand[i])
		views[i].set_selected(chosen.has("card:" + str(hand[i].id)))
	selection_overlay.queue_redraw()
	show()
	_update_buttons()
	if changed or poses.size() != views.size():
		_layout()
	_apply_board_view()
	if empty_bottom:
		_confirm_empty_selection.call_deferred()
	elif changed and input_ready:
		keep_button.grab_focus() if not keep_button.disabled else mulligan_button.grab_focus()

func _confirm_empty_selection() -> void:
	# Recheck the latest prompt after snapshot application, including reconnects.
	if empty_bottom and input_kind == "InputLondonMulligan":
		submit("ok")

func _update_buttons() -> void:
	keep_button.disabled = not input_ready or submitted or not can_keep
	mulligan_button.disabled = not input_ready or submitted or not can_mulligan

func submit(action: String) -> void:
	if not active or not input_ready or submitted:
		return
	if (action == "ok" and not can_keep) or (action == "cancel" and not can_mulligan):
		return
	submitted = true
	keep_requested = action == "ok"
	_update_buttons()
	decision.emit(action)

func _fade_to_battlefield() -> void:
	# Wait for Forge to finish keep/bottom selections before revealing the board.
	# Keep the overlay blocking clicks while its cards, buttons and shade fade.
	active = false
	input_ready = false
	hand_confirmed.emit()
	_update_buttons()
	view_button.disabled = true
	exit_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	exit_tween.tween_property(self, "modulate:a", 0.0, EXIT_SECONDS)
	exit_tween.finished.connect(reset)

func reset() -> void:
	if exit_tween != null:
		exit_tween.kill()
		exit_tween = null
	modulate.a = 1.0
	keep_requested = false
	if view_button != null: view_button.disabled = false
	empty_bottom = false
	show_keep_return_count = false
	active = false
	submitted = false
	input_ready = false
	viewing_board = false
	set_hover(-1)
	hide()

func _layout() -> void:
	if fan == null:
		return
	# ScaledSurface halves logical window dimensions. Keep the whole fan and
	# required decisions inside short viewports, preserving the original large layout.
	layout_scale = clampf(size.y / 800.0, 0.4, 1.0)
	heading.add_theme_font_size_override("font_size", roundi(clampf(size.y * 0.064, 52 * layout_scale, 72 * layout_scale)))
	heading.position = Vector2(24 * layout_scale, size.y * 0.16)
	heading.size = Vector2(size.x - 48 * layout_scale, 96 * layout_scale)
	hint.add_theme_font_size_override("font_size", roundi(24 * layout_scale))
	hint.add_theme_stylebox_override("normal", P.box(Color("381b22"), Color("ff6969"), roundi(8 * layout_scale), roundi(10 * layout_scale)))
	hint.position = Vector2(size.x * 0.07, size.y * 0.80)
	hint.size = Vector2(size.x * 0.86, 54 * layout_scale)
	fan.size = size
	actions.position = Vector2(24 * layout_scale, size.y * 0.87)
	actions.size = Vector2(size.x - 48 * layout_scale, 54 * layout_scale)
	actions.z_index = 60
	actions.add_theme_constant_override("separation", roundi(14 * layout_scale))
	for button in [view_button, mulligan_button, keep_button]:
		button.custom_minimum_size = Vector2(220, 54) * layout_scale
		button.add_theme_font_size_override("font_size", roundi(20 * layout_scale))
	poses.clear()
	var card_width := clampf(size.y * 0.30, 210 * layout_scale, 290 * layout_scale)
	var dimensions := Vector2(card_width, card_width * 202.0 / 144.0)
	var spread := minf(card_width * 0.72, (size.x * 0.88 - card_width) / maxf(1, views.size() - 1))
	var total := dimensions.x + spread * maxf(0, views.size() - 1)
	for i in range(views.size()):
		var t: float = 0 if views.size() <= 1 else (float(i) / (views.size() - 1) - 0.5) * 2
		var at := Vector2((size.x - total) * 0.5 + i * spread, size.y * 0.37 + absf(t) * 24 * layout_scale)
		var angle := deg_to_rad(t * 10)
		var view: Control = views[i]
		view.size = dimensions
		view._arrange()
		view.pivot_offset = Vector2(dimensions.x * 0.5, dimensions.y)
		poses.append(Transform2D(angle, at + view.pivot_offset - view.pivot_offset.rotated(angle)))
	_apply_hover(false)

func _process(_delta: float) -> void:
	if active and visible and not viewing_board and not synthetic_hover:
		hover_at(get_local_mouse_position())

func hover_at(point: Vector2) -> void:
	var candidate := -1
	# Pick against the resting fan so a raised card never traps its neighbors.
	for i in range(views.size() - 1, -1, -1):
		if Rect2(Vector2.ZERO, views[i].size).has_point(poses[i].affine_inverse() * point):
			candidate = i
			break
	if candidate < 0 and hovered >= 0 and Rect2(Vector2.ZERO, views[hovered].size).has_point(views[hovered].get_transform().affine_inverse() * point):
		candidate = hovered
	set_hover(candidate)

func set_hover(index: int) -> void:
	if hovered == index:
		return
	hovered = index
	_apply_hover(true)

func _apply_hover(animated: bool) -> void:
	for i in range(poses.size()):
		var view: Control = views[i]
		var raised := i == hovered
		var angle := poses[i].get_rotation()
		var at: Vector2 = poses[i].origin - view.pivot_offset + view.pivot_offset.rotated(angle)
		var target_position := at + Vector2(0, -52 * layout_scale if raised else 0)
		var target_angle := 0.0 if raised else angle
		var target_scale := Vector2.ONE * (1.06 if raised else 1.0)
		view.z_index = 30 if raised else i
		if view.animation != null:
			view.animation.kill()
		if animated:
			view.animation = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			view.animation.tween_property(view, "position", target_position, 0.12)
			view.animation.tween_property(view, "rotation", target_angle, 0.12)
			view.animation.tween_property(view, "scale", target_scale, 0.12)
		else:
			view.position = target_position
			view.rotation = target_angle
			view.scale = target_scale

func _toggle_board() -> void:
	viewing_board = not viewing_board
	set_hover(-1)
	_apply_board_view()

func _apply_board_view() -> void:
	fan.visible = not viewing_board
	heading.visible = not viewing_board
	hint.visible = not viewing_board and ((input_kind == "InputLondonMulligan" and not empty_bottom) or show_keep_return_count)
	shade.color.a = 0.08 if viewing_board else 0.92
	view_button.text = "View Hand" if viewing_board else "View Battlefield"

func _gui_input(event: InputEvent) -> void:
	if viewing_board or not input_ready or submitted:
		return
	if event is InputEventMouseButton and event.pressed:
		hover_at(event.position)
		if hovered < 0:
			return
		var card: Dictionary = views[hovered].data
		if event.button_index == MOUSE_BUTTON_RIGHT:
			inspect_requested.emit(card)
		elif event.button_index == MOUSE_BUTTON_LEFT and (input_kind == "InputLondonMulligan" or card.get("name", "") == "Serum Powder"):
			card_chosen.emit(card.id)
