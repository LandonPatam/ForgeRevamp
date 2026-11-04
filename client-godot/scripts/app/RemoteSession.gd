extends RefCounted
## Only seat credentials and public disk metadata belong here.
var path := "user://online-session.cfg"

func read() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path) != OK or config.get_value("seat", "version", 0) != 1: return {}
	var value = config.get_value("seat", "resume", {})
	if not value is Dictionary: return {}
	if not value.get("url") is String or not (value.url.begins_with("ws://") or value.url.begins_with("wss://")): return {}
	if not value.get("token") is String or value.token.is_empty(): return {}
	if not value.get("deck") is Dictionary or not value.get("info") is Dictionary or not value.get("session_id") is String: return {}
	return value

func save(value: Dictionary) -> Error:
	var config := ConfigFile.new()
	config.set_value("seat", "version", 1)
	config.set_value("seat", "resume", value)
	var result := config.save(path + ".tmp")
	if result != OK: return result
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))

func clear() -> void:
	for target in [path, path + ".tmp"]:
		if FileAccess.file_exists(target): DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
