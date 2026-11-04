extends RefCounted

func run(path: String) -> void:
	var helper = preload("res://scripts/app/RemoteSession.gd").new()
	helper.path = path
	helper.clear()
	assert(helper.read().is_empty(), "Absent seat files are ignored")
	var value := {"url": "ws://127.0.0.1:36743/ws", "token": "fixture-only", "session_id": "", "deck": {"id": "fixture", "name": "Fixture deck"}, "info": {"reconnect": true}}
	assert(helper.save(value) == OK, "Seat save succeeds")
	var fresh = preload("res://scripts/app/RemoteSession.gd").new()
	fresh.path = path
	assert(fresh.read() == value, "Fresh helpers read saved seats")
	value.session_id = "fixture-match"
	assert(fresh.save(value) == OK and helper.read() == value, "Replacing an existing file works on this platform")
	assert(not FileAccess.file_exists(path + ".tmp"), "Successful replacement leaves no temp file")
	fresh.clear()
	assert(helper.read().is_empty(), "Deletion is visible across instances")
	value.url = "https://invalid.example"
	assert(helper.save(value) == OK and fresh.read().is_empty(), "Invalid endpoints are ignored")
	helper.clear()
	print("PASS: remote session persistence")
