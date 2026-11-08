extends Control
signal inspect_requested(card: Dictionary)
signal acknowledged(stack_id: int)
signal response_requested(stack_id: int)
const P = preload("res://scripts/ui/Palette.gd")
const Card = preload("res://scripts/ui/CardView.gd")
var panel: PanelContainer
var title: Label
var caster: Label
var targets: Label
var face: Control
var target_cards: GridContainer
var rules: Label
var rules_pages: Control
var eyebrow: Label
var effect_arrow: Control
var targets_scroll: Control
var hover_preview: Control
var hovered_card: Control
var hover_left_inset := 24.0
var blocked: Callable
var active: Dictionary = {}
var waiting: Array = []
var stack_ids: Array = []
var latest := 0
var initialized := false
var remaining := 8.0
var resolve_button: Button
var respond_button: Button
var browse_button: Button
var responding: Array[int] = []
var dismissed: Array[int] = []
var current_state: Dictionary = {}
## Non-blocking notices for untargeted effects on this player ("each opponent loses 1 life").
var notice_panel: PanelContainer
var notice_title: Label
var notice_text: Label
var notices: Array = []
var notice_tween: Tween
const NOTICE_SECONDS := 3.2
## Targeted-player portraits stay near the 100 px Forge atlas cell instead of stretching to card size.
const PLAYER_PORTRAIT_SIDE := 112.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 70
	panel = PanelContainer.new()
	P.style_popup(panel, 18)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	eyebrow = _label("TARGETED EFFECT", 12, Color("6d9fa3"))
	eyebrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(eyebrow)
	var close := Button.new()
	browse_button = close
	close.text = "View battlefield"
	close.tooltip_text = "Keep priority and return to the battlefield to cast a response or activate an ability"
	P.style_popup_button(close)
	close.custom_minimum_size = Vector2(56, 30)
	close.add_theme_font_size_override("font_size", 16)
	close.pressed.connect(respond)
	top.add_child(close)
	title = _label("", 22, Color.WHITE)
	column.add_child(title)
	caster = _label("", 13, Color("6d9fa3"))
	column.add_child(caster)
	var interaction := HBoxContainer.new()
	interaction.alignment = BoxContainer.ALIGNMENT_CENTER
	interaction.add_theme_constant_override("separation", 16)
	column.add_child(interaction)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	interaction.add_child(center)
	face = Card.new()
	face.inspection = true
	face.table_angle = false
	center.add_child(face)
	_enable_card_hover(face)
	var arrow := Control.new()
	effect_arrow = arrow
	arrow.custom_minimum_size = Vector2(56, 250)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.draw.connect(func():
		var y := arrow.size.y * 0.5
		arrow.draw_line(Vector2(4, y), Vector2(48, y), Color("bd9bf2"), 4, true)
		arrow.draw_colored_polygon(PackedVector2Array([Vector2(52, y), Vector2(36, y - 10), Vector2(36, y + 10)]), Color("bd9bf2")))
	interaction.add_child(arrow)
	var pager := preload("res://scripts/ui/PagedChoices.gd").new()
	targets_scroll = pager
	interaction.add_child(pager)
	pager.configure(2, 4)
	target_cards = pager.grid
	targets = _label("", 15, P.TEXT)
	column.add_child(targets)
	rules_pages = preload("res://scripts/ui/ReadableText.gd").new()
	column.add_child(rules_pages)
	rules = rules_pages.label
	rules_pages.present("", 500, 110, 14)
	rules_pages.hide()
	respond_button = Button.new()
	resolve_button = respond_button
	respond_button.text = "Resolve"
	respond_button.tooltip_text = "Pass priority for this spell or ability. Forge handles its resolution and required decisions."
	P.style_popup_button(respond_button, true)
	respond_button.pressed.connect(dismiss)
	column.add_child(respond_button)
	hover_preview = Card.new()
	hover_preview.inspection = true
	hover_preview.table_angle = false
	hover_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_preview.z_index = 1
	add_child(hover_preview)
	hover_preview.hide()
	notice_panel = PanelContainer.new()
	P.style_popup(notice_panel, 14)
	notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var notice_column := VBoxContainer.new()
	notice_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_column.add_theme_constant_override("separation", 4)
	notice_panel.add_child(notice_column)
	notice_title = _label("", 13, Color("6d9fa3"))
	notice_column.add_child(notice_title)
	notice_text = _label("", 17, Color.WHITE)
	notice_column.add_child(notice_text)
	add_child(notice_panel)
	notice_panel.hide()
	panel.minimum_size_changed.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	resized.connect(_layout)
	panel.hide()

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func present(state: Dictionary) -> void:
	current_state = state
	stack_ids = state.get("stack", []).map(func(item): return int(item.id))
	for completed in responding.duplicate():
		if not stack_ids.has(completed): acknowledge_stack(completed)
	responding.assign(responding.filter(func(id): return stack_ids.has(id)))
	var events: Array = state.get("targetedEffects", [])
	var auto_resolve: bool = state.get("autoResolveAll", false)
	for event in events:
		if event.get("kind", "") == "notice":
			if int(event.id) > latest and initialized: _queue_notice(event)
			latest = maxi(latest, int(event.id))
			continue
		if auto_resolve:
			# Only threats: a held, respondable effect gets the blocking popup from _offer_priority.
			# One this seat cannot answer still shows its card and arrow, closing on its own timer.
			if int(event.id) > latest and initialized and event.get("kind", "") in ["targeted", "massRemoval"] and not dismissed.has(int(event.stackId)) and not _held_here(state, int(event.stackId)):
				var shown: Dictionary = event.duplicate(true)
				shown.noResponse = true
				waiting.append(shown)
			latest = maxi(latest, int(event.id))
			continue
		if int(event.id) > latest and (initialized or stack_ids.has(int(event.stackId))):
			if dismissed.has(int(event.stackId)):
				latest = maxi(latest, int(event.id))
				continue
			if int(active.get("stackId", -1)) == int(event.stackId):
				var time_left := remaining
				active = {}
				waiting.push_front(event.duplicate(true))
				_next()
				remaining = time_left
			elif event.get("kind", "") == "massRemoval":
				if not active.is_empty(): waiting.push_front(active.duplicate(true))
				active = {}
				waiting.push_front(event.duplicate(true))
			else:
				waiting.append(event.duplicate(true))
		latest = maxi(latest, int(event.id))
	initialized = true
	if active.is_empty():
		_next()
	_offer_priority()
	_update_actions()

