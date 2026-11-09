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
## The visible table (Main sets it); small effect cards center on it. Empty: the whole viewport.
var table_rect := Rect2()
var blocked: Callable
var active: Dictionary = {}
var waiting: Array = []
var stack_ids: Array = []
var latest := 0
var initialized := false
var resolve_button: Button
var respond_button: Button
var browse_button: Button
var responding: Array[int] = []
var dismissed: Array[int] = []
var current_state: Dictionary = {}
## Small card popups for anything that is not waiting on this seat: the source card, an arrow to
## your affected cards, and OK. They never hold the game and stay until OK (which is local only).
var notice_panel: PanelContainer
var notice_title: Label
var notice_count: Label
var notice_text: Label
var notice_source: Control
var notice_arrow: Control
var notice_targets: HBoxContainer
var notice_ok: Button
var notices: Array = []
var notice_active: Dictionary = {}
const NOTICE_CARD := Vector2(150, 210)
## A board wipe waiting on this seat: its card large in the middle of the table, lines branching
## out to every permanent it will reach (all players'), and a small terminal bar with Resolve.
var wipe_mode := false
var wipe_card: Control
var wipe_bar: PanelContainer
var wipe_title: Label
var wipe_detail: Label
var wipe_resolve: Button
var wipe_started := 0
## Main supplies the table's card views: func(id: int) -> Control (or null).
var card_view: Callable
## ...and player portraits by engine id, for effects that target a player.
var player_view: Callable
var wipe_heading: Label
## The same table view for a spell or ability aimed at your things (Aether Spellbomb -> your Angel):
## its card mid-table, a branch to each of your targets.
var aimed := false
const WIPE_LINE := Color("ffb978")
const NOTICE_MAX_TARGETS := 3
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
	close.text = "Respond with action"
	close.tooltip_text = "Keep priority and go to the table to cast a spell or activate an ability in response."
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
	_build_notice()
	_build_wipe()
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
	# A big popup whose item resolved while it was showing becomes a small card you can OK.
	if not active.is_empty() and not stack_ids.has(int(active.get("stackId", -1))) and not responding.has(int(active.get("stackId", -1))):
		_queue_notice(active)
		active = {}
		_next()
	var events: Array = state.get("targetedEffects", [])
	var auto_resolve: bool = state.get("autoResolveAll", false)
	for event in events:
		if event.get("kind", "") == "notice":
			if int(event.id) > latest and initialized: _queue_notice(event)
			latest = maxi(latest, int(event.id))
			continue
		var stack_id := int(event.get("stackId", -1))
		if int(event.id) > latest and dismissed.has(stack_id):
			latest = maxi(latest, int(event.id))
			continue
		# Not waiting on this seat (already resolved, passing without a response, or Only threats
		# with nothing to answer): the small card popup, never the decision popup.
		var informational: bool = not stack_ids.has(stack_id) or int(state.get("autoPassStackId", -1)) == stack_id or (auto_resolve and not _held_here(state, stack_id))
		if auto_resolve or informational:
			if int(event.id) > latest and initialized and informational: _queue_notice(event)
			latest = maxi(latest, int(event.id))
			continue
		if int(event.id) > latest and (initialized or stack_ids.has(stack_id)):
			if int(active.get("stackId", -1)) == int(event.stackId):
				active = {}
				waiting.push_front(event.duplicate(true))
				_next()
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
	_drop_notice(id) # The decision popup replaces a small card for the same item.
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
	if wipe_mode: _set_wipe_visible(true)
	else: panel.show()
	_update_actions()

func respond() -> void:
	var id := int(active.get("stackId", -1))
	if not stack_ids.has(id): return
	if not responding.has(id): responding.append(id)
	_clear_hover()
	panel.hide()
	_set_wipe_visible(false)
	response_requested.emit(id)

func _update_actions() -> void:
	var pending_effect: bool = stack_ids.has(int(active.get("stackId", -1)))
	resolve_button.text = "I accept" if pending_effect else "Close"
	browse_button.visible = pending_effect

