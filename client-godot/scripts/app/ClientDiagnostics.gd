extends RefCounted
## Local crash evidence, bounded to two snapshots each for the current and prior
## launch. Enabled only in diagnostic packages; never makes network requests.
var folder := ""
var session := ""
var sequence := 0
var latest: Dictionary = {}
var frame := -1
var activity: Dictionary = {}
var storm_saved := false

func start(ui: Control, directory: String = "user://client-diagnostics") -> void:
	folder = directory
	DirAccess.make_dir_recursive_absolute(folder)
	for name in ["session.json", "snapshot-0.json", "snapshot-1.json", "layout-storm.json"]:
		var current := folder.path_join(name)
		if not FileAccess.file_exists(current): continue
		var previous := folder.path_join("previous-" + name)
		_write_bytes(previous, FileAccess.get_file_as_bytes(current))
		DirAccess.remove_absolute(current)
	session = Time.get_datetime_string_from_system() + "-" + str(OS.get_process_id())
	_write("session.json", {"format": 1, "session": session, "started": Time.get_datetime_string_from_system(), "engine": Engine.get_version_info(), "executable": OS.get_executable_path(), "rendering_method": RenderingServer.get_current_rendering_method(), "rendering_driver": RenderingServer.get_current_rendering_driver_name(), "layout": _layout(ui)})
	for scroll in [ui.board_scroller, ui.stack_scroll, ui.decision_scroll, ui.zone_scroll]:
		if not is_instance_valid(scroll): continue
		_watch(scroll, ui)
		for child in scroll.get_children():
			if child is Control: _watch(child, ui)

func capture(state: Dictionary, ui: Control) -> void:
	sequence += 1
	latest = {"format": 1, "session": session, "sequence": sequence, "time": Time.get_datetime_string_from_system(), "ticks_ms": Time.get_ticks_msec(), "state": state, "layout_before_apply": _layout(ui)}
	_write("snapshot-%d.json" % (sequence % 2), latest)

func record_layout_recovery(scroll: ScrollContainer, ui: Control) -> void:
	storm_saved = true
	_write("layout-storm.json", {"session": session, "time": Time.get_datetime_string_from_system(), "sequence": sequence, "guard_tripped": true, "scroll": str(scroll.get_path()), "layout": _layout(ui)})

func _watch(control: Control, ui: Control) -> void:
	control.resized.connect(_activity.bind(str(control.get_path()), "resized", ui))
	if control is Container:
		control.sort_children.connect(_activity.bind(str(control.get_path()), "sort_children", ui))

func _activity(path: String, event: String, ui: Control) -> void:
	var current_frame := Engine.get_process_frames()
	if current_frame != frame:
		frame = current_frame
		activity.clear()
	var key := path + ":" + event
	activity[key] = int(activity.get(key, 0)) + 1
	if int(activity[key]) == 128 and not storm_saved:
		storm_saved = true
		_write("layout-storm.json", {"session": session, "time": Time.get_datetime_string_from_system(), "frame": frame, "sequence": sequence, "activity": activity, "layout": _layout(ui), "script_stack": get_stack()})

func _layout(ui: Control) -> Dictionary:
	var values := {"table_size": ui.size, "window_size": ui.get_window().size}
	for name in ["board_scroller", "stack_scroll", "decision_scroll", "zone_scroll"]:
		var scroll = ui.get(name)
		if not is_instance_valid(scroll): continue
		var children: Array = []
		for child in scroll.get_children():
			if child is Control:
				children.append({"path": str(child.get_path()), "size": child.size, "minimum": child.custom_minimum_size, "visible": child.visible})
		values[name] = {"size": scroll.size, "visible": scroll.visible, "vertical_bar": scroll.get_v_scroll_bar().visible, "children": children}
	return values

func _write(name: String, data: Dictionary) -> void:
	_write_bytes(folder.path_join(name), JSON.stringify(data).to_utf8_buffer())

func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.flush()