func _offer_priority(force: bool = false) -> void:
	# Routine stack changes stay in the rail. Direct targets still get a visual
	# interaction for opponents; our own choices remain in the rail.
	if not force and not current_state.get("autoResolveAll", false) and (current_state.get("stack", []).is_empty() or current_state.stack[0].get("targets", []).is_empty()): return
	var stack: Array = current_state.get("stack", [])
	if int(current_state.get("pendingCastId", -1)) >= 0 or current_state.get("game", {}).get("gameOver", false): return
	var auto_resolve: bool = current_state.get("autoResolveAll", false)
	if not force and auto_resolve and not preload("res://scripts/bridge/LiveAdapter.gd").holds_for_response(current_state): return # Passing on its own.
	if stack.is_empty() or current_state.get("prompt", {}).get("inputKind", "") != "InputPassPriority": return
	var item: Dictionary = stack[0]
	# Our target choices already show the effect; keep priority in the rail.
	if not force and int(item.get("card", {}).get("owner", -1)) == 0: return
	var id := int(item.id)
	if not force and not auto_resolve and item.has("targetsLocal") and not item.targetsLocal: return
	if not item.has("card") or (not force and (responding.has(id) or dismissed.has(id) or int(current_state.get("autoPassStackId", -1)) == id)): return
	if int(active.get("stackId", -1)) == id: return
	var notice := {"id": -id - 1, "stackId": id, "source": item.card, "effectText": item.get("text", ""), "controllerName": item.get("controllerName", "Player"), "ability": item.get("ability", false), "targets": item.get("targets", []), "kind": "effect"}
	if auto_resolve:
		# Keep the bridge's board-wide/targeted framing for the one popup auto-resolve still shows.
		for event in current_state.get("targetedEffects", []):
			if int(event.get("stackId", -1)) == id: notice = event.duplicate(true)
	for queued in waiting:
		if int(queued.stackId) == id:
			notice = queued
			waiting.erase(queued)
			break
	if not active.is_empty(): waiting.push_front(active)
	active = {}
	waiting.push_front(notice)
	_next()

func review() -> void:
	if current_state.get("stack", []).is_empty(): return
	var id := int(current_state.stack[0].id)
	responding.erase(id)
	dismissed.erase(id)
	_offer_priority(true)
	panel.show()
	_update_actions()

func respond() -> void:
	var id := int(active.get("stackId", -1))
	if not stack_ids.has(id): return
	if not responding.has(id): responding.append(id)
	_clear_hover()
	panel.hide()
	response_requested.emit(id)