func _next() -> void:
	_clear_hover()
	if waiting.is_empty():
		active = {}
		panel.hide()
		_hide_wipe()
		return
	active = waiting.pop_front()
	var source: Dictionary = active.get("source", {})
	var mass_removal: bool = active.get("kind", "") == "massRemoval"
	eyebrow.text = "BOARD-WIDE EFFECT" if mass_removal else ("SPELL / ABILITY" if active.get("kind", "") == "effect" else "TARGETED EFFECT")
	eyebrow.add_theme_color_override("font_color", Color("ffb978") if mass_removal else Color("6d9fa3"))
	effect_arrow.visible = not mass_removal and not active.get("targets", []).is_empty()
	targets_scroll.visible = effect_arrow.visible
	title.text = str(source.get("name", "Hidden source")) + _x_suffix(active)
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
	aimed = not mass_removal and not active.get("targets", []).is_empty()
	wipe_mode = (mass_removal or aimed) and table_rect.has_area()
	if wipe_mode: _show_wipe()
	else: _hide_wipe()
	_layout()
	panel.visible = not wipe_mode and not responding.has(int(active.stackId))
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

func _build_notice() -> void:
	notice_panel = PanelContainer.new()
	P.style_popup(notice_panel, 14)
	notice_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	notice_panel.add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	notice_title = _label("", 13, Color("6d9fa3"))
	notice_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	notice_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notice_title.clip_text = true
	top.add_child(notice_title)
	notice_count = _label("", 12, P.MUTED)
	notice_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(notice_count)
	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 10)
	column.add_child(cards)
	notice_source = Card.new()
	notice_source.inspection = true
	notice_source.table_angle = false
	notice_source.custom_minimum_size = NOTICE_CARD
	cards.add_child(notice_source)
	_enable_card_hover(notice_source)
	notice_arrow = Control.new()
	notice_arrow.custom_minimum_size = Vector2(40, NOTICE_CARD.y)
	notice_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_arrow.draw.connect(func():
		var y := notice_arrow.size.y * 0.5
		notice_arrow.draw_line(Vector2(2, y), Vector2(34, y), Color("bd9bf2"), 3, true)
		notice_arrow.draw_colored_polygon(PackedVector2Array([Vector2(38, y), Vector2(26, y - 8), Vector2(26, y + 8)]), Color("bd9bf2")))
	cards.add_child(notice_arrow)
	notice_targets = HBoxContainer.new()
	notice_targets.add_theme_constant_override("separation", 6)
	cards.add_child(notice_targets)
	notice_text = _label("", 14, P.TEXT)
	notice_text.max_lines_visible = 3
	notice_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(notice_text)
	notice_ok = Button.new()
	notice_ok.text = "OK"
	notice_ok.tooltip_text = "Close this notice. It only clears your screen; the game has already moved on."
	P.style_popup_button(notice_ok, true)
	notice_ok.custom_minimum_size.x = 96
	notice_ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	notice_ok.pressed.connect(close_notice)
	column.add_child(notice_ok)
	add_child(notice_panel)
	notice_panel.hide()

func _queue_notice(event: Dictionary) -> void:
	var stack_id := int(event.get("stackId", -1))
	if stack_id >= 0 and (int(notice_active.get("stackId", -2)) == stack_id or notices.any(func(queued): return int(queued.get("stackId", -2)) == stack_id)): return
	notices.append(event.duplicate(true))
	if notice_active.is_empty(): _next_notice()
	else: _update_notice_count()

## OK on the small card: clears it from this screen only, never an engine answer.
func close_notice() -> void:
	var stack_id := int(notice_active.get("stackId", -1))
	if stack_id >= 0 and not dismissed.has(stack_id): dismissed.append(stack_id)
	_clear_hover()
	_next_notice()

func _drop_notice(stack_id: int) -> void:
	notices = notices.filter(func(queued): return int(queued.get("stackId", -2)) != stack_id)
	if int(notice_active.get("stackId", -2)) == stack_id: _next_notice()
	else: _update_notice_count()

