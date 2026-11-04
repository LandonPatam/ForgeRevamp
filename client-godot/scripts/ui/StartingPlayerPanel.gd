extends PanelContainer
signal player_selected(id: int)
const P = preload("res://scripts/ui/Palette.gd")
const Avatar = preload("res://scripts/ui/PlayerAvatar.gd")
var buttons: Array[Button] = []
var portraits: Array[Control] = []
var hovered := -1
var submissions_enabled := false
var description: Label
var row: HBoxContainer
var players: Array = []
var hover_tweens: Dictionary = {}

static func needs_selection(state: Dictionary) -> bool:
	var prompt: Dictionary = state.get("prompt", {})
	# Forge uses a one-player entity selection before turn one to choose who starts.
	return not state.is_empty() and state.get("asks", []).is_empty() and int(state.get("game", {}).get("turn", -1)) == 0 and prompt.get("inputKind", "") == "InputSelectEntitiesFromList" and prompt.get("cards", []).is_empty() and int(prompt.get("selMin", 0)) == 1 and int(prompt.get("selMax", 0)) == 1

func _ready() -> void:
	P.style_popup(self, 26)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	add_child(column)
	var heading := Label.new()
	heading.text = "Who starts?"
	heading.add_theme_font_size_override("font_size", 32)
	column.add_child(heading)
	description = Label.new()
	description.custom_minimum_size.x = 500
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 16)
	description.add_theme_color_override("font_color", Color("6d9fa3"))
	column.add_child(description)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)

func present(state: Dictionary) -> void:
	submissions_enabled = state.get("connectionReady", false)
	description.text = str(state.prompt.get("message", "Click a portrait to choose the starting player."))
	var values: Array = state.players
	if players != values:
		players = values.duplicate(true)
		for tween in hover_tweens.values():
			tween.kill()
		hover_tweens.clear()
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
		buttons.clear()
		portraits.clear()
		hovered = -1
		for player in players:
			var button := Button.new()
			button.custom_minimum_size = Vector2(160, 180)
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.tooltip_text = "Choose " + str(player.name) + " to start"
			var normal := P.box(Color("0a1e22"), Color("32676c"), 2, 12)
			var highlight := P.box(Color("1b2032"), Color("bd9bf2"), 2, 12)
			highlight.shadow_color = Color(0.74, 0.61, 0.95, 0.16)
			highlight.shadow_size = 10
			highlight.shadow_offset = Vector2.ZERO
			button.add_theme_stylebox_override("normal", normal)
			button.add_theme_stylebox_override("disabled", normal)
			for key in ["hover", "pressed", "focus"]:
				button.add_theme_stylebox_override(key, highlight)
			row.add_child(button)
			var column := VBoxContainer.new()
			column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			column.offset_left = 12
			column.offset_right = -12
			column.offset_top = 16
			column.offset_bottom = -12
			column.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(column)
			var portrait := Avatar.new()
			portrait.portrait_only = true
			portrait.custom_minimum_size = Vector2(136, 100)
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(portrait)
			portrait.set_player(player, false)
			portrait.tooltip_text = ""
			var name_label := Label.new()
			name_label.text = player.name
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.add_theme_font_size_override("font_size", 16)
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			column.add_child(name_label)
			var index := buttons.size()
			button.mouse_entered.connect(_hover.bind(index, true))
			button.mouse_exited.connect(_hover.bind(index, false))
			button.focus_entered.connect(_hover.bind(index, true))
			button.focus_exited.connect(_hover.bind(index, false))
			button.pressed.connect(_choose.bind(int(player.id)))
			buttons.append(button)
			portraits.append(portrait)
	for button in buttons:
		button.disabled = not submissions_enabled

func _hover(index: int, active: bool) -> void:
	if not submissions_enabled:
		return
	if active: hovered = index
	elif hovered == index: hovered = -1
	if hover_tweens.has(index): hover_tweens[index].kill()
	var portrait: Control = portraits[index]
	portrait.pivot_offset = portrait.size * 0.5
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(portrait, "scale", Vector2.ONE * (1.06 if active else 1.0), 0.12)
	hover_tweens[index] = tween

func _choose(id: int) -> void:
	if not submissions_enabled:
		return
	submissions_enabled = false
	for button in buttons:
		button.disabled = true
	player_selected.emit(id)