func _update_actions() -> void:
	var pending_effect: bool = stack_ids.has(int(active.get("stackId", -1)))
	var no_response: bool = active.get("noResponse", false)
	resolve_button.text = "OK" if no_response else ("Resolve" if pending_effect else "Close")
	browse_button.visible = pending_effect and not no_response

func _next() -> void:
	_clear_hover()
	if waiting.is_empty():
		active = {}
		panel.hide()
		return
	active = waiting.pop_front()
	remaining = 8.0
	var source: Dictionary = active.get("source", {})
	var mass_removal: bool = active.get("kind", "") == "massRemoval"
	eyebrow.text = "BOARD-WIDE EFFECT" if mass_removal else ("SPELL / ABILITY" if active.get("kind", "") == "effect" else "TARGETED EFFECT")
	if active.get("noResponse", false): eyebrow.text += "  ·  NO RESPONSE AVAILABLE"
	eyebrow.add_theme_color_override("font_color", Color("ffb978") if mass_removal else Color("6d9fa3"))
	effect_arrow.visible = not mass_removal and not active.get("targets", []).is_empty()
	targets_scroll.visible = effect_arrow.visible
	title.text = source.get("name", "Hidden source")
	caster.text = "From " + active.get("controllerName", "Opponent")
	var names: Array = active.get("targets", []).map(func(target): return str(target.get("name", "Your card")))
	targets.text = "Targets: " + ", ".join(names) if names.size() <= 3 else "%d targets - use the card pages above to inspect each one." % names.size()
	targets.visible = mass_removal or not names.is_empty()
	if mass_removal: targets.text = "This spell or ability can affect multiple permanents."
	targets_scroll.page = 0
	for child in target_cards.get_children():
		target_cards.remove_child(child)
		child.queue_free()
	for target in active.get("targets", []):
		if target.get("kind", "") == "player":
			target_cards.add_child(_player_target(target))
			continue
		var target_face := Card.new()
		target_face.inspection = true
		target_face.table_angle = false
		target_face.custom_minimum_size = Vector2(144, 202)
		target_cards.add_child(target_face)
		_enable_card_hover(target_face)
		target_face.update_card(target.get("card", {"id": target.id, "name": target.get("name", "Target")}))
	rules.text = active.get("effectText", source.get("text", ""))
	rules.max_lines_visible = -1
	face.update_card(source)
	_update_actions()
	_layout()
	panel.visible = not responding.has(int(active.stackId))
	panel.modulate.a = 0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.12)

## A targeted player reads like a card slot: their Forge portrait with their name beneath it.
func _player_target(target: Dictionary) -> Control:
	var engine_id := int(target.get("id", -1))
	var player: Dictionary = {}
	for candidate in current_state.get("players", []):
		if int(candidate.get("engineId", candidate.get("id", -2))) == engine_id: player = candidate
	if player.is_empty(): player = {"name": str(target.get("name", "Player")), "life": 0}
	var tile := VBoxContainer.new()
	tile.set_meta("player_target", true)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.alignment = BoxContainer.ALIGNMENT_CENTER
	tile.add_theme_constant_override("separation", 10)
	var portrait := preload("res://scripts/ui/PlayerAvatar.gd").new()
	portrait.name = "Portrait"
	portrait.portrait_only = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile.add_child(portrait)
	portrait.set_player(player, false)
	portrait.tooltip_text = ""
	var label := _label(str(player.get("name", target.get("name", "Player"))) + (" (you)" if int(player.get("id", -1)) == 0 else ""), 20, P.TEXT)
	label.name = "PlayerName"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tile.add_child(label)
	_size_player_target(tile, face.custom_minimum_size)
	return tile

func _size_player_target(tile: Control, card_size: Vector2) -> void:
	tile.custom_minimum_size = card_size
	# Forge's avatar atlas cells are 100 px; scaling them to card size looks grainy, so stay near native.
	var side := minf(PLAYER_PORTRAIT_SIDE, minf(card_size.x, card_size.y - 40))
	tile.get_node("Portrait").custom_minimum_size = Vector2.ONE * side
	tile.get_node("PlayerName").custom_minimum_size.x = card_size.x

func dismiss() -> void:
	var stack_id := int(active.get("stackId", -1))
	acknowledge_stack(stack_id)
	if stack_id >= 0: acknowledged.emit(stack_id)

func acknowledge_stack(stack_id: int) -> void:
	if stack_id < 0: return
	if not dismissed.has(stack_id): dismissed.append(stack_id)
	responding.erase(stack_id)
	waiting = waiting.filter(func(event): return int(event.get("stackId", -1)) != stack_id)
	if int(active.get("stackId", -1)) == stack_id: _next()

