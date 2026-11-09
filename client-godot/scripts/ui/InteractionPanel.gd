extends Control
## Board-side actions and legal-target outlines, independent of the stack rail.
signal action_requested(action: String)
signal entity_selected(action: String, id: int)
signal resolve_requested(stack_id: int)
signal review_requested
signal browse_requested
signal modes_answered(id: int, picks: Array)
signal card_chosen(card_id: int)
signal target_player_clicked(seat: int)
signal targets_confirmed
signal targets_cancelled
const P = preload("res://scripts/ui/Palette.gd")
const Flow = preload("res://scripts/ui/InteractionFlow.gd")
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
var panel: PanelContainer
var rail_host: ScrollContainer
var heading: Label
var message: Label
var help: Label
var choices: HFlowContainer
var confirm_button: Button
var cancel_button: Button
var review_button: Button
var browse_button: Button
var source_view: Control
var source_frame: MarginContainer
var cards: Dictionary = {}
var player_views: Dictionary = {}
var state: Dictionary = {}
var description: Dictionary = {}
var suspended := true
var decision_key := ""
## Yes/no confirmations about a visible card attach to it instead of the top banner.
var callout: PanelContainer
var callout_card: Control
## A card's modes ("choose one or more —") also attach to that card when it is on the table.
var mode_ask: Dictionary = {}
## A tether with nothing on the table to hang from (a scry from a resolving spell): centered, no line.
var floating := false
## Targets of an effect from a permanent (or a card in your zones) tether to it; Main stages the
## picks in `target_staged` ({kind, id, name}) and sends them on Confirm.
var target_tether := false
var target_staged: Array = []
## Main supplies your zone icon holding a card id (graveyard, exile...), so a decision about a card
## that already left the table tethers to where it is: func(id: int) -> Control (or null).
var zone_view: Callable
const CALLOUT_GAP := 34.0
const RAIL_WIDTH := 316.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80
	panel = PanelContainer.new()
	Terminal.panel(panel)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	heading = _label(18, Terminal.INK)
	column.add_child(heading)
	message = _label(14, Terminal.INK)
	message.max_lines_visible = 4
	column.add_child(message)
	help = _label(12, Terminal.MUTED)
	column.add_child(help)
	source_view = preload("res://scripts/ui/CardView.gd").new()
	source_view.inspection = true
	source_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_view.custom_minimum_size = Vector2(200, 280)
	source_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	source_frame = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		source_frame.add_theme_constant_override("margin_" + side, 8)
	source_frame.add_child(source_view)
	column.add_child(source_frame)
	source_frame.hide()
	source_view.hide()
	choices = HFlowContainer.new()
	column.add_child(choices)
	var actions := HFlowContainer.new()
	column.add_child(actions)
	review_button = _button("Review effect", func(): review_requested.emit())
	actions.add_child(review_button)
	browse_button = _button("Browse targets", func(): browse_requested.emit())
	actions.add_child(browse_button)
	cancel_button = _button("Cancel", func(): action_requested.emit("cancel"))
	actions.add_child(cancel_button)
	confirm_button = _button("Confirm", _confirm)
	Terminal.button(confirm_button, true)
	actions.add_child(confirm_button)
	resized.connect(_layout)
	panel.minimum_size_changed.connect(_layout)
	panel.hide()
	callout = preload("res://scripts/ui/CardCallout.gd").new()
	callout.answered.connect(func(action): action_requested.emit(action))
	callout.modes_answered.connect(func(id, picks): modes_answered.emit(id, picks))
	callout.ask_answered.connect(func(id, value): modes_answered.emit(id, value))
	callout.card_chosen.connect(func(card_id): card_chosen.emit(card_id))
	callout.target_player_clicked.connect(func(seat): target_player_clicked.emit(seat))
	callout.targets_confirmed.connect(func(): targets_confirmed.emit())
	callout.targets_cancelled.connect(func(): targets_cancelled.emit())
	add_child(callout)

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_font_override("font", Terminal.font())
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	Terminal.button(button)
	button.pressed.connect(callback)
	return button

