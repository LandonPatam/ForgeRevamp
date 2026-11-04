extends VBoxContainer
## Continuous rules text: bounded height, normal wrapping, and native scrolling.
var label: Label
var scroll: ScrollContainer
var reading_hint: Label
var full_text := ""

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_constant_override("line_spacing", 3)
	scroll.add_child(label)
	reading_hint = Label.new()
	reading_hint.add_theme_font_size_override("font_size", 12)
	reading_hint.add_theme_color_override("font_color", Color("6d9fa3"))
	add_child(reading_hint)
	scroll.get_v_scroll_bar().changed.connect(_update_hint)
	scroll.get_v_scroll_bar().value_changed.connect(func(_value): _update_hint())

static func compact_text(text: String) -> String:
	# Forge messages can contain CRLF and repeated spacer lines. Keep paragraph
	# boundaries and every nonblank line, without the engine's visual padding.
	var lines: PackedStringArray = []
	var blank := false
	for raw in text.replace("\r\n", "\n").replace("\r", "\n").strip_edges().split("\n"):
		var line := raw.strip_edges()
		if line.is_empty():
			if not blank: lines.append("")
		else: lines.append(line)
		blank = line.is_empty()
	return "\n".join(lines)

func present(text: String, width: float, budget: float, font_size: int = 15) -> void:
	var changed := full_text != text
	full_text = text
	label.text = compact_text(text)
	label.add_theme_font_size_override("font_size", font_size)
	var font := label.get_theme_font("font")
	var height := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width - 20, font_size).y
	# Reserve line spacing too; the ScrollContainer handles actual font wrapping.
	height += maxf(0, height / font.get_height(font_size) - 1) * 3
	scroll.custom_minimum_size = Vector2(width, minf(maxf(font.get_height(font_size), height), maxf(40, budget)))
	if changed: scroll.scroll_vertical = 0
	_update_hint.call_deferred()

func _update_hint() -> void:
	var bar := scroll.get_v_scroll_bar()
	reading_hint.visible = bar.max_value > bar.page + 1
	reading_hint.text = "Scroll to read more" if bar.value + bar.page < bar.max_value - 1 else "End of rules"
