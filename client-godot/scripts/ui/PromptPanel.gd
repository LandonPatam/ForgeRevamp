extends PanelContainer
signal answered(id: int, value: Variant)
signal board_requested
const P = preload("res://scripts/ui/Palette.gd")
const ManaOption = preload("res://scripts/ui/ManaOption.gd")
const AbilityOption = preload("res://scripts/ui/AbilityOption.gd")
var ask: Dictionary = {}
var chosen: Array[int] = []
var amounts: Array[int] = []
var spins: Array[SpinBox] = []
## Redraws each damage column after any amount changes (caps can lower other amounts).
var amount_refreshers: Array[Callable] = []
var option_buttons: Array[Button] = []
var confirm_button: Button
var hint: Label
var input: LineEdit
var submissions_enabled := true
var error_label: Label
var mine_button: Button
var source_view: Control
var order_preview: Label
var auto_button: Button
var gallery: Control
## Long plain lists such as creature types: searchable, compact rows, ten to a page.
const LIST_PAGE := 10
var list_menu := false
var search: LineEdit
var list_pager: VBoxContainer

func present(value: Dictionary) -> void:
	if int(ask.get("id", -1)) != int(value.get("id", -1)): submissions_enabled = true
	ask = _with_modes_as_text(value.duplicate(true))
	var options: Array = ask.get("options", [])
	var card_choices: bool = options.any(func(option): return option.has("card")) and ask.kind in ["choose", "order", "message"]
	var face_size := Vector2(288, 404)
	if get_viewport().get_visible_rect().size.y < 760: face_size *= 0.8
	order_preview = null
	auto_button = null
	var mana_menu: bool = ask.get("kind", "") == "choose" and not ask.get("options", []).is_empty() and ask.options.all(func(option): return not option.has("card") and not ManaOption.choice_details(str(option.get("label", ""))).is_empty())
	list_menu = ask.get("kind", "") == "choose" and not card_choices and not mana_menu and options.size() > LIST_PAGE and not ask.get("abilityChoice", false) and ask.get("title", "") != "Choose ability"
	chosen.clear()
	for index in ask.get("selected", []):
		if index is int or index is float:
			chosen.append(int(index))
	amounts.clear()
	spins.clear()
	amount_refreshers.clear()
	option_buttons.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	P.style_popup(self)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = ("FORGE DECISION  /  " if ask.get("mode", "") == "live" else "DEMO DECISION  /  ") + str(ask.kind).to_upper()
	eyebrow.add_theme_color_override("font_color", Color("6d9fa3"))
	eyebrow.add_theme_font_size_override("font_size", 12)
	column.add_child(eyebrow)
	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 440
	if mana_menu: title.custom_minimum_size.x = 560
	title.text = str(ask.get("title", "")).strip_edges()
	if mana_menu: title.text = "Choose mana to add to pool"
	if title.text.is_empty():
		title.text = ("Cards viewed" if card_choices else "Message") if ask.kind == "message" else "Your choice"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("a6dfdf"))
	column.add_child(title)
	var divider := HSeparator.new()
	divider.add_theme_stylebox_override("separator", P.box(Color("32676c"), Color.TRANSPARENT, 0, 0))
	divider.custom_minimum_size.y = 1
	column.add_child(divider)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	source_view = null
	var source_column: VBoxContainer
	if card_choices:
		source_column = VBoxContainer.new()
		body.add_child(source_column)
	if not ask.get("sourceCard", {}).is_empty():
		source_view = preload("res://scripts/ui/CardView.gd").new()
		source_view.inspection = true
		source_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		source_view.custom_minimum_size = face_size
		source_view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		if card_choices: source_column.add_child(source_view)
		else: body.add_child(source_view)
		source_view.update_card(ask.sourceCard)
	var list_column: VBoxContainer
	if list_menu:
		list_column = VBoxContainer.new()
		list_column.add_theme_constant_override("separation", 10)
		list_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		body.add_child(list_column)
		title.custom_minimum_size.x = 420
		title.reparent(list_column)
	var text := str(ask.get("message", "")).strip_edges()
	if source_view != null:
		var printed: String = ask.sourceCard.get("text", "")
		var effect: String = ask.get("effectText", "")
		if not effect.strip_edges().is_empty() and not printed.contains(effect): text += "\n\nEffect: " + effect
	var readable := preload("res://scripts/ui/ReadableText.gd").new()
	if card_choices:
		source_column.add_child(readable)
		readable.present(text, face_size.x, 70, 15)
		source_column.visible = source_view != null
		if source_view == null:
			readable.reparent(column)
			column.move_child(readable, body.get_index())
			readable.present(text, minf(900, maxf(480, options.size() * (face_size.x + 20))), 48, 15)
			readable.visible = not text.is_empty()
	elif list_menu:
		list_column.add_child(readable)
		readable.present(text, 420, 60, 15)
		readable.visible = not text.is_empty() and text != title.text
	else:
		body.add_child(readable)
		readable.present(text, 400 if source_view != null else 440, 202 if source_view != null else clampf(get_viewport().get_visible_rect().size.y * 0.16, 96, 220), 17)
	body.visible = card_choices or list_menu or source_view != null or not text.is_empty()
	hint = Label.new()
	hint.add_theme_color_override("font_color", Color("6d9fa3"))
	hint.add_theme_font_size_override("font_size", 12)
	hint.visible = ask.kind != "message"
	column.add_child(hint)
	error_label = Label.new()
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_color_override("font_color", Color("f2a18a"))
	error_label.hide()
	column.add_child(error_label)
	if ask.kind == "message" and options.any(func(option): return option.has("card")):
		options = options.filter(func(option): return option.has("card") or str(option.get("label", "")).replace(" ", "").to_lower() not in ["===main===", "===maindeck==="])
	var card_distribution: bool = ask.kind == "distribute" and options.any(func(option): return option.has("card"))
	gallery = VBoxContainer.new()
	if card_choices:
		body.add_child(gallery)
		if source_view != null:
			var divider_vertical := VSeparator.new()
			body.move_child(gallery, body.get_child_count() - 1)
			body.add_child(divider_vertical)
			body.move_child(divider_vertical, 1)
		var gallery_title := Label.new()
		gallery_title.text = "Resolution order · first → last" if ask.get("abilityOrder", false) else ("Cards viewed" if ask.kind == "message" else "Eligible cards · choose below")
		gallery.add_child(gallery_title)
	elif list_menu:
		search = LineEdit.new()
		search.placeholder_text = "Search…"
		search.custom_minimum_size.y = 36
		list_column.add_child(search)
		list_column.add_child(gallery)
	else: column.add_child(gallery)
	var pager := preload("res://scripts/ui/PagedChoices.gd").new()
	gallery.add_child(pager)
	list_pager = pager
	var reserved := face_size.x + 120 if card_choices and source_column.visible else 100.0
	var columns := clampi(int((get_viewport().get_visible_rect().size.x - reserved) / (face_size.x + 24)), 1, 4) if card_choices else 1
	if card_choices: columns = mini(columns, maxi(1, options.size()))
	if mana_menu: columns = mini(6, options.size())
	var rows := 1 if card_choices else (2 if card_distribution else 3)
	pager.configure(columns, columns * rows)
	if mana_menu: pager.configure(columns, columns)
	pager.custom_minimum_size.x = columns * (face_size.x + 20) if card_choices else (640 if card_distribution else 480)
	if mana_menu: pager.custom_minimum_size.x = columns * 140
	if list_menu:
		pager.configure(1, LIST_PAGE)
		pager.custom_minimum_size.x = 420
		pager.grid.add_theme_constant_override("v_separation", 4)
	pager.visible = not options.is_empty()
	var options_column: Container = pager.grid
	if mana_menu: options_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if ask.kind in ["choose", "order"]:
		for i in range(options.size()):
			var mana_colors := ManaOption.colors_for(str(options[i].get("label", "")))
			var is_ability: bool = (ask.get("abilityChoice", false) or ask.get("title", "") == "Choose ability") and not options[i].has("card")
			var button: Button = ManaOption.new() if mana_menu else (AbilityOption.new() if is_ability else (Button.new() if mana_colors.is_empty() else ManaOption.new()))
			if button is AbilityOption: button.description = options[i].get("label", "Option")
			if button is ManaOption: button.colors = mana_colors
			if mana_menu: button.choice_tile = true
			button.text = options[i].get("label", "Option")
			button.tooltip_text = button.text if ask.kind == "order" else options[i].get("card", {}).get("text", button.text)
			button.clip_text = false
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size.y = 43
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if not card_choices and not mana_menu: button.custom_minimum_size.x = 480
			if list_menu:
				button.custom_minimum_size = Vector2(420, 30)
				button.set_meta("search", str(options[i].get("label", "")).to_lower())
			button.pressed.connect(_toggle.bind(i))
			if mana_menu:
				var tile := VBoxContainer.new()
				tile.add_theme_constant_override("separation", 10)
				options_column.add_child(tile)
				tile.add_child(button)
				var details := ManaOption.choice_details(str(options[i].label))
				if not details.cost.is_empty():
					var cost := preload("res://scripts/ui/AbilityText.gd").new()
					cost.text = "Cost: " + str(details.cost)
					cost.font_size = 14
					cost.custom_minimum_size.x = 128
					tile.add_child(cost)
				if not details.extra.is_empty():
					var extra := Label.new()
					extra.text = details.extra
					extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					extra.custom_minimum_size.x = 128
					extra.add_theme_font_size_override("font_size", 14)
					tile.add_child(extra)
			else: options_column.add_child(button)
			option_buttons.append(button)
			if options[i].has("card"):
				var card = preload("res://scripts/ui/CardView.gd").new()
				card.inspection = true
				card.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.custom_minimum_size = face_size
				button.custom_minimum_size.x = face_size.x + 20
				var card_center := CenterContainer.new()
				card_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
				button.add_child(card_center)
				card_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				card_center.offset_top = 12
				card_center.offset_bottom = -36
				card_center.add_child(card)
				card.update_card(options[i].card)
				button.set_meta("card_preview", card)
				button.custom_minimum_size.y = face_size.y + 48
				if options[i].has("stackId"):
					button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					button.clip_text = false
					button.add_theme_font_size_override("font_size", 13)
				button.vertical_icon_alignment = VERTICAL_ALIGNMENT_BOTTOM
				button.add_theme_constant_override("text_outline_size", 0)
				for style_name in ["normal", "hover", "pressed", "disabled"]:
					var style := button.get_theme_stylebox(style_name).duplicate() as StyleBox
					style.content_margin_top = face_size.y + 18
					button.add_theme_stylebox_override(style_name, style)
		if list_menu:
			_order_list(options_column, options)
			search.text_changed.connect(func(text: String): list_pager.set_filter(text))
			search.text_submitted.connect(func(_text: String): _select_top_match())
			_focus_search.call_deferred()
	elif ask.kind == "distribute":
		# One column per recipient: big amount (marked Lethal when it kills) over its card.
		var lethal: Array = ask.get("lethal", [])
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", 18)
		strip.alignment = BoxContainer.ALIGNMENT_CENTER
		var scroller := ScrollContainer.new()
		scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroller.custom_minimum_size.y = 430 if card_distribution else 200
		scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroller.add_child(strip)
		options_column.add_child(scroller)
		for i in range(options.size()):
			var target := VBoxContainer.new()
			target.add_theme_constant_override("separation", 6)
			target.custom_minimum_size.x = 172
			var amount_label := Label.new()
			amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			amount_label.add_theme_font_size_override("font_size", 40)
			target.add_child(amount_label)
			var lethal_label := Label.new()
			lethal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lethal_label.add_theme_font_size_override("font_size", 15)
			lethal_label.add_theme_color_override("font_color", Color("f2a18a"))
			target.add_child(lethal_label)
			var spin := SpinBox.new()
			spin.min_value = 1 if ask.get("atLeastOne", false) else 0
			spin.max_value = ask.amount
			spin.step = 1
			spin.visible = false # The model behind the big number and its buttons.
			amounts.append(int(spin.min_value))
			spin.value = spin.min_value
			spins.append(spin)
			target.add_child(spin)
			var buttons := HBoxContainer.new()
			buttons.alignment = BoxContainer.ALIGNMENT_CENTER
			buttons.add_theme_constant_override("separation", 10)
			for delta in [-1, 1]:
				var step := Button.new()
				step.text = "−" if delta < 0 else "+"
				step.custom_minimum_size = Vector2(56, 40)
				step.add_theme_font_size_override("font_size", 22)
				step.focus_mode = Control.FOCUS_NONE
				step.add_theme_stylebox_override("normal", P.box(Color("0a1e22"), Color("32676c"), 6, 8))
				step.add_theme_stylebox_override("hover", P.box(Color("1b2032"), Color("bd9bf2"), 6, 8))
				step.add_theme_stylebox_override("pressed", P.box(Color("1b2032"), Color("bd9bf2"), 6, 8))
				step.add_theme_stylebox_override("disabled", P.box(Color("081416"), Color("1d3a3d"), 6, 8))
				step.pressed.connect(func(): spin.value = clampf(spin.value + delta, spin.min_value, spin.max_value))
				buttons.add_child(step)
			target.add_child(buttons)
			var threshold: int = int(lethal[i]) if i < lethal.size() else 0
			var show_amount := func():
				amount_label.text = str(amounts[i])
				lethal_label.text = "(Lethal)" if threshold > 0 and amounts[i] >= threshold else ("%d to kill" % threshold if threshold > 0 else " ")
			show_amount.call()
			spin.value_changed.connect(func(n: float):
				amounts[i] = int(n)
				_limit_distribution()
				_validate()
				for refresh in amount_refreshers: refresh.call())
			amount_refreshers.append(show_amount)
			if options[i].has("card"):
				var card = preload("res://scripts/ui/CardView.gd").new()
				card.inspection = true
				card.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.custom_minimum_size = Vector2(160, 224)
				card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				target.add_child(card)
				card.update_card(options[i].card)
			var label := Label.new()
			label.text = options[i].label
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = 160
			target.add_child(label)
			strip.add_child(target)
	elif ask.kind == "input":
		input = LineEdit.new()
		input.text = ask.get("initial", "")
		input.custom_minimum_size.y = 44
		input.placeholder_text = "Enter a number…" if ask.get("numeric", false) else "Enter your answer…"
		input.text_changed.connect(func(_s): _validate())
		input.text_submitted.connect(func(_s): _submit())
		input.gui_input.connect(func(event):
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_emit_answer(null))
		column.add_child(input)
		_focus_input.call_deferred()
	elif ask.kind == "message":
		for option in options:
			var group := VBoxContainer.new()
			options_column.add_child(group)
			if option.has("card"):
				var card = preload("res://scripts/ui/CardView.gd").new()
				card.inspection = true
				card.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.custom_minimum_size = face_size
				var center := CenterContainer.new()
				group.add_child(center)
				center.add_child(card)
				card.update_card(option.card)
			var label := Label.new()
			label.text = "" if option.has("card") else str(option.get("label", ""))
			label.visible = not label.text.is_empty()
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = 180 if card_choices else 440
			label.add_theme_font_size_override("font_size", 17)
			group.add_child(label)
	if card_choices and not ask.get("revealedCards", []).is_empty():
		var tabs := HBoxContainer.new()
		gallery.add_child(tabs)
		gallery.move_child(tabs, 1)
		var viewed := preload("res://scripts/ui/PagedChoices.gd").new()
		gallery.add_child(viewed)
		viewed.configure(columns, columns)
		viewed.custom_minimum_size.x = pager.custom_minimum_size.x
		for data in ask.revealedCards:
			var tile := VBoxContainer.new()
			viewed.grid.add_child(tile)
			var face = preload("res://scripts/ui/CardView.gd").new()
			face.inspection = true
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			face.custom_minimum_size = face_size
			tile.add_child(face)
			face.update_card(data)
			var eligibility := Label.new()
			eligibility.text = "Eligible" if options.any(func(option): return int(option.get("cardId", -1)) == int(data.get("id", -2))) else "Viewed only"
			tile.add_child(eligibility)
		viewed.hide()
		var eligible_button := Button.new()
		eligible_button.text = "Eligible cards (%d)" % options.size()
		P.style_popup_button(eligible_button)
		eligible_button.pressed.connect(func(): viewed.hide(); pager.show())
		tabs.add_child(eligible_button)
		var viewed_button := Button.new()
		viewed_button.text = "All viewed (%d)" % ask.revealedCards.size()
		P.style_popup_button(viewed_button)
		viewed_button.pressed.connect(func(): pager.hide(); viewed.show())
		tabs.add_child(viewed_button)
	if ask.kind == "order":
		order_preview = Label.new()
		order_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		order_preview.custom_minimum_size.x = 480
		column.add_child(order_preview)
	var buttons := HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_END
	column.add_child(buttons)
	var board := Button.new()
	board.text = "View battlefield"
	P.style_popup_button(board)
	board.pressed.connect(func(): board_requested.emit())
	buttons.add_child(board)
	if ask.kind == "order" and ask.get("autoOrder", false):
		auto_button = Button.new()
		auto_button.text = "Auto"
		auto_button.tooltip_text = "Use Forge's supplied order for the remaining cards or abilities."
		P.style_popup_button(auto_button)
		auto_button.pressed.connect(_auto_order)
		buttons.add_child(auto_button)
	mine_button = null
	if ask.kind in ["choose", "order"] and ask.get("bulkSelection", false) and ask.has("localPlayerId"):
		mine_button = Button.new()
		mine_button.text = "Select my permanents"
		mine_button.tooltip_text = "Select your eligible permanents. Review or change the selection before confirming."
		mine_button.pressed.connect(_select_mine)
		buttons.add_child(mine_button)
	if ask.kind in ["choose", "order"] and ask.get("min", 1) == 0 and not options.is_empty():
		var decline := Button.new()
		decline.text = "Cancel activation" if ask.get("manaChoice", false) else "Choose none"
		decline.pressed.connect(func(): _emit_answer([]))
		buttons.add_child(decline)
	if ask.kind == "input" or ask.get("maySkip", false):
		var cancel := Button.new()
		cancel.text = "Cancel" if ask.kind == "input" else "Skip"
		cancel.pressed.connect(func(): _emit_answer(null))
		buttons.add_child(cancel)
	if ask.kind in ["choose", "order"]:
		var clear := Button.new()
		clear.text = "Clear"
		clear.visible = not ask.get("manaChoice", false)
		clear.pressed.connect(func():
			chosen.clear()
			_validate())
		buttons.add_child(clear)
	confirm_button = Button.new()
	confirm_button.text = "Acknowledge" if ask.kind == "message" else "Confirm choice"
	confirm_button.visible = not ask.get("manaChoice", false)
	confirm_button.custom_minimum_size = Vector2(190, 46)
	P.style_popup_button(confirm_button, true)
	confirm_button.pressed.connect(_submit)
	buttons.add_child(confirm_button)
	_validate()
	reset_size()

