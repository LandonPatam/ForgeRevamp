extends PanelContainer
signal mana_selected(code: int)
signal cancel_requested
signal sources_requested
const P = preload("res://scripts/ui/Palette.gd")
const KEYS := ["W", "U", "B", "R", "G", "C"]
const CODES := [1, 2, 4, 8, 16, 0]
const NAMES := ["White", "Blue", "Black", "Red", "Green", "Colorless"]
var mana_buttons: Dictionary = {}
var cancel_button: Button
var sources_button: Button

func present(state: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	mana_buttons.clear()
	P.style_popup(self)
	custom_minimum_size.x = 520
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	add_child(column)
	var title := Label.new()
	title.text = "Choose mana to spend"
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	var message := Label.new()
	message.text = state.prompt.get("message", "Choose one mana from your pool.")
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 470
	column.add_child(message)
	var ready: bool = state.get("connectionReady", false)
	for i in range(KEYS.size()):
		var count: int = state.players[0].mana.get(KEYS[i], 0)
		if count <= 0: continue
		var button := preload("res://scripts/ui/ManaOption.gd").new()
		button.colors = [i]
		button.text = "%s · %d available" % [NAMES[i], count]
		button.custom_minimum_size.y = 43
		P.style_popup_button(button, true)
		button.disabled = not ready
		button.pressed.connect(func():
			set_submission_enabled(false)
			mana_selected.emit(CODES[i]))
		column.add_child(button)
		mana_buttons[KEYS[i]] = button
	if mana_buttons.is_empty():
		var empty := Label.new()
		empty.text = "Your mana pool is empty. Use a source to add mana."
		column.add_child(empty)
	var sources := Button.new()
	sources_button = sources
	sources.text = "Use a mana source on the battlefield"
	P.style_popup_button(sources)
	sources.disabled = not ready
	sources.pressed.connect(func(): sources_requested.emit())
	column.add_child(sources)
	cancel_button = Button.new()
	cancel_button.text = "Cancel activation"
	P.style_popup_button(cancel_button)
	cancel_button.disabled = not ready or not state.prompt.get("cancelEnabled", false)
	cancel_button.pressed.connect(func():
		set_submission_enabled(false)
		cancel_requested.emit())
	column.add_child(cancel_button)

func set_submission_enabled(enabled: bool) -> void:
	for button in mana_buttons.values():
		button.disabled = not enabled
	if not enabled and is_instance_valid(cancel_button): cancel_button.disabled = true
	if not enabled and is_instance_valid(sources_button): sources_button.disabled = true
