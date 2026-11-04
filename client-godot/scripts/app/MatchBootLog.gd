extends Control
## Presentation runs line by line; readiness gates can only be opened by the host.
signal activity
const Console = preload("res://scripts/app/DeckConsole.gd")
const Meter = preload("res://scripts/app/TerminalMeter.gd")
const SAFE_RECT = Console.SAFE_RECT
const DESIGN_SIZE = Console.DESIGN_SIZE
const BASELINES := [166, 224, 282, 340, 398, 530]
const CAPS := [0.10, 0.22, 0.34, 0.68, 0.84, 0.96]
var rows: Array[String] = []
var names := ""
var disk_name := ""
var commander := ""
var card_count := 0
var unlocked := 0
var done_count := 0
var printed := 0.0
var dots_age := 0.0
var ok_age := 0.0
var row_age := 0.0
var elapsed := 0.0
var value := 0.0
var ready_age := 0.0
var active := false
var complete := false
var resuming := false
var failed := ""
var text_bounds: Array[Rect2] = []
var _last_chars := -1
var _ok_lit := false
var character_rate := 85.0
var dot_delay := 0.22
var ok_delay := 0.16
var row_delay := 0.30
var progress_rate := 0.65
var stage_caps: Array = CAPS

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)
	set_process(false)

func begin(deck: Dictionary, setup: Dictionary, resume: bool = false) -> void:
	resuming = resume
	disk_name = str(deck.get("name", "SESSION DISK")).to_upper()
	commander = " + ".join(deck.get("sections", {}).get("Commander", []).map(func(card): return card.name)).to_upper()
	card_count = int(Console.summarize(deck).total)
	var players: Array = [setup.get("human", {"name": "YOU"})] + setup.get("bots", [])
	names = ", ".join(players.map(func(player): return str(player.get("name", "PLAYER")).to_upper()))
	rows.assign([
		("READING SESSION: " if resume else "READING DISK: ") + disk_name,
		"COMMANDER: " + commander,
		"%d / 100 CARDS VERIFIED" % card_count,
		"CONNECTING LIVE ENGINE" if resume else "LOADING RULES ENGINE",
		"SEATING PLAYERS: %d" % players.size(),
		"RESTORING TABLE" if resume else "SHUFFLING LIBRARIES"
	])
	unlocked = 3 # Actual disk metadata was read and validated before insertion.
	done_count = 0
	printed = 0
	dots_age = 0
	ok_age = 0
	row_age = 0
	elapsed = 0
	value = 0
	ready_age = 0
	failed = ""
	complete = false
	active = true
	_last_chars = -1
	_ok_lit = false
	show()
	set_process(true)
	activity.emit()
	queue_redraw()

func engine_ready() -> void:
	unlocked = maxi(unlocked, 4)

func players_ready(players: Array) -> void:
	if players.size() < 2: return
	names = ", ".join(players.map(func(player): return str(player.name).to_upper()))
	rows[4] = "SEATING PLAYERS: %d" % players.size()
	unlocked = maxi(unlocked, 5)

func table_ready() -> void:
	# A stage label or elapsed time must never authorize the last OK / 100%.
	if unlocked >= 5: unlocked = 6

func stop() -> void:
	active = false
	set_process(false)

func fail(message: String) -> void:
	failed = message.to_upper()
	set_process(false)
	queue_redraw()

func wait_for_finish() -> bool:
	while active and failed.is_empty() and (not complete or value < 1 or ready_age < 0.65):
		await get_tree().process_frame
	return active and complete and failed.is_empty()

func _process(delta: float) -> void:
	if not active or not failed.is_empty(): return
	elapsed += delta
	if done_count < rows.size():
		row_age += delta
		printed = minf(rows[done_count].length(), printed + delta * character_rate)
		var chars := int(printed) / 6
		if chars != _last_chars:
			_last_chars = chars
			activity.emit()
		if printed >= rows[done_count].length():
			dots_age += delta
			if dots_age >= dot_delay and done_count < unlocked:
				ok_age += delta
				if ok_age >= ok_delay and not _ok_lit:
					_ok_lit = true
					activity.emit()
				if ok_age >= row_delay:
					done_count += 1
					printed = 0
					dots_age = 0
					ok_age = 0
					row_age = 0
					_last_chars = -1
					_ok_lit = false
	complete = done_count == rows.size() and unlocked == rows.size()
	var target := 1.0
	if not complete:
		var base: float = stage_caps[done_count - 1] if done_count > 0 else 0.0
		target = lerpf(base, stage_caps[done_count], 1.0 - exp(-row_age / 4.0))
	value = move_toward(value, maxf(value, target), delta * progress_rate)
	if complete and value >= 1: ready_age += delta
	queue_redraw()

