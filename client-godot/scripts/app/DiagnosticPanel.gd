extends PanelContainer
## A caption cut into the fine rectangular borders used by ForgeCheck.
var caption := ""
const INK := Color("70d6bc")
const DIM := Color("3d8373")
const DARK := Color("061712")

func _ready() -> void:
	var frame := StyleBoxFlat.new()
	frame.bg_color = DARK
	frame.border_color = DIM
	frame.set_border_width_all(1)
	frame.set_content_margin_all(18)
	frame.content_margin_top = 28
	add_theme_stylebox_override("panel",frame)
	resized.connect(queue_redraw)

func _draw() -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,22).x
	draw_rect(Rect2(12,-1,width+20,20),DARK)
	draw_string(font,Vector2(22,8),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,22,INK)
