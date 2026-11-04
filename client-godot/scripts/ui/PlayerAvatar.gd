extends Control
signal activated
const P = preload("res://scripts/ui/Palette.gd")
var player: Dictionary = {}
var priority := false
var clock := 0.0
var damage_flash := 0.0
var portrait: Texture2D
var terminal_font: SystemFont
var portrait_only := false

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	terminal_font = SystemFont.new()
	terminal_font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono"])

func set_player(value: Dictionary, active: bool) -> void:
	if not player.is_empty() and player.life != value.life:
		damage_flash = 1.0
	player = value.duplicate(true)
	portrait = preload("res://scripts/ui/Portraits.gd").texture(player)
	priority = active
	tooltip_text = player.name + " / " + str(player.life) + " life. Click to select this player."
	set_process(priority or damage_flash > 0.0)
	queue_redraw()

func _process(delta: float) -> void:
	clock += delta
	damage_flash = maxf(0, damage_flash - delta * 1.5)
	queue_redraw()
	if not priority and is_zero_approx(damage_flash): set_process(false)

func _draw() -> void:
	if player.is_empty():
		return
	if portrait_only:
		var side := maxf(1, minf(size.x, size.y) - 8)
		var face := Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)
		draw_style_box(P.box(Color("11191b"), Color("538c91"), 3, 0), face.grow(2))
		if portrait != null:
			draw_texture_rect(portrait, face, false)
		else:
			draw_string(terminal_font, face.position + Vector2(0, side * 0.5 + 11), player.get("initials", "P"), HORIZONTAL_ALIGNMENT_CENTER, side, 30, Color("a6dfdf"))
		return
	var factor := minf(size.x / 136.0, size.y / 62.0)
	var origin := (size - Vector2(136, 62) * factor) * 0.5
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	var ink := Color("65e0d5").lerp(Color("ff765e"), damage_flash)
	var edge := Color("a78bd4") if priority else Color("697474")
	# One arcade scoreboard housing: clean portrait window and recessed LEDs.
	draw_style_box(P.box(Color("111718"), Color("0a0e0f"), 5, 0), Rect2(0, 3, 136, 59))
	draw_style_box(P.box(Color("303a3e"), edge, 5, 0), Rect2(0, 0, 136, 58))
	draw_line(Vector2(6, 2), Vector2(130, 2), Color("657174"), 1)
	var face := Rect2(6, 6, 44, 44)
	draw_style_box(P.box(Color("11191b"), Color("121b1e"), 2, 0), face.grow(2))
	if portrait != null:
		draw_texture_rect(portrait, face, false)
	else:
		draw_string(terminal_font, face.position + Vector2(0, 29), player.get("initials", "P"), HORIZONTAL_ALIGNMENT_CENTER, face.size.x, 20, Color("c7d3d1"))
	draw_style_box(P.box(Color("0b1110"), Color("101719"), 3, 0), Rect2(55, 5, 75, 48))
	draw_string(terminal_font, Vector2(61, 15), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("779d9b"))
	var led := Color("30263f")
	if priority:
		led = Color("bd9bf2")
		led.a = 0.8 + sin(clock * 2) * 0.15
		draw_circle(Vector2(121, 12), 4, Color(led, led.a * 0.14))
	draw_circle(Vector2(121, 12), 2, led)
	_draw_digits(str(player.life), Rect2(59, 20, 67, 29), ink)
	if has_focus(): draw_rect(Rect2(0, 0, 136, 58), ink, false, 1)
	draw_set_transform(Vector2.ZERO)

func _draw_digits(value: String, rect: Rect2, color: Color) -> void:
	var scale_factor := minf(rect.size.y / 34.0, rect.size.x / (value.length() * 24.0 - 4.0))
	var width := (value.length() * 24.0 - 4.0) * scale_factor
	var start := rect.position + Vector2((rect.size.x - width) * 0.5, (rect.size.y - 34 * scale_factor) * 0.5)
	var masks := {"0": 63, "1": 6, "2": 91, "3": 79, "4": 102, "5": 109, "6": 125, "7": 7, "8": 127, "9": 111, "-": 64}
	var bars := [Rect2(3, 0, 14, 3), Rect2(17, 3, 3, 12), Rect2(17, 19, 3, 12), Rect2(3, 31, 14, 3), Rect2(0, 19, 3, 12), Rect2(0, 3, 3, 12), Rect2(3, 15.5, 14, 3)]
	for index in range(value.length()):
		var mask: int = masks.get(value[index], 0)
		for segment in range(7):
			var bar: Rect2 = bars[segment]
			var points := PackedVector2Array()
			var x := bar.position.x
			var y := bar.position.y
			var w := bar.size.x
			var h := bar.size.y
			if w > h:
				points = PackedVector2Array([Vector2(x, y + h / 2), Vector2(x + 1.5, y), Vector2(x + w - 1.5, y), Vector2(x + w, y + h / 2), Vector2(x + w - 1.5, y + h), Vector2(x + 1.5, y + h)])
			else:
				points = PackedVector2Array([Vector2(x + w / 2, y), Vector2(x + w, y + 1.5), Vector2(x + w, y + h - 1.5), Vector2(x + w / 2, y + h), Vector2(x, y + h - 1.5), Vector2(x, y + 1.5)])
			for point in range(points.size()): points[point] = start + (points[point] + Vector2(index * 24, 0)) * scale_factor
			draw_colored_polygon(points, color if mask & (1 << segment) else Color("163531"))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit()
		accept_event()
