extends RefCounted
## Local cosmetics keyed by saved deck identity; shared by every floppy view.
const COLORS := [Color("e8bb4f"), Color("e38b51"), Color("d77974"), Color("d76196"), Color("9673bd"), Color("537fbd"), Color("4d9d9a"), Color("6ebba8")]
static var settings: ConfigFile

static func settings_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--floppy-color-settings="): return arg.trim_prefix("--floppy-color-settings=")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--library-fixture="): return arg.trim_prefix("--library-fixture=").path_join("floppy-colors.cfg")
	return "user://deck-floppy-colors.cfg"

static func _settings() -> ConfigFile:
	if settings == null:
		settings = ConfigFile.new()
		settings.load(settings_path())
	return settings

static func default_color(id: String) -> Color:
	return COLORS[posmod(id.hash(), COLORS.size())]

static func color_for(deck: Dictionary) -> Color:
	if deck.get("create", false): return Color("91a8aa")
	var id := str(deck.get("id", ""))
	var saved = _settings().get_value("colors", id, default_color(id))
	return Color(saved.r, saved.g, saved.b, 1.0) if saved is Color else default_color(id)

static func save_color(id: String, color: Color, reset: bool = false) -> Error:
	var config := _settings()
	if reset:
		if config.has_section_key("colors", id): config.erase_section_key("colors", id)
	else: config.set_value("colors", id, Color(color.r, color.g, color.b, 1.0))
	return config.save(settings_path())
