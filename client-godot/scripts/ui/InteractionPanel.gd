extends Control
## Board-side actions and legal-target outlines, independent of the stack rail.
signal action_requested(action: String)
signal entity_selected(action: String, id: int)
signal resolve_requested(stack_id: int)
signal review_requested
signal browse_requested
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
	panel.visible = not suspended and not description.is_empty()
	if not panel.visible:
		queue_redraw()
		return
	var prompt: Dictionary = state.prompt
	var response: bool = description.kind == "response"
	var ready: bool = state.get("connectionReady", false) and state.get("asks", []).is_empty() and state.get("pendingDraws", []).is_empty()
	heading.text = description.title
	message.text = state.stack[0].get("text", "") if response else prompt.get("message", "")
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

## Choosing cards on the board must never cover the cards being chosen.
func _picks_from_board() -> bool:
	var kind: String = state.get("prompt", {}).get("inputKind", "")
	return kind.begins_with("InputSelect") or kind.begins_with("InputPayMana")

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
	if panel.visible: queue_redraw()

func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.get_parent() != self: panel.queue_free()

func _draw() -> void:
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
