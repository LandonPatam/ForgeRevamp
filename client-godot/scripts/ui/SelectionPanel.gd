extends PanelContainer
## Forge's synchronous card input: each click goes directly to the active input.
signal selected_card(id: int)
signal entity_selected(action: String, id: int)
signal board_requested
signal action_requested(action: String)
const P = preload("res://scripts/ui/Palette.gd")
var pager: Control
var options_column: GridContainer
var preview: Control
var title: Label
var hint: Label
var confirm_button: Button
var none_button: Button
var cancel_button: Button
var board_button: Button
var options: Array = []
var option_buttons: Array[Button] = []
var source_view: Control
var source_context: HBoxContainer
var source_rules: Control
var body: HBoxContainer
var source_column: VBoxContainer

func _ready() -> void:
	P.style_popup(self, 24)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	title = Label.new()
	title.custom_minimum_size.x = 540
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	source_context = HBoxContainer.new()
	source_context.add_theme_constant_override("separation", 16)
	source_column = VBoxContainer.new()
	source_context.add_child(source_column)
	source_view = preload("res://scripts/ui/CardView.gd").new()
	source_view.inspection = true
	source_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_view.custom_minimum_size = Vector2(288, 404)
	source_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	source_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	source_column.add_child(source_view)
	source_rules = preload("res://scripts/ui/ReadableText.gd").new()
	source_column.add_child(source_rules)
	source_context.hide()
	body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	body.add_child(source_context)
	source_context.add_child(VSeparator.new())
	pager = preload("res://scripts/ui/PagedChoices.gd").new()
	body.add_child(pager)
	pager.configure(3, 3)
	options_column = pager.grid
	preview = preload("res://scripts/ui/CardView.gd").new()
	preview.inspection = true
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.custom_minimum_size = Vector2(300 * 144.0 / 202, 300)
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(preview)
	preview.hide()
	hint = Label.new()
	column.add_child(hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	none_button = Button.new()
	none_button.text = "Choose none"
	P.style_popup_button(none_button)
	none_button.pressed.connect(func(): action_requested.emit(none_button.get_meta("action", "ok")))
	buttons.add_child(none_button)
	confirm_button = Button.new()
	confirm_button.text = "Confirm selection"
	P.style_popup_button(confirm_button, true)
	confirm_button.pressed.connect(func(): action_requested.emit("ok"))
	buttons.add_child(confirm_button)
	cancel_button = Button.new()
	P.style_popup_button(cancel_button)
	cancel_button.pressed.connect(func(): action_requested.emit("cancel"))
	buttons.add_child(cancel_button)
	board_button = Button.new()
	board_button.text = "View battlefield"
	P.style_popup_button(board_button)
	board_button.pressed.connect(func(): board_requested.emit())
	buttons.add_child(board_button)

func present(snapshot: Dictionary) -> void:
	var prompt: Dictionary = snapshot.prompt
	var ready: bool = snapshot.get("connectionReady", false)
	title.text = prompt.get("message", "Choose cards")
	source_context.visible = not prompt.get("sourceCard", {}).is_empty()
	if source_context.visible:
		source_view.update_card(prompt.sourceCard)
		source_rules.hide()
	var cards: Array = prompt.get("cards", []).duplicate(true)
	for card in cards:
		card.kind = "card"
		card.eligible = true
		card.ref = "card:" + str(int(card.id))
	for revealed_card in prompt.get("revealedCards", []):
		if cards.any(func(card): return int(card.id) == int(revealed_card.id)): continue
		var viewed_card: Dictionary = revealed_card.duplicate(true)
		viewed_card.kind = "card"
		viewed_card.ref = "card:" + str(int(viewed_card.id))
		viewed_card.eligible = false
		cards.append(viewed_card)
	for entity in prompt.get("entities", []):
		var entry: Dictionary = entity.duplicate(true)
		entry.ref = str(entry.kind) + ":" + str(int(entry.get("engineId", entry.id)))
		if entry.kind == "stack": entry.name = entry.get("sourceName", entry.get("card", {}).get("name", "Spell or ability"))
		cards.append(entry)
	var columns := mini(maxi(1, cards.size()), clampi(int((get_viewport().get_visible_rect().size.x - (400 if source_context.visible else 100)) / 320), 1, 4))
	pager.custom_minimum_size.x = columns * 308
	pager.configure(columns, columns)
	if cards != options:
		options = cards.duplicate(true)
		for child in options_column.get_children():
			options_column.remove_child(child)
			child.queue_free()
		option_buttons.clear()
		for card in options:
			var button := Button.new()
			button.text = card.get("name", "Face-down card")
			button.clip_text = true
			button.tooltip_text = button.text
			button.custom_minimum_size = Vector2(308, 456)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.pressed.connect(func():
				if card.kind == "card": selected_card.emit(int(card.id))
				else: entity_selected.emit(str(card.kind), int(card.id)))
			button.mouse_entered.connect(func():
				var data: Dictionary = card.get("card", card)
				if card.kind != "player" and not data.get("hidden", false): preview.update_card(data))
			options_column.add_child(button)
			var face = preload("res://scripts/ui/CardView.gd").new()
			face.inspection = true
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(face)
			face.position = Vector2(10, 8)
			face.size = Vector2(288, 404)
			if card.kind == "player":
				face.hide()
				var portrait := preload("res://scripts/ui/PlayerAvatar.gd").new()
				portrait.position = Vector2(18, 30)
				portrait.size = Vector2(144, 160)
				portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.add_child(portrait)
				if int(card.id) >= 0 and int(card.id) < snapshot.get("players", []).size(): portrait.set_player(snapshot.players[int(card.id)], false)
			else:
				face.update_card(card.get("card", card))
			if card.kind == "stack":
				button.text = card.name + "\n" + str(card.get("text", ""))
				button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				button.clip_text = false
				button.add_theme_font_size_override("font_size", 13)
				button.custom_minimum_size.y = 496
			for style_name in ["normal", "hover", "pressed", "disabled"]:
				var style := button.get_theme_stylebox(style_name).duplicate() as StyleBox
				style.content_margin_top = 420
				button.add_theme_stylebox_override(style_name, style)
			option_buttons.append(button)
		if not cards.is_empty() and cards[0].kind != "player":
			preview.update_card(cards[0].get("card", cards[0]))
	var refs: Array = options.map(func(option): return str(option.ref))
	var chosen: Array = prompt.get("chosen", []).filter(func(ref): return refs.has(str(ref)))
	for i in range(options.size()):
		var button := option_buttons[i]
		button.disabled = not ready or not options[i].get("eligible", true)
		var selected: bool = chosen.has(str(options[i].ref))
		button.text = ("✓ " if selected else "") + str(options[i].get("name", "Face-down card"))
		if not options[i].get("eligible", true): button.text = "Viewed only · " + button.text
		if options[i].kind == "stack": button.text += "\n" + str(options[i].get("text", ""))
		button.get_child(0).set_selected(selected)
		button.add_theme_stylebox_override("normal", P.box(Color("1b2032") if selected else Color("0a1e22"), Color("bd9bf2") if selected else Color("32676c"), 2, 12))
		button.get_theme_stylebox("normal").content_margin_top = 420
	hint.text = "%d selected" % chosen.size() if prompt.get("inputKind", "") == "InputSelectStackItems" else "%d selected / %d–%d required" % [chosen.size(), prompt.get("selMin", 0), prompt.get("selMax", 0)]
	confirm_button.disabled = not ready or not prompt.get("okEnabled", false) or chosen.is_empty()
	# Forge represents an optional 1-card effect as Cancel rather than a 0 minimum.
	var decline: bool = prompt.get("inputKind", "") in ["InputSelectCardsFromList", "InputSelectEntitiesFromList"] and prompt.get("cancelEnabled", false) and not prompt.has("selectionShortcut")
	none_button.set_meta("action", "cancel" if decline else "ok")
	none_button.visible = int(prompt.get("selMin", 0)) == 0 or decline
	none_button.disabled = not ready or (not decline and not prompt.get("okEnabled", false)) or not chosen.is_empty()
	cancel_button.text = prompt.get("cancelLabel", "Cancel")
	match prompt.get("selectionShortcut", ""):
		"MINE": cancel_button.text = "Select my permanents"
		"ALL": cancel_button.text = "Select all eligible"
		"NONE": cancel_button.text = "Clear selection"
	cancel_button.tooltip_text = "Change the selection, then review it before confirming." if prompt.has("selectionShortcut") else ""
	cancel_button.visible = prompt.get("cancelEnabled", false) and not decline
	cancel_button.disabled = not ready
	board_button.text = "Choose on board" if prompt.get("inputKind", "") == "InputSelectTargets" else "View battlefield"
	board_button.visible = true
	board_button.disabled = not ready