func _next_notice() -> void:
	if notices.is_empty():
		notice_active = {}
		notice_panel.hide()
		return
	notice_active = notices.pop_front()
	var source: Dictionary = notice_active.get("source", {})
	var kind: String = notice_active.get("kind", "")
	var targets: Array = notice_active.get("targets", [])
	var heading := "BOARD-WIDE EFFECT" if kind == "massRemoval" else ("TARGETED YOU" if not targets.is_empty() else "AFFECTS YOU")
	notice_title.text = "%s  ·  %s  ·  %s%s" % [heading, notice_active.get("controllerName", "Opponent"), source.get("name", "Hidden source"), _x_suffix(notice_active)]
	notice_title.add_theme_color_override("font_color", Color("ffb978") if kind == "massRemoval" else Color("6d9fa3"))
	notice_source.update_card(source if not source.is_empty() else {"id": -1, "hidden": true})
	for child in notice_targets.get_children():
		notice_targets.remove_child(child)
		child.queue_free()
	for index in range(mini(targets.size(), NOTICE_MAX_TARGETS)):
		var target: Dictionary = targets[index]
		if target.get("kind", "") == "player":
			var tile := _player_target(target)
			_size_player_target(tile, NOTICE_CARD)
			tile.get_node("PlayerName").add_theme_font_size_override("font_size", 14)
			notice_targets.add_child(tile)
			continue
		var view := Card.new()
		view.inspection = true
		view.table_angle = false
		view.custom_minimum_size = NOTICE_CARD
		notice_targets.add_child(view)
		_enable_card_hover(view)
		view.update_card(target.get("card", {"id": target.get("id", -1), "name": target.get("name", "Target")}))
	if targets.size() > NOTICE_MAX_TARGETS:
		notice_targets.add_child(_label("+%d more" % (targets.size() - NOTICE_MAX_TARGETS), 14, P.MUTED))
	notice_arrow.visible = not targets.is_empty()
	notice_targets.visible = not targets.is_empty()
	var names: Array = targets.map(func(target): return "you" if target.get("kind", "") == "player" else "your " + str(target.get("name", "card")))
	var lead := ""
	if not names.is_empty(): lead = "Targeted " + (", ".join(names) if names.size() <= 3 else "%d of your things" % names.size()) + ".  "
	notice_text.text = lead + str(notice_active.get("effectText", source.get("text", "")))
	_update_notice_count()
	notice_panel.show()
	notice_panel.modulate.a = 0.0
	create_tween().tween_property(notice_panel, "modulate:a", 1.0, 0.15)
	_layout()

func _update_notice_count() -> void:
	notice_count.text = "+%d more" % notices.size() if not notices.is_empty() else ""

func reset() -> void:
	_clear_hover()
	notices.clear()
	notice_active = {}
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
	_hide_wipe()

## "  ·  X = 4" for a spell or ability cast with X (Earthquake, Blaze), else "".
func _x_suffix(event: Dictionary) -> String:
	var x: Variant = event.get("xValue", null)
	if x == null:
		for item in current_state.get("stack", []):
			if int(item.get("id", -1)) == int(event.get("stackId", -2)): x = item.get("xValue", null)
	return "" if x == null else "  ·  X = %d" % int(x)

## Whether a decision-style popup (the large one or the wipe overlay) is up on this seat.
func showing() -> bool:
	return panel.visible or (wipe_card != null and wipe_card.visible)

func _build_wipe() -> void:
	var Terminal = preload("res://scripts/ui/TerminalStyle.gd")
	wipe_card = Card.new()
	wipe_card.inspection = true
	wipe_card.table_angle = false
	add_child(wipe_card)
	_enable_card_hover(wipe_card)
	wipe_bar = PanelContainer.new()
	Terminal.panel(wipe_bar, 12)
	var frame := wipe_bar.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	frame.border_color = WIPE_LINE
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 10
	wipe_bar.add_theme_stylebox_override("panel", frame)
	wipe_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(wipe_bar)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	wipe_bar.add_child(column)
	wipe_heading = _label("BOARD-WIDE EFFECT", 12, WIPE_LINE)
	wipe_heading.add_theme_font_override("font", Terminal.font())
	column.add_child(wipe_heading)
	wipe_title = _label("", 20, Color.WHITE)
	wipe_title.add_theme_font_override("font", Terminal.font())
	column.add_child(wipe_title)
	wipe_detail = _label("", 14, Terminal.INK)
	wipe_detail.add_theme_font_override("font", Terminal.font())
	wipe_detail.custom_minimum_size.x = 260
	column.add_child(wipe_detail)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	var view := Button.new()
	view.text = "Respond with action"
	view.tooltip_text = "Keep priority and go to the table to cast a spell or activate an ability in response."
	Terminal.button(view)
	view.pressed.connect(respond)
	row.add_child(view)
	wipe_resolve = Button.new()
	wipe_resolve.text = "I accept"
	wipe_resolve.tooltip_text = "Pass priority: you accept that this board-wide effect resolves."
	Terminal.button(wipe_resolve, true)
	wipe_resolve.pressed.connect(dismiss)
	row.add_child(wipe_resolve)
	wipe_card.hide()
	wipe_bar.hide()

