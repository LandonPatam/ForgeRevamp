extends RefCounted
const INK := Color("a6dfdf")
const MUTED := Color("6d9fa3")
const EDGE := Color("32676c")
const ACCENT := Color("bd9bf2")
static var mono: SystemFont
static var prompt_icon: Texture2D

static func font() -> Font:
	if mono == null:
		mono = SystemFont.new()
		mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono"])
	return mono

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = font()
	result.default_font_size = 14
	result.set_color("font_color", "Label", INK)
	var line := StyleBoxLine.new()
	line.color = EDGE
	line.thickness = 1
	result.set_stylebox("separator", "HSeparator", line)
	for state in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("0a2024") if state == "scroll" else EDGE.lightened(0.2 if state != "grabber" else 0.0)
		box.set_content_margin_all(4)
		result.set_stylebox(state, "VScrollBar", box)
	return result

static func panel(control: PanelContainer, margin: int = 14) -> void:
	control.theme = theme()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("07181b")
	frame.border_color = EDGE
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(4)
	frame.set_content_margin_all(margin)
	control.add_theme_stylebox_override("panel", frame)

static func button(control: Button, primary: bool = false) -> void:
	if prompt_icon == null:
		var pixels := Image.create(8,12,false,Image.FORMAT_RGBA8)
		pixels.fill(Color.TRANSPARENT)
		for y in range(2,9): pixels.set_pixel(6-absi(y-5),y,Color.WHITE)
		prompt_icon = ImageTexture.create_from_image(pixels)
	control.icon = prompt_icon
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.add_theme_font_override("font", font())
	control.add_theme_font_size_override("font_size", 14)
	control.custom_minimum_size.y = 40
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("2a2b47") if primary and state == "hover" else Color("14393e") if state == "hover" else Color("1b2032") if primary else Color("0a1e22")
		if state == "pressed": box.bg_color = Color("352e53") if primary else Color("1c4c50")
		if state == "disabled": box.bg_color = Color("08191b")
		box.border_color = ACCENT if primary else EDGE
		if state in ["hover", "focus"]: box.border_color = INK
		if state == "disabled": box.border_color = Color("23434a")
		box.set_border_width_all(1)
		box.border_width_left = 3 if primary else 1
		box.set_corner_radius_all(2)
		box.set_content_margin_all(10)
		if state == "focus": box.bg_color = Color.TRANSPARENT
		control.add_theme_stylebox_override(state, box)
		var ink := Color("436a70") if state == "disabled" else ACCENT if primary else INK
		control.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", ink)
		control.add_theme_color_override("icon_normal_color" if state == "normal" else "icon_" + state + "_color", ink)