func present(value: Dictionary, blocked: bool, board_cards: Dictionary = {}, avatars: Dictionary = {}) -> void:
	var prompt_key := str(value.get("prompt", {}).get("inputKind", "")) + ":" + str(value.get("prompt", {}).get("message", ""))
	if decision_key != prompt_key and is_instance_valid(rail_host): rail_host.scroll_vertical = 0
	decision_key = prompt_key
	state = value
	cards = board_cards
	player_views = avatars
	suspended = blocked
	description = Flow.describe(state)
	floating = false
	if mode_ask.get("kind", "") == "scry":
		# Scry always takes the tether: off its source card or that card's zone, else centered.
		panel.hide()
		callout_card = _anchor_for(int(mode_ask.get("sourceCard", {}).get("id", -1)))
		floating = callout_card == null
		callout.visible = true
		callout.present_scry(mode_ask, state.get("connectionReady", false))
		_place_callout()
		queue_redraw()
		return
	var mode_view := _mode_view()
	if mode_view != null:
		panel.hide()
		callout_card = mode_view
		callout.visible = true
		if mode_ask.get("kind", "") == "message":
			callout.present_cards(str(mode_ask.get("message", "Looking at cards")), mode_ask.options.map(func(option): return option.card), false, state.get("connectionReady", false), int(mode_ask.id))
		else: callout.present_modes(str(mode_ask.get("sourceCard", mode_ask.options[0].get("card", {})).get("name", "Card")), mode_ask, state.get("connectionReady", false))
		_place_callout()
		queue_redraw()
		return
	var target_anchor := _target_anchor()
	target_tether = target_anchor != null
	if target_tether:
		panel.hide()
		callout_card = target_anchor
		callout.visible = true
		var target_prompt: Dictionary = state.prompt
		var target_ready: bool = state.get("connectionReady", false) and state.get("asks", []).is_empty() and state.get("pendingDraws", []).is_empty()
		var players: Array = []
		for entity in target_prompt.get("entities", []):
			if entity.get("kind", "") == "player": players.append({"seat": int(entity.get("id", -1)), "name": str(entity.get("name", "Player"))})
		callout.present_targets(str(target_prompt.sourceCard.get("name", "Card")), _target_question(target_prompt), players, target_staged, int(target_prompt.get("selMin", 1)), int(target_prompt.get("selMax", 1)), target_ready, target_prompt.get("cancelEnabled", false))
		_place_callout()
		queue_redraw()
		return
	var pick_view := _pick_view()
	if pick_view != null:
		panel.hide()
		callout_card = pick_view
		callout.visible = true
		var pick_prompt: Dictionary = state.prompt
		var pick_ready: bool = state.get("connectionReady", false) and state.get("asks", []).is_empty() and state.get("pendingDraws", []).is_empty()
		callout.present_cards(_pick_question(pick_prompt), pick_prompt.get("cards", []), true, pick_ready, -1, _pick_verb(pick_prompt))
		_place_callout()
		queue_redraw()
		return
	panel.visible = not suspended and not description.is_empty()
	callout_card = _callout_card() if panel.visible else null
	callout.visible = callout_card != null
	if callout.visible:
		panel.hide()
		var ask: Dictionary = state.prompt
		var ready_now: bool = state.get("connectionReady", false) and state.get("asks", []).is_empty() and state.get("pendingDraws", []).is_empty()
		var source: Dictionary = ask.get("sourceCard", {})
		var in_zone: bool = callout_card != cards.get(int(source.get("id", -1)))
		var question := str(ask.get("message", ""))
		var ok_label := str(ask.get("okLabel", "Yes"))
		var cancel_label := str(ask.get("cancelLabel", "No"))
		# Forge words the commander choice as its rule text; ask it plainly.
		if source.get("commander", false) and question.to_lower().contains("command zone"):
			var where := str(callout_card.get("kind")).to_lower() if in_zone and callout_card.get("kind") != null else "its zone"
			question = "Move %s to the command zone?" % str(source.get("name", "your commander"))
			ok_label = "Command zone"
			cancel_label = ("Leave in " + where) if in_zone else "Let it leave"
		callout.present(str(source.get("name", "Card")), question, ok_label, cancel_label, ready_now and ask.get("okEnabled", false), ready_now and ask.get("cancelEnabled", false), source if in_zone else {})
		_place_callout()
	if not panel.visible:
		queue_redraw()
		return
	var prompt: Dictionary = state.prompt
	var response: bool = description.kind == "response"
	var ready: bool = state.get("connectionReady", false) and state.get("asks", []).is_empty() and state.get("pendingDraws", []).is_empty()
	heading.text = description.title
	message.text = state.stack[0].get("text", "") if response else prompt.get("message", "")
	if prompt.get("inputKind", "") == "InputSelectCardsForConvokeOrImprovise": message.text = _helper_payment_text(prompt)
	help.text = description.help
	help.visible = not help.text.is_empty()
	source_view.visible = not prompt.get("sourceCard", {}).is_empty()
	source_frame.visible = source_view.visible
	if source_view.visible: source_view.update_card(prompt.sourceCard)
	confirm_button.text = description.confirm
	confirm_button.disabled = not ready or not prompt.get("okEnabled", false)
	cancel_button.text = prompt.get("cancelLabel", "Cancel")
	match prompt.get("selectionShortcut", ""):
		"MINE": cancel_button.text = "Select my permanents"
		"ALL": cancel_button.text = "Select all eligible"
		"NONE": cancel_button.text = "Clear selection"
	if not prompt.has("selectionShortcut") and prompt.get("inputKind", "") in ["InputSelectCardsFromList", "InputSelectEntitiesFromList"]:
		cancel_button.text = "Choose none"
	cancel_button.visible = not response and prompt.get("cancelEnabled", false)
	cancel_button.disabled = not ready
	review_button.visible = response
	review_button.disabled = not ready
	browse_button.visible = description.kind == "InputSelectTargets" and not prompt.get("cards", []).is_empty()
	browse_button.disabled = not ready
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()
	if not response:
		for entity in prompt.get("entities", []):
			if entity.get("kind", "") != "player": continue
			var button := _button(entity.get("name", "Player"), func(): entity_selected.emit("player", int(entity.id)))
			button.disabled = not ready
			choices.add_child(button)
	choices.visible = choices.get_child_count() > 0
	if prompt.has("selectionShortcut") or description.get("kind", "") in ["InputAttack", "InputBlock"]:
		choices.hide()
		help.text += "\n%d selected" % prompt.get("chosen", []).size()
	_layout()
	queue_redraw()

