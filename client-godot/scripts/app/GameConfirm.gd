extends Control
signal confirmed
signal canceled
const P = preload("res://scripts/ui/Palette.gd")
var title := "Commander game"
var dialog_text := ""
var ok_button_text := "Continue"
var cancel_button_text := "Keep playing"
## False for announcements with a single button; Escape then acts as that button.
var show_cancel := true
var heading: Label
var message: Label
var ok: Button
var cancel: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 500
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.03, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	P.style_popup(panel, 28)
	panel.custom_minimum_size.x = 540
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "FORGE / COMMANDER"
	eyebrow.add_theme_color_override("font_color", Color("80cfc2"))
	column.add_child(eyebrow)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 30)
	column.add_child(heading)
	column.add_child(HSeparator.new())
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 484
	message.add_theme_font_size_override("font_size", 18)
	column.add_child(message)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	cancel = Button.new()
	P.style_popup_button(cancel)
	cancel.pressed.connect(func(): canceled.emit())
	buttons.add_child(cancel)
	ok = Button.new()
	P.style_popup_button(ok, true)
	ok.pressed.connect(func(): confirmed.emit())
	buttons.add_child(ok)
	hide()

func popup_centered() -> void:
	heading.text = title
	message.text = dialog_text
	ok.text = ok_button_text
	cancel.text = cancel_button_text
	cancel.visible = show_cancel
	show()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)
	(cancel if show_cancel else ok).grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if show_cancel: canceled.emit()
		else: confirmed.emit()
		get_viewport().set_input_as_handled()
