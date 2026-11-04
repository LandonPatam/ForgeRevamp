extends Control
## Multi-recipient callback decisions remain local until one final answer.
signal answered(id: int, value: Variant)
const P = preload("res://scripts/ui/Palette.gd")
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
var ask: Dictionary = {}
var chosen: Array[int] = []
var cards: Dictionary = {}
var player_views: Dictionary = {}
var submissions_enabled := false
var panel: PanelContainer
var rail_host: ScrollContainer
var title: Label
var hint: Label
var mine_button: Button
var confirm_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 82
	panel = PanelContainer.new()
	Terminal.panel(panel)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	title = Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	hint = Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	mine_button = _button(column, "Select my permanents", _select_mine)
	_button(column, "Clear selection", func(): chosen.clear(); _refresh())
	_button(column, "Choose none", func(): if submissions_enabled: answered.emit(ask.id, []))
	confirm_button = _button(column, "Confirm counters", _submit)
	Terminal.button(confirm_button, true)
	resized.connect(_layout)
	panel.minimum_size_changed.connect(_layout)
	visibility_changed.connect(func():
		panel.visible = visible
		if visible: _layout())
	hide()

func _button(column: Control, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	Terminal.button(button)
	button.pressed.connect(action)
	column.add_child(button)
	return button

func present(value: Dictionary, views: Dictionary, enabled: bool, avatars: Dictionary = {}) -> void:
	if int(ask.get("id", -1)) != int(value.id):
		if is_instance_valid(rail_host): rail_host.scroll_vertical = 0
		chosen.clear()
		for index in value.get("selected", []): chosen.append(int(index))
	ask = value
	cards = views
	player_views = avatars
	submissions_enabled = enabled
	title.text = ask.get("title", "Choose recipients")
	show()
	_refresh()
	_layout()

func select_entity(kind: String, id: int) -> void:
	if not visible or not submissions_enabled: return
	for index in range(ask.get("options", []).size()):
		if int(ask.options[index].get("cardId" if kind == "card" else "playerId", -1)) != id: continue
		if chosen.has(index): chosen.erase(index)
		elif chosen.size() < int(ask.get("max", 0)): chosen.append(index)
		_refresh()
		return

func _select_mine() -> void:
	if not submissions_enabled: return
	chosen.clear()
	for index in range(ask.get("options", []).size()):
		var option: Dictionary = ask.options[index]
		if option.has("cardId") and int(option.get("controllerId", -1)) == int(ask.get("localPlayerId", -2)) and chosen.size() < int(ask.get("max", 0)): chosen.append(index)
	_refresh()

func _submit() -> void:
	if submissions_enabled and not confirm_button.disabled: answered.emit(ask.id, chosen.duplicate())

func _refresh() -> void:
	hint.text = "Click highlighted permanents or player portraits.\n%d selected" % chosen.size()
	for button in panel.get_child(0).get_children():
		if button is Button: button.disabled = not submissions_enabled
	confirm_button.disabled = not submissions_enabled or chosen.is_empty() or chosen.size() < int(ask.get("min", 0)) or chosen.size() > int(ask.get("max", 0))
	queue_redraw()

func _layout() -> void:
	if panel == null: return
	if preload("res://scripts/ui/SidebarDecision.gd").dock(panel, rail_host, [title, hint], _layout): return
	panel.size = Vector2(266, 0)
	panel.position = Vector2(maxf(16, (size.x - 300 - panel.size.x) * 0.5), 20)

func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.get_parent() != self: panel.queue_free()

func _process(_delta: float) -> void:
	if visible: queue_redraw()

func _draw() -> void:
	if not visible: return
	for index in range(ask.get("options", []).size()):
		var option: Dictionary = ask.options[index]
		var view: Control = cards.get(int(option.cardId)) if option.has("cardId") else player_views.get(int(option.get("playerId", -1)))
		if not is_instance_valid(view) or not view.is_visible_in_tree(): continue
		var frame := P.box(Color.TRANSPARENT, Color("ffcf73") if chosen.has(index) else Color("80d9ff"), 8, 0)
		frame.set_border_width_all(4)
		draw_set_transform_matrix(get_global_transform().affine_inverse() * view.get_global_transform())
		draw_style_box(frame, Rect2(Vector2(-4, -4), view.size + Vector2(8, 8)))
	draw_set_transform_matrix(Transform2D.IDENTITY)