func _confirm() -> void:
	if confirm_button.disabled: return
	if description.get("kind", "") == "response": resolve_requested.emit(int(state.stack[0].id))
	else: action_requested.emit("ok")

## Forge's improvise/convoke text repeats the card and shows the cost before floating mana is
## spent; say what is actually still owed and what clicking does.
func _helper_payment_text(prompt: Dictionary) -> String:
	var raw := str(prompt.get("message", ""))
	var found := RegEx.create_from_string("Remaining mana cost is (\\{[^\\n]*\\})").search(raw)
	if found == null: return raw
	var pool: Dictionary = state.get("players", [{}])[0].get("mana", {})
	var owed: String = preload("res://scripts/ui/ManaPips.gd").remaining_after_pool(found.get_string(1), pool)
	var spell := str(prompt.get("sourceCard", {}).get("name", raw.get_slice("\n", 0).get_slice(" (", 0)))
	var helper := "creature" if raw.to_lower().contains("convoke") else "artifact"
	var keyword := "convoke" if helper == "creature" else "improvise"
	var floating := 0
	for amount in pool.values(): floating += int(amount)
	if owed == "{0}": return "%s is paid by your floating mana. Confirm to cast it." % spell
	return "%s still needs %s%s.\nTap an outlined %s to pay {1} with %s, or Confirm to pay the rest with mana." % [spell, owed, " after your %d floating mana" % floating if floating > 0 else "", helper, keyword]

## Choosing cards on the board must never cover the cards being chosen.
func _picks_from_board() -> bool:
	var kind: String = state.get("prompt", {}).get("inputKind", "")
	return kind.begins_with("InputSelect") or kind.begins_with("InputPayMana")

## The card id a mode ask chooses for: every option is a mode of one card, not a card itself.
static func mode_source(ask: Dictionary) -> int:
	var options: Array = ask.get("options", [])
	if ask.get("kind", "") != "choose" or options.size() < 2: return -1
	# A card's abilities or mana colors (Canopy Vista: green or white) tether to that card too.
	if ask.get("abilityChoice", false) and not ask.get("sourceCard", {}).is_empty() and not ask.sourceCard.get("hidden", false) and options.all(func(option): return not option.has("card")):
		return int(ask.sourceCard.get("id", -1))
	for option in options:
		if not option.has("card") or option.has("cardId") or option.has("stackId") or not option.card.has("id"): return -1
		if int(option.card.id) != int(options[0].card.id) or str(option.get("label", "")) == str(option.card.get("name", "")): return -1
	return -1 if options[0].card.get("hidden", false) else int(options[0].card.id)

