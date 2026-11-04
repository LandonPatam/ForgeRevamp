extends Button
## A compact inline check: yellow action, animated check, or green status.
var status := ""
var clock := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(100, 36)
	set_process(false)

func update_status(legal: bool, checking: bool, available: bool, report: String) -> void:
	var next := "checking" if checking else "legal" if legal else "validate"
	disabled = checking or legal or not available
	mouse_default_cursor_shape = Control.CURSOR_ARROW if legal else Control.CURSOR_POINTING_HAND
	tooltip_text = report if legal else ("Checking Forge's Commander rules…" if checking else "Check this draft against Forge's Commander rules." + ("\n" + report if not report.is_empty() else ""))
	if next == status: return
	status = next
	text = "Legal" if legal else "Checking" if checking else "Validate"
	set_process(checking)
	clock = 0.0
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color.TRANSPARENT if legal else Color("e2c56d").lightened(0.12 if state == "hover" else 0.0)
		box.border_color = Color.TRANSPARENT if legal else Color("a58a43")
		box.set_border_width_all(0 if legal else 1)
		box.set_corner_radius_all(5)
		box.content_margin_left = 25 if legal or checking else 10
		box.content_margin_right = 10
		add_theme_stylebox_override(state, box)
		add_theme_color_override("font_" + state + "_color" if state != "normal" else "font_color", Color("329b58") if legal else Color("352b12"))
	queue_redraw()

func _process(delta: float) -> void:
	clock += delta
	queue_redraw()

func _draw() -> void:
	var center := Vector2(12, size.y * 0.5)
	if status == "legal":
		draw_circle(center, 7, Color(0.20, 0.75, 0.36, 0.12))
		draw_circle(center, 4, Color("42c56e"))
	elif status == "checking":
		draw_arc(center, 5, clock * TAU, clock * TAU + TAU * 0.72, 20, Color("594614"), 2, true)