func _text(text: String, position: Vector2, font_size: int, width: float, color: Color = Console.INK) -> void:
	var font := get_theme_default_font()
	var visible := text
	while font.get_string_size(visible, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and not visible.is_empty():
		visible = visible.left(visible.length() - 1)
	if visible != text: visible = visible.left(maxi(0, visible.length() - 3)) + "..."
	var extent := font.get_string_size(visible, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	text_bounds.append(Rect2(position - Vector2(0, font.get_ascent(font_size)), Vector2(extent.x, font.get_height(font_size))))
	draw_string(font, position, visible, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

func _name_lines() -> Array[String]:
	var lines: Array[String] = [""]
	var font := get_theme_default_font()
	for word in names.split(" "):
		var candidate := (lines[-1] + " " + word).strip_edges()
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x > 840 and lines.size() < 2:
			lines.append(word)
		else: lines[-1] = candidate
	return lines

func _draw_header() -> void:
	_text("FORGECHECK 1.0", Vector2(64, 86), 28, 420)
	_text("COMMANDER SYSTEM", Vector2(703, 86), 26, 257, Console.DIM)
	draw_line(Vector2(64, 106), Vector2(960, 106), Console.EDGE, 1)

func _draw_row(index: int, baseline: float) -> void:
	var label: String = rows[index] if index < done_count else rows[index].left(int(printed))
	_text("> " + label, Vector2(64, baseline), 30, 794)
	var filled := index < done_count or (index == done_count and _ok_lit)
	if index < done_count or printed >= rows[index].length():
		var label_width := minf(794, get_theme_default_font().get_string_size("> " + rows[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x)
		var x := 64 + label_width + 8
		var dots := maxi(0, int((884 - x) / 18))
		if index == done_count: dots = mini(dots, int(dots_age * 60))
		_text(".".repeat(dots), Vector2(x, baseline), 30, maxf(0, 884 - x), Console.DIM)
	_text("OK" if filled else ("_" if int(elapsed * 2) % 2 == 0 else ""), Vector2(918, baseline), 30, 42)

func _draw() -> void:
	text_bounds.clear()
	draw_set_transform(Vector2.ZERO, 0, size / Console.DESIGN_SIZE)
	draw_rect(Rect2(Vector2.ZERO, Console.DESIGN_SIZE), Console.DARK)
	_draw_header()
	for index in range(mini(done_count + 1, rows.size())):
		_draw_row(index, BASELINES[index])
		if index == 4:
			var lines := _name_lines()
			for line in range(lines.size()): _text(lines[line], Vector2(100, 432 + line * 32), 26, 840, Console.DIM)
	Meter.paint(self, Rect2(64, 574, 754, 16), value)
	_text("%3d%%" % mini(100 if complete else 99, floori(value * 100)), Vector2(854, 591), 32, 106)
	var footer := "READY. ENTERING TABLE..." if complete and value >= 1 else "BOOTING COMMANDER"
	if resuming and not complete: footer = "RESUMING COMMANDER"
	if not failed.is_empty(): footer = "ERROR: " + failed
	_text(footer, Vector2(64, 660), 32, 864, Color("f2a19d") if not failed.is_empty() else Console.INK)
	if int(elapsed * 2) % 2 == 0:
		var cursor_x := minf(938, 72 + get_theme_default_font().get_string_size(footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x)
		draw_rect(Rect2(cursor_x, 636, 18, 27), Console.INK)
	if complete and value >= 1 and ready_age < 0.12:
		draw_rect(Rect2(Vector2.ZERO, Console.DESIGN_SIZE), Color(0.32, 0.88, 0.76, (1.0 - ready_age / 0.12) * 0.12))
	draw_set_transform(Vector2.ZERO)