func _show_wipe() -> void:
	var source: Dictionary = active.get("source", {})
	wipe_card.update_card(source if not source.is_empty() else {"id": -1, "hidden": true})
	wipe_title.text = str(source.get("name", "Hidden source")).to_upper() + _x_suffix(active)
	wipe_heading.text = "TARGETED EFFECT" if aimed else "BOARD-WIDE EFFECT"
	_count_wipe()
	wipe_started = Time.get_ticks_msec()
	_set_wipe_visible(not responding.has(int(active.get("stackId", -1))))
	wipe_card.modulate.a = 0.0
	wipe_bar.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(wipe_card, "modulate:a", 1.0, 0.18)
	tween.tween_property(wipe_bar, "modulate:a", 1.0, 0.18)

## Counted from the table each frame: the views settle after the snapshot that opened the wipe.
func _count_wipe() -> void:
	if aimed:
		var names: Array = active.get("targets", []).map(func(target): return "you" if target.get("kind", "") == "player" else "your " + str(target.get("name", "card")))
		wipe_detail.text = "> from %s\n> targets %s" % [active.get("controllerName", "Opponent"), ", ".join(names) if names.size() <= 3 else "%d of your things" % names.size()]
		return
	var reached := _wipe_views()
	var yours := 0
	for view in reached:
		if int(view.data.get("owner", -1)) == 0: yours += 1
	wipe_detail.text = "> from %s\n> reaches %d permanent%s, %d of yours" % [active.get("controllerName", "Opponent"), reached.size(), "" if reached.size() == 1 else "s", yours]

func _hide_wipe() -> void:
	wipe_mode = false
	_set_wipe_visible(false)

func _set_wipe_visible(value: bool) -> void:
	if wipe_card == null: return
	wipe_card.visible = value and wipe_mode
	wipe_bar.visible = wipe_card.visible
	queue_redraw()

## The table views of the permanents the wipe reaches, one per visible view (a pile counts once).
func _wipe_views() -> Array:
	var views: Array = []
	if not card_view.is_valid(): return views
	if aimed:
		for target in active.get("targets", []):
			var aimed_view: Control = null
			if target.get("kind", "") == "player":
				if player_view.is_valid(): aimed_view = player_view.call(int(target.get("id", -1)))
			else: aimed_view = card_view.call(int(target.get("id", -1)))
			if is_instance_valid(aimed_view) and aimed_view.is_visible_in_tree() and not views.has(aimed_view): views.append(aimed_view)
		return views
	for id in active.get("affected", []):
		var view: Control = card_view.call(int(id))
		if is_instance_valid(view) and view.is_visible_in_tree() and not views.has(view): views.append(view)
	return views

