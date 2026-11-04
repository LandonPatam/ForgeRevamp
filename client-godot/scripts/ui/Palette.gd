extends RefCounted

const INK := Color("0b141a")
const PANEL := Color("111f27")
const LINE := Color("2c3c42")
const TEXT := Color("e5e8df")
const MUTED := Color("8eaaa9")
const GOLD := Color("cfad70")
const MINT := Color("83cdb1")

static func accent(key: String) -> Color:
	return {"G": Color("83b591"), "U": Color("80afc9"), "R": Color("d28e72"), "B": Color("b09dc6"), "W": Color("d8c9a0")}.get(key, MINT)

static func display_font() -> FontVariation:
	var heavy := SystemFont.new()
	heavy.font_names = PackedStringArray(["Arial Black", "Arial", "DejaVu Sans"])
	heavy.font_weight = 900
	var result := FontVariation.new()
	result.base_font = heavy
	result.variation_transform = Transform2D(Vector2(1, 0.18), Vector2.DOWN, Vector2.ZERO)
	return result

static func style_menu_button(button: Button, primary: bool = false) -> void:
	var fill := Color("127d99") if primary else Color("34363a")
	button.add_theme_font_override("font", display_font())
	button.add_theme_font_size_override("font_size", 16)
	button.custom_minimum_size.y = 46
	for color in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(color, Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("929ca3"))
	button.add_theme_stylebox_override("normal", box(fill, fill.lightened(0.3) if primary else Color("878b90"), 7, 12))
	button.add_theme_stylebox_override("hover", box(fill.lightened(0.18), Color.WHITE, 7, 12))
	button.add_theme_stylebox_override("pressed", box(fill.darkened(0.15), Color.WHITE, 7, 12))
	button.add_theme_stylebox_override("disabled", box(fill.darkened(0.55), Color("494e53"), 7, 12))
	button.add_theme_stylebox_override("focus", box(Color.TRANSPARENT, Color.WHITE, 7, 12))

static func popup_theme() -> Theme:
	var terminal = preload("res://scripts/ui/TerminalStyle.gd")
	var result: Theme = terminal.theme()
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 12)
	for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := Color("14393e") if kind == "hover" else Color("1c4c50") if kind == "pressed" else Color("0a1e22")
		var edge: Color = terminal.INK if kind in ["hover", "pressed", "focus"] else terminal.EDGE
		result.set_stylebox(kind, "Button", box(Color.TRANSPARENT if kind == "focus" else fill, edge, 2, 12))
		result.set_color("font_color" if kind == "normal" else "font_" + kind + "_color", "Button", terminal.MUTED if kind == "disabled" else terminal.INK)
	result.set_stylebox("normal", "LineEdit", box(Color("061712"), terminal.EDGE, 2, 12))
	result.set_stylebox("focus", "LineEdit", box(Color("061712"), terminal.ACCENT, 2, 12))
	result.set_color("font_color", "LineEdit", terminal.INK)
	result.set_color("caret_color", "LineEdit", terminal.ACCENT)
	return result

static func style_popup_button(button: Button, primary: bool = false) -> void:
	preload("res://scripts/ui/TerminalStyle.gd").button(button, primary)

static func style_popup(panel: PanelContainer, margin: int = 26) -> void:
	panel.theme = popup_theme()
	var frame := box(Color("061712"), Color("3d8373"), 2, margin)
	frame.shadow_color = Color(0, 0, 0, 0.6)
	frame.shadow_size = 20
	frame.shadow_offset = Vector2.ZERO
	panel.add_theme_stylebox_override("panel", frame)

static func box(fill: Color, border: Color = Color.TRANSPARENT, radius: int = 10, margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(margin)
	return style

static func make_theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Inter", "Noto Sans"])
	result.default_font = font
	result.default_font_size = 14
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_disabled_color", "Button", Color("566d72"))
	result.set_stylebox("normal", "Button", box(Color("16262d"), LINE, 7, 10))
	result.set_stylebox("hover", "Button", box(Color("21363c"), Color("648b85"), 7, 10))
	result.set_stylebox("pressed", "Button", box(Color("28443f"), MINT, 7, 10))
	result.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD, 7, 10))
	result.set_stylebox("disabled", "Button", box(Color("102027"), Color("24343a"), 7, 10))
	result.set_stylebox("normal", "LineEdit", box(INK, LINE, 7, 12))
	result.set_stylebox("focus", "LineEdit", box(INK, GOLD, 7, 12))
	result.set_color("font_color", "LineEdit", TEXT)
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 10)
	return result