## A look or reveal ("Looking at cards in your library") whose source card is on the table.
static func look_source(ask: Dictionary) -> int:
	var options: Array = ask.get("options", [])
	if ask.get("kind", "") != "message" or options.is_empty() or not options.all(func(option): return option.has("card")): return -1
	var source: Dictionary = ask.get("sourceCard", {})
	return -1 if source.is_empty() or source.get("hidden", false) else int(source.get("id", -1))

## A required one-card pick made by a card's own effect among cards on the table (Izzet Boilerworks:
## return a land): the source card's id, so the choice tethers to it instead of opening the
## card-search window. Picks among revealed or library cards keep that window (it also shows the
## cards you may not take).
static func pick_source(value: Dictionary, board_cards: Dictionary = {}) -> int:
	var prompt: Dictionary = value.get("prompt", {})
	if prompt.get("inputKind", "") not in ["InputSelectCardsFromList", "InputSelectEntitiesFromList"]: return -1
	if int(prompt.get("selMin", 0)) != 1 or int(prompt.get("selMax", 0)) != 1 or not value.get("asks", []).is_empty(): return -1
	var cards: Array = prompt.get("cards", [])
	if cards.is_empty() or cards.size() > 8 or not prompt.get("entities", []).is_empty() or prompt.has("selectionShortcut"): return -1
	if cards.any(func(card): return card.get("hidden", false)): return -1
	var source: Dictionary = prompt.get("sourceCard", {})
	if source.is_empty() or cards.any(func(card): return int(card.get("id", -1)) == -1): return -1
	for card in cards:
		var view: Control = board_cards.get(int(card.id))
		if not is_instance_valid(view) or not view.is_visible_in_tree() or str(view.data.get("zone", "")) != "Battlefield": return -1
	return int(source.get("id", -1))

func _pick_view() -> Control:
	var view: Control = cards.get(pick_source(state, cards))
	return view if is_instance_valid(view) and view.is_visible_in_tree() else null

## The effect line of Forge's prompt ("Return a land you control to its owner's hand."), else its last line.
static func _pick_question(prompt: Dictionary) -> String:
	var lines: Array = Array(str(prompt.get("message", "")).split("\n")).map(func(line): return RegEx.create_from_string(" \\(\\d+\\)").sub(str(line), "", true).strip_edges()).filter(func(line): return not line.is_empty())
	for line in lines:
		if line.begins_with("- "): return line.trim_prefix("- ")
	return lines.back() if not lines.is_empty() else "choose a card"

static func _pick_verb(prompt: Dictionary) -> String:
	var question := _pick_question(prompt).to_lower()
	for verb in ["return", "sacrifice", "exile", "destroy", "discard", "tap", "untap"]:
		if question.begins_with(verb): return verb.capitalize()
	return "Choose"

## Main hands over a mode ask (or {} to drop it) when its card is on the table.
func show_modes(ask: Dictionary) -> void:
	if ask == mode_ask: return
	mode_ask = ask
	present(state, suspended, cards, player_views)

## Choosing targets for an effect whose source is a permanent on the table or a card in one of
## your zones (a trigger or ability). Targets for a spell being cast from hand keep the rail.
func _target_anchor() -> Control:
	var prompt: Dictionary = state.get("prompt", {})
	if prompt.get("inputKind", "") != "InputSelectTargets" or not state.get("asks", []).is_empty(): return null
	var source: Dictionary = prompt.get("sourceCard", {})
	if source.is_empty() or source.get("hidden", false): return null
	var view: Control = cards.get(int(source.get("id", -1)))
	if is_instance_valid(view) and view.is_visible_in_tree() and str(view.data.get("zone", "")) == "Battlefield": return view
	if zone_view.is_valid():
		var zone: Control = zone_view.call(int(source.get("id", -1)))
		if is_instance_valid(zone) and zone.is_visible_in_tree(): return zone
	return null