## Modes of one card are choices of text, not of cards: show that card once beside its readable options.
func _with_modes_as_text(value: Dictionary) -> Dictionary:
	var options: Array = value.get("options", [])
	if value.get("kind", "") != "choose" or options.is_empty(): return value
	for option in options:
		if not option.has("card") or option.has("cardId") or option.has("stackId") or not option.card.has("id"): return value
		if int(option.card.id) != int(options[0].card.id) or str(option.get("label", "")) == str(option.card.get("name", "")): return value
	value.sourceCard = options[0].card
	value.abilityChoice = true
	for option in options: option.erase("card")
	return value

## Types on the table first, most common first; the rest keep Forge's order. Answers still use the original index.
func _order_list(grid: Container, options: Array) -> void:
	var order: Array = range(options.size())
	var rank := func(index: int) -> int: return int(options[index].get("tableCount", 0))
	order.sort_custom(func(a: int, b: int): return rank.call(a) > rank.call(b) or (rank.call(a) == rank.call(b) and a < b))
	for index in order: grid.move_child(option_buttons[index], -1)

## Enter picks the best match, leaving Confirm as the deliberate final step.
func _select_top_match() -> void:
	var found: Array = list_pager.matches()
	if found.is_empty() or not submissions_enabled: return
	var index := option_buttons.find(found[0])
	if index >= 0 and not chosen.has(index): _toggle(index)

