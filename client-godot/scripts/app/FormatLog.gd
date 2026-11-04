extends "res://scripts/app/MatchBootLog.gd"
## Shares the boot terminal's typing, delayed OKs, activity pulses and meter.
const CLEANUP_TIMEOUT := 8.0
var cleanup_ready := Callable()
var cleanup_timed_out := false

func begin_format(info: Dictionary, stopped: Callable) -> void:
	begin({}, {})
	cleanup_ready = stopped
	cleanup_timed_out = false
	rows.assign([
		"FORMAT A: " + str(info.get("name", "SESSION DISK")).to_upper(),
		"ERASING TURN %d / %s / LIFE %d" % [int(info.get("turn", 1)), str(info.get("phase", "")).to_upper(), int(info.get("life", 40))],
		"CLEARING PLAYER SEATS",
		"RELEASING ENGINE"
	])
	unlocked = 3
	character_rate = 260.0
	dot_delay = 0.10
	ok_delay = 0.08
	row_delay = 0.16
	progress_rate = 1.1
	stage_caps = [0.25, 0.55, 0.88, 0.96]

func _process(delta: float) -> void:
	if active and unlocked < rows.size():
		if cleanup_ready.is_valid() and cleanup_ready.call():
			unlocked = rows.size()
		elif elapsed >= CLEANUP_TIMEOUT:
			cleanup_timed_out = true
			unlocked = rows.size()
			push_warning("FORMAT A: engine cleanup acknowledgment timed out; finishing presentation")
	super._process(delta)

func _draw() -> void:
	text_bounds.clear()
	draw_set_transform(Vector2.ZERO, 0, size / DESIGN_SIZE)
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), Console.DARK)
	_draw_header()
	for index in range(mini(done_count + 1, rows.size())):
		_draw_row(index, 180 + index * 80)
	Meter.paint(self, Rect2(64, 574, 754, 16), value)
	_text("%3d%%" % mini(100 if complete else 99, floori(value * 100)), Vector2(854, 591), 32, 106)
	_text("> SESSION ERASED." if complete and value >= 1 else "FORMATTING A: / PLEASE WAIT", Vector2(64, 660), 32, 864)
	draw_set_transform(Vector2.ZERO)
