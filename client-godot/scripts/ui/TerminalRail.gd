extends PanelContainer
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")

func _ready() -> void:
	Terminal.panel(self,16)
	resized.connect(queue_redraw)

func _draw() -> void:
	var bounds := Rect2(Vector2(4,4),size-Vector2(8,8))
	draw_rect(bounds,Color("163c42"),false,1)
	for y in range(8,int(size.y)-8,4):
		draw_line(Vector2(8,y),Vector2(size.x-8,y),Color(0.08,0.25,0.28,0.08),1)
