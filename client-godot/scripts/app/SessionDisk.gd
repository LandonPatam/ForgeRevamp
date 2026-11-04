extends Control
signal resume_requested
signal end_requested
const Cartridge = preload("res://scripts/app/DeckCartridge.gd")
const P = preload("res://scripts/ui/Palette.gd")
var images: Node
var info: Dictionary = {}
var disk: Control
var resume_button: Button
var end_button: Button
var printed: Label
var details: Label
var state_lines: Array[Label] = []
const STATE_Y := [260.0, 294.0, 328.0, 394.0]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resume_button = Button.new()
	resume_button.text = ""
	resume_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		resume_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	resume_button.pressed.connect(func(): resume_requested.emit())
	add_child(resume_button)
	disk = Cartridge.new()
	disk.images = images
	disk.deck = {"id": "session", "name": "Resume game", "cover": {}}
	resume_button.add_child(disk)
	disk.shell_color = Color("587e89")
	disk.face_material.set_shader_parameter("shell_color", disk.shell_color)
	printed = Label.new()
	printed.position = Vector2(215, 75)
	printed.size = Vector2(246, 368)
	printed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	printed.add_theme_font_size_override("font_size", 25)
	printed.add_theme_color_override("font_color", Color("203a40"))
	printed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disk.face_view.add_child(printed)
	printed.max_lines_visible = 5
	for y in STATE_Y:
		var line := Label.new()
		line.position = Vector2(215, y)
		line.size = Vector2(246, 64)
		line.clip_text = true
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_theme_font_size_override("font_size", 25)
		line.add_theme_color_override("font_color", Color("203a40"))
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		disk.face_view.add_child(line)
		state_lines.append(line)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.max_lines_visible = 3
	details.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_theme_font_size_override("font_size", 16)
	details.add_theme_color_override("font_color", Color("38525b"))
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(details)
	end_button = Button.new()
	end_button.text = "End Game"
	P.style_menu_button(end_button)
	end_button.pressed.connect(func(): end_requested.emit())
	add_child(end_button)
	resized.connect(_layout)
	update_info(info)
	_layout()

func update_info(value: Dictionary) -> void:
	info = value.duplicate(true)
	if printed == null: return
	var name_value: String = info.get("name", "Commander")
	printed.text = "LIVE SESSION\n------------\n%s" % name_value.left(36)
	var values := ["TURN %d" % int(info.get("turn", 1)), str(info.get("phase", "")), "LIFE %d" % int(info.get("life", 40)), "CLICK TO RESUME"]
	for index in range(state_lines.size()): state_lines[index].text = values[index]
	details.text = "RESUME GAME\nTurn %d · %s\n%s" % [int(info.get("turn", 1)), str(info.get("phase", "")), name_value]
	resume_button.tooltip_text = str(info.get("decision", "Resume the same live game"))
	if info.get("reconnect", false):
		printed.text = "ONLINE SESSION\n------------\n%s" % name_value.left(36)
		state_lines[3].text = "CLICK TO REJOIN"
		details.text = "REJOIN ONLINE GAME\n" + name_value
		end_button.text = "Forget session"
	else: end_button.text = "End Game"
	disk.face_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	disk.queue_redraw()

func _layout() -> void:
	if disk == null: return
	resume_button.size = Vector2(size.x, size.x)
	disk.size = Vector2(size.x, size.x)
	details.position = Vector2(0, size.x + 8)
	details.size = Vector2(size.x, 76)
	end_button.position = Vector2(22, size.x + 88)
	end_button.size = Vector2(size.x - 44, 34)