## The effect in the card's words, then Forge's instruction: "...deals damage to that player.
## select target opponent". Engine ids, the "Name - " prefix and [bookkeeping] are dropped.
static func _target_question(prompt: Dictionary) -> String:
	var lines: Array = Array(str(prompt.get("message", "")).split("\n")).map(func(line): return str(line).strip_edges()).filter(func(line): return not line.is_empty())
	if lines.is_empty(): return "choose a target"
	var ids := RegEx.create_from_string(" \\(\\d+\\)")
	var bookkeeping := RegEx.create_from_string("\\s*\\[[^\\]]*\\]\\s*$")
	var effect: String = bookkeeping.sub(ids.sub(str(lines[0]), "", true), "").strip_edges()
	var card_name := str(prompt.get("sourceCard", {}).get("name", ""))
	if not card_name.is_empty() and effect.begins_with(card_name + " - "): effect = effect.substr(card_name.length() + 3)
	var instruction: String = ids.sub(str(lines.back()), "", true)
	return effect if lines.size() == 1 else effect + "\n" + instruction

## Main's staged picks changed: redraw the box and its lines.
func set_target_staged(value: Array) -> void:
	target_staged = value.duplicate(true)
	present(state, suspended, cards, player_views)

## The table card with this id, else your zone icon holding it, else null.
func _anchor_for(id: int) -> Control:
	var view: Control = cards.get(id)
	if is_instance_valid(view) and view.is_visible_in_tree(): return view
	if zone_view.is_valid():
		var zone: Control = zone_view.call(id)
		if is_instance_valid(zone) and zone.is_visible_in_tree(): return zone
	return null

func _mode_view() -> Control:
	if mode_ask.is_empty(): return null
	var source := mode_source(mode_ask)
	if source < 0: source = look_source(mode_ask)
	var view: Control = cards.get(source)
	return view if is_instance_valid(view) and view.is_visible_in_tree() else null

## The table card a plain yes/no confirmation is about, when it is on screen.
func _callout_card() -> Control:
	var prompt: Dictionary = state.get("prompt", {})
	if description.get("kind", "") != "InputConfirm" or prompt.get("sourceCard", {}).is_empty() or prompt.get("sourceCard", {}).get("hidden", false): return null
	var view: Control = cards.get(int(prompt.sourceCard.get("id", -1)))
	if is_instance_valid(view) and view.is_visible_in_tree(): return view
	if zone_view.is_valid():
		var zone: Control = zone_view.call(int(prompt.sourceCard.get("id", -1)))
		if is_instance_valid(zone) and zone.is_visible_in_tree(): return zone
	return null

func _card_rect(view: Control) -> Rect2:
	var to_local: Transform2D = get_global_transform().affine_inverse() * view.get_global_transform()
	var bounds := Rect2(to_local * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(view.size.x, 0), view.size, Vector2(0, view.size.y)]: bounds = bounds.expand(to_local * corner)
	return bounds

## Beside the card (right, else left, else below), clear of the rail and kept on screen.
func _place_callout() -> void:
	if floating:
		callout.reset_size()
		var room := Vector2(size.x - RAIL_WIDTH, size.y)
		callout.position = ((room - callout.size) * 0.5).max(Vector2(8, 8)).round()
		return
	if not is_instance_valid(callout_card): return
	callout.reset_size()
	var box: Vector2 = callout.size
	var card := _card_rect(callout_card)
	var right_limit := size.x - RAIL_WIDTH
	var at := Vector2(card.end.x + CALLOUT_GAP, card.get_center().y - box.y * 0.5)
	if at.x + box.x > right_limit:
		at.x = card.position.x - CALLOUT_GAP - box.x
		if at.x < 8:
			at = Vector2(card.get_center().x - box.x * 0.5, card.end.y + CALLOUT_GAP)
			if at.y + box.y > size.y - 8: at.y = card.position.y - CALLOUT_GAP - box.y
	at.x = clampf(at.x, 8, maxf(8, right_limit - box.x))
	at.y = clampf(at.y, 8, maxf(8, size.y - box.y - 8))
	callout.position = at.round()

func uses_stack_rail() -> bool:
	return panel != null and panel.visible and (state.get("prompt", {}).has("selectionShortcut") or state.get("prompt", {}).get("inputKind", "") in ["InputAttack", "InputBlock"] or _picks_from_board())

## Spells on the stack can be the targets, so they stay in the rail beside the decision.
func keeps_stack_visible() -> bool:
	return uses_stack_rail() and _picks_from_board() and not state.get("prompt", {}).has("selectionShortcut") and not state.get("stack", []).is_empty()