func _auto_order() -> void:
	if not submissions_enabled: return
	# Same as Forge's DualListBox Auto: append all remaining items, then finish.
	for i in range(ask.get("options", []).size()):
		if not chosen.has(i): chosen.append(i)
	_validate()
	_submit()

func _toggle(index: int) -> void:
	if not submissions_enabled: return
	if chosen.has(index):
		chosen.erase(index)
	elif ask.max == 1:
		chosen.assign([index])
	elif chosen.size() < ask.max:
		chosen.append(index)
	_validate()
	if ask.get("manaChoice", false) and not chosen.is_empty(): _submit()

## Hard-caps the assigned total at ask.amount: each box may only reach what the others leave.
func _limit_distribution() -> void:
	var total := 0
	for n in amounts: total += n
	for i in range(spins.size()):
		var room: int = int(ask.amount) - (total - amounts[i])
		spins[i].max_value = maxi(int(spins[i].min_value), room)
		if amounts[i] > spins[i].max_value:
			total -= amounts[i] - int(spins[i].max_value)
			amounts[i] = int(spins[i].max_value)
			spins[i].set_value_no_signal(amounts[i])

func _select_mine() -> void:
	if not submissions_enabled or not ask.get("bulkSelection", false) or not ask.has("localPlayerId"): return
	chosen.clear()
	for index in range(ask.get("options", []).size()):
		var option: Dictionary = ask.options[index]
		if option.has("cardId") and int(option.get("controllerId", -1)) == int(ask.localPlayerId): chosen.append(index)
	_validate()

