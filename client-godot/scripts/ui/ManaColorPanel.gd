extends PanelContainer
signal action_requested(action: String)
const P = preload("res://scripts/ui/Palette.gd")
const Option = preload("res://scripts/ui/ManaOption.gd")

static func needs_selection(state: Dictionary) -> bool:
	var prompt: Dictionary = state.get("prompt", {})
	return state.get("asks", []).is_empty() and prompt.get("inputKind", "") == "InputConfirm" and not Option.colors_for(prompt.get("okLabel", "")).is_empty() and not Option.colors_for(prompt.get("cancelLabel", "")).is_empty()

func present(state: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	P.style_popup(self)
	var column := VBoxContainer.new()
	add_child(column)
	var title := Label.new()
	title.text = "Choose mana to add to pool"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size.x = 470
	column.add_child(title)
	var choices := HBoxContainer.new()
	choices.add_theme_constant_override("separation", 16)
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(choices)
	for action in ["ok", "cancel"]:
		var button := Option.new()
		button.choice_tile = true
		button.text = state.prompt.get(action + "Label", "")
		button.colors = Option.colors_for(button.text)
		P.style_popup_button(button, true)
		button.disabled = not state.get("connectionReady", false) or not state.prompt.get(action + "Enabled", false)
		button.pressed.connect(func(): action_requested.emit(action))
		choices.add_child(button)
