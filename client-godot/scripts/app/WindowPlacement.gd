extends Node
## Fit the complete decorated window, not just its client area, on one monitor.

func _ready() -> void:
	if DisplayServer.get_name() == "headless": return
	# Respect explicit launch/test placement, fullscreen and maximized windows.
	for argument in OS.get_cmdline_args():
		if argument in ["--resolution", "--position"] or argument.begins_with("--resolution=") or argument.begins_with("--position="): return
	fit_window.call_deferred()

static func client_rect(requested: Vector2i, usable: Rect2i, decoration: Vector2i, inset: Vector2i) -> Rect2i:
	var available := (usable.size - decoration).max(Vector2i.ONE)
	var ratio := minf(1.0, minf(float(available.x) / requested.x, float(available.y) / requested.y))
	var fitted := Vector2i(Vector2(requested) * ratio).max(Vector2i.ONE)
	return Rect2i(usable.position + (usable.size - fitted - decoration) / 2 + inset, fitted)

func fit_window() -> void:
	var window := get_window()
	if window.mode != Window.MODE_WINDOWED: return
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	if usable.size.x <= 0 or usable.size.y <= 0: return
	var decoration := (DisplayServer.window_get_size_with_decorations() - window.size).max(Vector2i.ZERO)
	var inset := window.position - DisplayServer.window_get_position_with_decorations()
	var fitted := client_rect(window.size, usable, decoration, inset)
	window.min_size = window.min_size.min(fitted.size)
	window.size = fitted.size
	window.position = fitted.position