func _validate() -> void:
	if confirm_button == null:
		return
	var valid := true
	match ask.kind:
		"choose", "order":
			valid = chosen.size() >= ask.min and chosen.size() <= ask.max
			if ask.min == 0 and not ask.get("options", []).is_empty() and chosen.is_empty():
				valid = false # Choosing nothing is a deliberate separate action.
			hint.text = ("Select in order · " if ask.kind == "order" else "Choose · ") + str(chosen.size()) + " selected / " + str(ask.min) + "–" + str(ask.max)
			if ask.get("manaChoice", false): hint.text = "Select the mana to add."
			for i in range(option_buttons.size()):
				var selected := chosen.has(i)
				var prefix := str(chosen.find(i) + 1) + ".  " if selected and ask.kind == "order" else ("✓  " if selected else "")
				var mana_tile: bool = option_buttons[i] is ManaOption and option_buttons[i].choice_tile
				if not option_buttons[i] is AbilityOption and not mana_tile:
					option_buttons[i].text = ("%d →" % (chosen.find(i) + 1) if selected else "Choose next") if ask.kind == "order" and ask.options[i].has("card") else prefix + str(ask.options[i].label)
				if option_buttons[i].has_meta("card_preview"):
					option_buttons[i].get_meta("card_preview").set_selected(selected)
				var style := P.box(Color("1b2032") if selected else Color("0a1e22"), Color("bd9bf2") if selected else Color("32676c"), 2, 12)
				if ask.options[i].has("card"): style.content_margin_top = option_buttons[i].get_meta("card_preview").custom_minimum_size.y + 18
				if list_menu:
					style.content_margin_top = 4
					style.content_margin_bottom = 4
				if mana_tile: style.set_corner_radius_all(30)
				elif option_buttons[i] is ManaOption: style.content_margin_left = 16 + option_buttons[i].colors.size() * 48
				option_buttons[i].add_theme_stylebox_override("normal", style)
			if order_preview != null:
				var sequence: Array[String] = []
				for index in chosen: sequence.append("%d. %s" % [sequence.size() + 1, ask.options[index].get("card", {}).get("name", ask.options[index].label)])
				order_preview.text = " → ".join(sequence) if not sequence.is_empty() else "Click cards in the order they should resolve, or use Auto."
		"distribute":
			var total := 0
			for n in amounts:
				total += n
			valid = total == ask.amount
			hint.text = str(total) + " / " + str(int(ask.amount)) + " assigned"
		"input":
			valid = not ask.get("numeric", false) or input.text.is_valid_int()
			hint.text = "Enter a whole number." if ask.get("numeric", false) else "Enter your answer."
		"message":
			hint.text = "The engine can wait here until you acknowledge."
		_:
			valid = false
			hint.text = "Unsupported prompt kind: " + str(ask.kind)
	confirm_button.disabled = not valid or not submissions_enabled