## Branches grow out from the spell to each permanent it reaches; yours are brighter, each gets a
## pulsing frame and a spark that runs along its branch.
func _draw() -> void:
	if wipe_card == null or not wipe_card.visible: return
	var to_local := get_global_transform().affine_inverse()
	var origin: Vector2 = to_local * wipe_card.get_global_rect().get_center()
	var age := (Time.get_ticks_msec() - wipe_started) / 1000.0
	var grow := clampf(age / 0.45, 0.0, 1.0)
	grow = 1.0 - pow(1.0 - grow, 3.0)
	var pulse := 0.55 + 0.45 * sin(age * 4.0)
	for view in _wipe_views():
		# The card's own transform, so a tapped (turned) card gets its frame and branch where it is.
		var card_transform: Transform2D = to_local * view.get_global_transform()
		var target: Vector2 = card_transform * (view.size * 0.5)
		var mine := aimed or int(view.data.get("owner", -1)) == 0
		var color := Color(WIPE_LINE, 1.0 if mine else 0.7)
		var bend := origin.lerp(target, 0.5) + Vector2(0, -0.12 * origin.distance_to(target))
		var points := PackedVector2Array()
		var steps := 24
		for i in range(int(steps * grow) + 1):
			var t := float(i) / steps
			points.append(origin.lerp(bend, t).lerp(bend.lerp(target, t), t))
		if points.size() >= 2:
			draw_polyline(points, Color(color, color.a * 0.28), 16.0 if mine else 11.0, true)
			draw_polyline(points, color, 4.5 if mine else 3.0, true)
		if grow >= 1.0:
			var spark_t := fmod(age * 0.7 + float(view.get_instance_id() % 97) / 97.0, 1.0)
			var spark := origin.lerp(bend, spark_t).lerp(bend.lerp(target, spark_t), spark_t)
			draw_circle(spark, 6.0 if mine else 4.5, Color(1, 0.9, 0.75, 0.95))
			var frame := P.box(Color(WIPE_LINE, 0.12 * pulse), Color(WIPE_LINE, 0.4 + 0.6 * pulse), 8, 0)
			frame.set_border_width_all(4 if mine else 3)
			draw_set_transform_matrix(card_transform)
			draw_style_box(frame, Rect2(Vector2.ZERO, view.size).grow(4))
			draw_set_transform_matrix(Transform2D.IDENTITY)

func _layout_wipe() -> void:
	if wipe_card == null or not table_rect.has_area(): return
	var height := clampf(table_rect.size.y * 0.62, 260, 520)
	var card_size := Vector2(height * 144.0 / 202.0, height).round()
	wipe_card.size = card_size
	wipe_card.custom_minimum_size = card_size
	wipe_bar.reset_size()
	var gap := 24.0
	var total := card_size.x + gap + wipe_bar.size.x
	var left := table_rect.get_center().x - total * 0.5
	wipe_card.position = Vector2(left, table_rect.get_center().y - card_size.y * 0.5).round()
	wipe_bar.position = Vector2(left + card_size.x + gap, table_rect.get_center().y - wipe_bar.size.y * 0.5).round()

func _layout() -> void:
	if panel == null:
		return
	_layout_wipe()
	var available := get_viewport_rect().size
	if notice_panel != null and notice_panel.visible:
		# A small card in the middle of the table, never over the rail.
		var area: Rect2 = table_rect if table_rect.has_area() else Rect2(Vector2.ZERO, available)
		var notice_width := minf(460, area.size.x - 32)
		notice_text.custom_minimum_size.x = notice_width - 32
		notice_panel.size = Vector2(notice_width, 0)
		notice_panel.size = Vector2(notice_width, notice_panel.get_combined_minimum_size().y)
		var centered := area.get_center() - notice_panel.size * 0.5
		notice_panel.position = Vector2(clampf(centered.x, 16, maxf(16, available.x - notice_panel.size.x - 16)), clampf(centered.y, 16, maxf(16, available.y - notice_panel.size.y - 16))).round()
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
	if not (panel.visible or notice_panel.visible) or card.data.get("hidden", false):
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

func _process(_delta: float) -> void:
	var suspended: bool = blocked.is_valid() and blocked.call()
	# Required dialogs come first; a pending small card waits underneath and returns afterwards.
	if notice_panel != null: notice_panel.visible = not notice_active.is_empty() and not suspended
	if active.is_empty():
		return
	panel.visible = not wipe_mode and not suspended and not responding.has(int(active.get("stackId", -1)))
	if wipe_mode:
		var shown := not suspended and not responding.has(int(active.get("stackId", -1)))
		if shown != wipe_card.visible: _set_wipe_visible(shown)
		if shown:
			_layout_wipe()
			_count_wipe()
			queue_redraw()
	if suspended:
		_clear_hover()
