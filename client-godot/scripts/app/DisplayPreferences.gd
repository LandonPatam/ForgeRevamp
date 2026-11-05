extends RefCounted
## Device-local display sizing, separate from decks, lobby configuration and readiness.
static func path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--library-fixture="):
			return argument.trim_prefix("--library-fixture=").path_join("display.cfg")
	return "user://display.cfg"

static func read() -> float:
	var config := ConfigFile.new()
	if config.load(path()) != OK: return 0.0
	var value = config.get_value("display", "ui_scale", 0.0)
	if not (value is float or value is int): return 0.0
	return clampf(float(value), 1.0, 2.0) if is_finite(float(value)) and float(value) > 0 else 0.0

static func current() -> float:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-scale="):
			var value := argument.trim_prefix("--ui-scale=")
			if value.is_valid_float() and is_finite(float(value)): return clampf(float(value), 1.0, 2.0)
	var choice := read()
	return choice if choice > 0 else (2.0 if OS.has_feature("macos") else 1.0)

static func save(choice: float) -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "ui_scale", clampf(choice, 1.0, 2.0) if choice > 0 else 0.0)
	return config.save(path())
