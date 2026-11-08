extends PanelContainer
## A yes/no Forge confirmation attached to the card it asks about ("Sacrifice Evolving Wilds?"):
## a small terminal box beside the card, joined to it by a leader line drawn by InteractionPanel.
signal answered(action: String)
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const BLINK_SECONDS := 0.55
var title: Label
var line: Label
var yes_button: Button
var no_button: Button
var question := ""
var cursor_on := true
var blink := 0.0

func _ready() -> void:
	Terminal.panel(self, 12)
	var frame := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	frame.border_color = Terminal.ACCENT
	frame.shadow_color = Color(0, 0, 0, 0.45)
	frame.shadow_size = 8
	add_theme_stylebox_override("panel", frame)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	title = _label(12, Terminal.MUTED)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	line = _label(16, Terminal.INK)
	column.add_child(line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	yes_button = _button(func(): answered.emit("ok"))
	Terminal.button(yes_button, true)
	row.add_child(yes_button)
	no_button = _button(func(): answered.emit("cancel"))
	row.add_child(no_button)
	hide()

func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_font_override("font", Terminal.font())
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size.x = 250
	return label

func _button(callback: Callable) -> Button:
	var button := Button.new()
	Terminal.button(button)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button

## `card_name` labels the box; labels come from Forge's own Yes/No (or custom) button text.
func present(card_name: String, message: String, ok_label: String, cancel_label: String, ok_enabled: bool, cancel_enabled: bool) -> void:
	title.text = "[ %s ]" % card_name.to_upper()
	question = "> " + message.strip_edges().to_lower()
	_show_line()
	yes_button.text = "[Y] " + ok_label
	no_button.text = "[N] " + cancel_label
	yes_button.disabled = not ok_enabled
	no_button.disabled = not cancel_enabled
	no_button.visible = cancel_enabled or not cancel_label.is_empty()

func _show_line() -> void:
	line.text = question + ("_" if cursor_on else " ")

func _process(delta: float) -> void:
	if not visible: return
	blink += delta
	if blink >= BLINK_SECONDS:
		blink = 0.0
		cursor_on = not cursor_on
		_show_line()