## Docked, the card follows the actions and shrinks, so Confirm stays in view without scrolling.
func _place_source(docked: bool) -> void:
	var index: int = source_frame.get_parent().get_child_count() - 1 if docked else 3
	if source_frame.get_index() != index: source_frame.get_parent().move_child(source_frame, index)
	source_view.custom_minimum_size = Vector2(160, 224) if docked else Vector2(200, 280)

func _layout() -> void:
	if panel == null: return
	if uses_stack_rail():
		message.max_lines_visible = -1
		_place_source(true)
		if preload("res://scripts/ui/SidebarDecision.gd").dock(panel, rail_host, [message, heading, help], _layout): return
		message.custom_minimum_size.x = 238
		heading.custom_minimum_size.x = 238
		panel.size = Vector2(266, 0)
		panel.position = Vector2(maxf(16, (size.x - 300 - panel.size.x) * 0.5), 20)
		return
	_place_source(false)
	if panel.get_parent() != self: panel.reparent(self, false)
	message.max_lines_visible = -1
	var width := minf(660, maxf(440, size.x - 580))
	message.custom_minimum_size.x = width - 28
	heading.custom_minimum_size.x = width - 28
	panel.size = Vector2(width, 0)
	panel.position = Vector2(maxf(110, (size.x - 300 - width) * 0.5), 20)

