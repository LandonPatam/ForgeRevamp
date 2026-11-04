extends RefCounted

static func path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--library-fixture="): return arg.trim_prefix("--library-fixture=").path_join("match-settings.cfg")
	return "user://commander-match.cfg"

static func defaults() -> Dictionary:
	return {"human": {"name": "Player 1", "avatar": 0, "portrait": ""}, "bots": [bot(1), bot(2)]}

static func bot(index: int) -> Dictionary:
	return {"name": "Bot %d" % index, "avatar": index % 3, "portrait": "", "mode": "saved", "deckId": ""}

static func read() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(path()) == OK:
		var value = config.get_value("match", "players", {})
		# An online table can be saved with no bots; an offline game adds one back when it starts.
		if value is Dictionary and value.has("human") and value.get("bots") is Array and value.bots.size() <= 3: return value
	return defaults()

static func last_server() -> String:
	var config := ConfigFile.new()
	return str(config.get_value("online", "server", "")) if config.load(_online_path()) == OK else ""

static func save_last_server(address: String) -> void:
	var config := ConfigFile.new()
	config.set_value("online", "server", address)
	config.save(_online_path())

static func _online_path() -> String:
	return path().get_base_dir().path_join("online-session.cfg")

static func save(value: Dictionary) -> Error:
	var config := ConfigFile.new()
	config.set_value("match", "players", value)
	return config.save(path())
