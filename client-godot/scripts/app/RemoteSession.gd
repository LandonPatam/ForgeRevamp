extends RefCounted
## Reconnect credentials and public disk metadata only. Forge keeps the actual match.
var path := "user://online-session.cfg"

func read() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK or config.get_value("seat", "version", 0) != 1: return {}
	var value = config.get_value("seat", "resume", {})
	if not value is Dictionary: return {}
	if not value.get("url", null) is String or not value.get("token", null) is String: return {}
	if not value.url.begins_with("ws://") and not value.url.begins_with("wss://"): return {}
	if value.token.is_empty() or not value.get("deck", {}) is Dictionary or not value.get("info", {}) is Dictionary: return {}
	if not value.get("session_id", "") is String: return {}
	return value

func save(value: Dictionary) -> Error:
	var config := ConfigFile.new()
	config.set_value("seat", "version", 1)
	config.set_value("seat", "resume", value)
	# Replace only after a complete write, so a crash cannot truncate the saved seat.
	var result := config.save(path + ".tmp")
	if result != OK: return result
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))

func clear() -> void:
	for target in [path, path + ".tmp"]:
		if FileAccess.file_exists(target): DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