func _process(_delta: float) -> void:
	if callout.visible and floating:
		_place_callout()
	elif callout.visible:
		if not is_instance_valid(callout_card) or not callout_card.is_visible_in_tree():
			present(state, suspended, cards, player_views)
		else:
			_place_callout()
		queue_redraw()
	if panel.visible: queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not callout.visible or not event is InputEventKey or not event.pressed or event.echo: return
	if callout.card_mode and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		callout._focus_card(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()
		return
	if not callout.mode_ask.is_empty() and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		callout._toggle_mode(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_Y and not callout.yes_button.disabled:
		callout.yes_button.pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_N and callout.no_button.visible and not callout.no_button.disabled:
		callout.no_button.pressed.emit()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.get_parent() != self: panel.queue_free()

func _draw() -> void:
	if callout.visible and is_instance_valid(callout_card): _draw_callout_link()
	if callout.visible: _draw_pick_branch()
	if callout.visible and target_tether: _draw_target_lines()
	if suspended or description.is_empty() or not str(description.get("kind", "")).begins_with("InputSelect"): return
	var offered: Array = state.get("prompt", {}).get("cards", [])
	var chosen: Array = state.get("prompt", {}).get("chosen", [])
	for card in offered:
		var view: Control = cards.get(int(card.id))
		if not is_instance_valid(view) or not view.is_visible_in_tree(): continue
		var color := Color("ffcf73") if chosen.has("card:" + str(card.id)) else Color("80d9ff")
		var frame := P.box(Color.TRANSPARENT, color, 8, 0)
		frame.set_border_width_all(3)
		draw_set_transform_matrix(get_global_transform().affine_inverse() * view.get_global_transform())
		draw_style_box(frame, Rect2(Vector2(-3, -3), view.size + Vector2(6, 6)))
	for entity in state.get("prompt", {}).get("entities", []):
		if entity.get("kind", "") != "player": continue
		var avatar: Control = player_views.get(int(entity.id))
		if not is_instance_valid(avatar): continue
		var frame := P.box(Color.TRANSPARENT, Color("ffcf73") if chosen.has("player:" + str(int(entity.get("engineId", entity.id)))) else Color("80d9ff"), 8, 0)
		frame.set_border_width_all(3)
		draw_set_transform_matrix(get_global_transform().affine_inverse() * avatar.get_global_transform())
		draw_style_box(frame, Rect2(Vector2(-3, -3), avatar.size + Vector2(6, 6)))
	draw_set_transform_matrix(Transform2D.IDENTITY)

## A purple line from the tether to each staged target (card or portrait), with a frame on it.
func _draw_target_lines() -> void:
	var to_local := get_global_transform().affine_inverse()
	var box := Rect2(callout.position, callout.size)
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	for ref in target_staged:
		var view: Control = cards.get(int(ref.id)) if ref.kind == "card" else player_views.get(int(ref.id))
		if not is_instance_valid(view) or not view.is_visible_in_tree(): continue
		var view_transform: Transform2D = to_local * view.get_global_transform()
		var target: Vector2 = view_transform * (view.size * 0.5)
		var start := Vector2(clampf(target.x, box.position.x, box.end.x), clampf(target.y, box.position.y, box.end.y))
		if box.has_point(target): continue
		draw_line(start, target, Color(Terminal.ACCENT, 0.3), 12.0, true)
		draw_line(start, target, Terminal.ACCENT, 3.5, true)
		draw_circle(target, 6.0, Terminal.ACCENT)
		var frame := P.box(Color(Terminal.ACCENT, 0.1 * pulse), Color(Terminal.ACCENT, 0.4 + 0.6 * pulse), 8, 0)
		frame.set_border_width_all(3)
		draw_set_transform_matrix(view_transform)
		draw_style_box(frame, Rect2(Vector2.ZERO, view.size).grow(4))
		draw_set_transform_matrix(Transform2D.IDENTITY)

## A one-card pick: an orange branch from the tether to the highlighted choice on the table.
func _draw_pick_branch() -> void:
	var pick: Dictionary = callout.focused_pick()
	if pick.is_empty(): return
	var view: Control = cards.get(int(pick.get("id", -1)))
	if not is_instance_valid(view) or not view.is_visible_in_tree() or view == callout_card: return
	var to_local := get_global_transform().affine_inverse()
	var card_transform: Transform2D = to_local * view.get_global_transform()
	var target: Vector2 = card_transform * (view.size * 0.5)
	var box := Rect2(callout.position, callout.size)
	var start := Vector2(clampf(target.x, box.position.x, box.end.x), box.end.y if target.y > box.end.y else (box.position.y if target.y < box.position.y else box.get_center().y))
	var bend := start.lerp(target, 0.5) + Vector2(0, -0.12 * start.distance_to(target))
	var points := PackedVector2Array()
	for i in range(25):
		var t := i / 24.0
		points.append(start.lerp(bend, t).lerp(bend.lerp(target, t), t))
	var orange := Color("ffb978")
	draw_polyline(points, Color(orange, 0.28), 12.0, true)
	draw_polyline(points, orange, 3.5, true)
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	var frame := P.box(Color(orange, 0.1 * pulse), Color(orange, 0.4 + 0.6 * pulse), 8, 0)
	frame.set_border_width_all(3)
	draw_set_transform_matrix(card_transform)
	draw_style_box(frame, Rect2(Vector2.ZERO, view.size).grow(4))
	draw_set_transform_matrix(Transform2D.IDENTITY)

## A pulsing outline on the card and a leader line from its edge to the callout box.
func _draw_callout_link() -> void:
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	var glow := Color(Terminal.ACCENT, pulse)
	draw_set_transform_matrix(get_global_transform().affine_inverse() * callout_card.get_global_transform())
	var frame := P.box(Color.TRANSPARENT, glow, 9, 0)
	frame.set_border_width_all(3)
	draw_style_box(frame, Rect2(Vector2(-5, -5), callout_card.size + Vector2(10, 10)))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var card := _card_rect(callout_card).grow(5)
	var box := Rect2(callout.position, callout.size)
	var start: Vector2
	var finish: Vector2
	if box.position.x >= card.end.x:
		start = Vector2(card.end.x, card.get_center().y)
		finish = Vector2(box.position.x, clampf(start.y, box.position.y + 12, box.end.y - 12))
	elif box.end.x <= card.position.x:
		start = Vector2(card.position.x, card.get_center().y)
		finish = Vector2(box.end.x, clampf(start.y, box.position.y + 12, box.end.y - 12))
	elif box.position.y >= card.end.y:
		start = Vector2(card.get_center().x, card.end.y)
		finish = Vector2(clampf(start.x, box.position.x + 12, box.end.x - 12), box.position.y)
	else:
		start = Vector2(card.get_center().x, card.position.y)
		finish = Vector2(clampf(start.x, box.position.x + 12, box.end.x - 12), box.end.y)
	draw_line(start, finish, Terminal.ACCENT, 2.0, true)
	draw_circle(start, 4.0, Terminal.ACCENT)
	draw_rect(Rect2(finish - Vector2(3, 3), Vector2(6, 6)), Terminal.ACCENT)
