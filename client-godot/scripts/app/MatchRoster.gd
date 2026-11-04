extends PanelContainer
## A cut-caption terminal frame for the match roster.
var caption := "ROSTER"
const INK := Color("65e0d5")
const EDGE := Color("326e70")
const DARK := Color("031013")

func _ready() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("041316")
	frame.border_color = EDGE
	frame.set_border_width_all(1)
	frame.set_content_margin_all(18)
	frame.content_margin_top = 30
	add_theme_stylebox_override("panel", frame)
	resized.connect(queue_redraw)

func _draw() -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_rect(Rect2(18, -8, width + 20, 22), DARK)
	draw_string(font, Vector2(28, 8), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, INK)