func _submit() -> void:
	if confirm_button == null or confirm_button.disabled:
		return
	match ask.kind:
		"choose", "order": _emit_answer(chosen.duplicate())
		"distribute": _emit_answer(amounts.duplicate())
		"input": _emit_answer(input.text)
		"message": _emit_answer(true)

func cancel_input() -> void:
	if ask.get("kind", "") == "input":
		_emit_answer(null)

func _emit_answer(value: Variant) -> void:
	if submissions_enabled:
		set_submission_enabled(false)
		answered.emit(ask.id, value)

func show_error(message: String) -> void:
	error_label.text = message
	error_label.show()

func set_submission_enabled(enabled: bool) -> void:
	submissions_enabled = enabled
	_set_controls_enabled(self, enabled)
	_validate()

func _set_controls_enabled(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is Button:
			child.disabled = not enabled
		elif child is LineEdit:
			child.editable = enabled
		elif child is SpinBox:
			child.editable = enabled
		_set_controls_enabled(child, enabled)

func _focus_search() -> void:
	if is_instance_valid(search) and search.is_inside_tree() and search.is_visible_in_tree():
		search.grab_focus()

func _focus_input() -> void:
	if is_inside_tree() and is_instance_valid(input) and input.is_inside_tree():
		input.grab_focus()
