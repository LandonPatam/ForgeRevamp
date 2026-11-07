extends Control
## Full-screen win/loss terminal: ASCII "rain", then block letters made of falling characters
## lock into place to spell YOU WIN / YOU LOSE, a typed status line, and one button.
## Drawn every frame with a monospace font; no shaders, so it works under GL Compatibility.
signal acknowledged

const P = preload("res://scripts/ui/Palette.gd")
const GLYPHS := "0123456789ABCDEFXZ#$%&*+=<>/\\|{}[]?!@"
const LETTERS := {
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	" ": ["...", "...", "...", "...", "...", "...", "..."],
}
const RAIN := Color("65e0d5")
const FALL_SECONDS := 0.55
const TYPE_RATE := 38.0

var victory := false
var font: SystemFont
var clock := 0.0
var rain_cell := 16.0
var cell := 24.0
var columns: Array = []
var cells: Array = []
var settle_time := 0.0
var status := ""
var button: Button
var built_size := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP # The table waits until the result is acknowledged.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "monospace"])
	button = Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(300, 64)
	P.style_popup_button(button, true)
	button.add_theme_font_size_override("font_size", 28)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.pressed.connect(_acknowledge)
	add_child(button)
	button.hide()
	resized.connect(_build)

func present(won: bool) -> void:
	victory = won
	button.text = "I WON" if won else "I lost"
	status = "> ALL OPPONENTS ELIMINATED. RETURNING TO THE COMPUTER." if won else "> SEAT ELIMINATED. YOU CAN KEEP WATCHING THE TABLE."
	clock = 0.0
	built_size = Vector2.ZERO
	_build()
	show()
	set_process(true)

func accent() -> Color:
	return Color("bd9bf2") if victory else Color("ff765e")

## Lay out the rain columns and the falling message cells for the current size.
func _build() -> void:
	if size.x < 8 or size.y < 8 or size == built_size: return
	built_size = size
	var word := "YOU WIN" if victory else "YOU LOSE"
	var pixel_columns := 0
	for letter in word: pixel_columns += LETTERS[letter][0].length() + 1
	pixel_columns -= 1
	cell = clampf(size.x * 0.78 / pixel_columns, 10.0, 30.0)
	rain_cell = clampf(cell * 0.62, 11.0, 18.0)
	var origin := Vector2((size.x - pixel_columns * cell) * 0.5, size.y * 0.36 - 3.5 * cell)
	cells.clear()
	var x := 0
	var latest := 0.0
	for letter in word:
		var rows: Array = LETTERS[letter]
		for row in range(rows.size()):
			for column in range(rows[row].length()):
				if rows[row][column] != "#": continue
				var delay := 0.25 + (x + column) * 0.022 + randf() * 0.45
				latest = maxf(latest, delay)
				cells.append({"target": origin + Vector2((x + column) * cell, row * cell), "delay": delay, "drop": cell * randf_range(4.0, 18.0), "glyph": _glyph(), "flip": 0.0})
		x += rows[0].length() + 1
	settle_time = latest + FALL_SECONDS
	columns.clear()
	for index in range(int(size.x / rain_cell) + 1):
		columns.append({"x": index * rain_cell, "head": randf_range(-size.y, size.y), "speed": randf_range(size.y * 0.35, size.y * 0.9), "length": randi_range(6, 22), "seed": randi()})
	button.position = Vector2((size.x - button.custom_minimum_size.x) * 0.5, size.y * 0.36 + 3.5 * cell + 110)
	button.size = button.custom_minimum_size

func _glyph() -> String:
	return GLYPHS[randi() % GLYPHS.length()]

func _process(delta: float) -> void:
	clock += delta
	for column in columns:
		column.head += column.speed * delta
		if column.head - column.length * rain_cell > size.y:
			column.head = randf_range(-size.y * 0.5, 0.0)
			column.speed = randf_range(size.y * 0.35, size.y * 0.9)
	for entry in cells:
		entry.flip -= delta
		var locked: bool = clock >= entry.delay + FALL_SECONDS
		# Falling characters scramble quickly; locked ones only occasionally flicker.
		if entry.flip <= 0.0:
			entry.glyph = _glyph()
			entry.flip = randf_range(0.6, 2.4) if locked else 0.06
	var reveal := clock >= settle_time + 0.35
	if reveal and not button.visible:
		button.modulate.a = 0.0
		button.show()
		create_tween().tween_property(button, "modulate:a", 1.0, 0.3)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.03, 0.035, minf(0.9, clock * 2.6)))
	var rain_size := int(rain_cell * 0.9)
	var step := int(clock * 9.0)
	for column in columns:
		for k in range(int(column.length)):
			var y: float = column.head - k * rain_cell
			if y < -rain_cell or y > size.y + rain_cell: continue
			var glyph: String = GLYPHS[abs(hash([column.seed, int(y / rain_cell), step if k < 3 else 0])) % GLYPHS.length()]
			var fade: float = 1.0 - float(k) / column.length
			var color: Color = Color(0.86, 1.0, 0.98, 0.85) if k == 0 else Color(RAIN, 0.42 * fade)
			draw_char(font, Vector2(column.x, y), glyph, rain_size, color)
	var tint := accent()
	var glyph_size := int(cell * 0.95)
	# A dark band keeps the message and status readable over the rain.
	var band_top := size.y * 0.36 - 3.5 * cell - cell * 1.2
	draw_rect(Rect2(0, band_top, size.x, 7 * cell + cell * 2.4 + 90), Color(0.01, 0.03, 0.035, minf(0.82, clock * 2.0)))
	for entry in cells:
		if clock < entry.delay: continue
		var progress := clampf((clock - entry.delay) / FALL_SECONDS, 0.0, 1.0)
		var at: Vector2 = entry.target - Vector2(0, entry.drop * (1.0 - progress * progress))
		var color: Color = Color(1, 1, 1, 0.9) if progress < 1.0 else tint.lightened(0.55).lerp(Color.WHITE, clampf(1.0 - (clock - entry.delay - FALL_SECONDS) * 4.0, 0.0, 1.0))
		if progress >= 1.0:
			# Solid blocks make the letters read at a glance; the characters stay on top.
			var landed := clampf((clock - entry.delay - FALL_SECONDS) * 3.0, 0.0, 1.0)
			draw_rect(Rect2(at + Vector2(1, 1), Vector2(cell - 2, cell - 2)), Color(tint.darkened(0.35), 0.55 * landed))
		draw_char(font, at + Vector2(cell * 0.18, cell * 0.82), entry.glyph, glyph_size, color)
	if clock > settle_time:
		var typed := status.substr(0, int((clock - settle_time) * TYPE_RATE))
		var cursor := "_" if int(clock * 2.5) % 2 == 0 else " "
		var line_size := int(clampf(cell * 0.62, 13, 20))
		var width := font.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size).x
		draw_string(font, Vector2((size.x - width) * 0.5, size.y * 0.36 + 3.5 * cell + 62), typed + cursor, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size, Color(RAIN, 0.95))

func _acknowledge() -> void:
	if not button.visible: return
	set_process(false)
	acknowledged.emit()

## Enter (or Space) acknowledges once the button is showing; other table shortcuts are swallowed.
func handle_key(event: InputEventKey) -> void:
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and button.visible: _acknowledge()