func _held_here(state: Dictionary, stack_id: int) -> bool:
	var stack: Array = state.get("stack", [])
	return not stack.is_empty() and int(stack[0].get("id", -1)) == stack_id and preload("res://scripts/bridge/LiveAdapter.gd").holds_for_response(state)

func _queue_notice(event: Dictionary) -> void:
	notices.append(event.duplicate(true))
	if notice_tween == null or not notice_tween.is_running(): _next_notice()

func _next_notice() -> void:
	if notices.is_empty():
		notice_panel.hide()
		return
	var event: Dictionary = notices.pop_front()
	notice_title.text = "%s  ·  %s" % [event.get("controllerName", "Opponent"), event.get("source", {}).get("name", "Hidden source")]
	notice_text.text = str(event.get("effectText", ""))
	notice_panel.modulate.a = 0.0
	notice_panel.show()
	_layout()
	notice_tween = create_tween()
	notice_tween.tween_property(notice_panel, "modulate:a", 1.0, 0.15)
	notice_tween.tween_interval(NOTICE_SECONDS)
	notice_tween.tween_property(notice_panel, "modulate:a", 0.0, 0.35)
	notice_tween.tween_callback(_next_notice)

func reset() -> void:
	_clear_hover()
	notices.clear()
	if notice_tween != null: notice_tween.kill()
	if notice_panel != null: notice_panel.hide()
	active = {}
	waiting.clear()
	stack_ids.clear()
	responding.clear()
	dismissed.clear()
	current_state = {}
	latest = 0
	initialized = false
	panel.hide()

func _layout() -> void:
	if panel == null:
		return
	var available := get_viewport_rect().size
	if notice_panel != null and notice_panel.visible:
		notice_panel.size = Vector2(minf(520, available.x - 32), 0)
		notice_text.custom_minimum_size.x = notice_panel.size.x - 36
		notice_panel.position = Vector2((available.x - notice_panel.size.x) * 0.5, 24)
	var width := minf(1040, maxf(580, available.x - 96))
	var height := clampf(available.y - 340, 300, 540)
	face.custom_minimum_size = Vector2(height * 144 / 202, height)
	for target in target_cards.get_children():
		if target is Card: target.custom_minimum_size = face.custom_minimum_size
		elif target.has_meta("player_target"): _size_player_target(target, face.custom_minimum_size)
	var columns := clampi(int((width - face.custom_minimum_size.x - 124) / (face.custom_minimum_size.x + 12)), 1, 3)
	targets_scroll.configure(columns, columns)
	# Reserve room for the header, card gallery, both page controls and response action.
	rules_pages.hide()
	panel.size = Vector2(width, 0)
	panel.position = Vector2(maxf(16, (available.x - panel.size.x) * 0.5), maxf(24, (available.y - panel.size.y) * 0.5))
	_layout_hover()

func _enable_card_hover(card: Control) -> void:
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_entered.connect(_show_hover.bind(card))
	card.mouse_exited.connect(_hide_hover.bind(card))
	card.inspect_requested.connect(func(data): inspect_requested.emit(data))

func _show_hover(card: Control) -> void:
	if not panel.visible or card.data.get("hidden", false):
		_clear_hover()
		return
	hovered_card = card
	hover_preview.update_card(card.data)
	_layout_hover()
	hover_preview.show()

func _hide_hover(card: Control) -> void:
	if hovered_card == card: _clear_hover()

func _clear_hover() -> void:
	hovered_card = null
	if is_instance_valid(hover_preview): hover_preview.hide()

func _layout_hover() -> void:
	if not is_instance_valid(hovered_card): return
	var height := minf(clampf(size.y * 0.42, 360, 440) * 1.25, size.y - 48)
	var width := height * 144.0 / 202
	var source_on_right: bool = hovered_card.get_global_rect().get_center().x >= get_global_rect().get_center().x
	hover_preview.size = Vector2(width, height)
	hover_preview.position = Vector2(minf(hover_left_inset, size.x - width - 24) if source_on_right else size.x - width - 24, (size.y - height) * 0.5)

func _process(delta: float) -> void:
	if active.is_empty():
		return
	var suspended: bool = blocked.is_valid() and blocked.call()
	panel.visible = not suspended and not responding.has(int(active.get("stackId", -1)))
	if suspended:
		_clear_hover()
		return
	if not panel.visible: return
	if is_instance_valid(hovered_card) or stack_ids.has(int(active.stackId)) or panel.get_global_rect().has_point(get_global_mouse_position()):
		return
	remaining -= delta
	if remaining <= 0:
		_next()
