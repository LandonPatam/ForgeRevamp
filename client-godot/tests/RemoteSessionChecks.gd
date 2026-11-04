extends RefCounted

func run(path: String) -> void:
	var store = preload("res://scripts/app/RemoteSession.gd").new()
	store.path = path
	assert(store.read().is_empty(), "No saved credentials means no recovery disk")
	var saved := {"url": "ws://127.0.0.1:36743/ws", "token": "test-seat", "session_id": "original-match", "deck": {"name": "Test deck"}, "info": {"turn": 4}}
	assert(store.save(saved) == OK, "Seat credentials can be persisted")
	var fresh = preload("res://scripts/app/RemoteSession.gd").new()
	fresh.path = path
	assert(fresh.read() == saved, "A new store instance recovers credentials from disk")
	saved.info.turn = 5
	assert(fresh.save(saved) == OK and store.read().info.turn == 5, "Atomic replacement updates an existing save")
	assert(not FileAccess.file_exists(path + ".tmp"), "Completed writes leave no temporary credential copy")
	fresh.clear()
	assert(store.read().is_empty(), "Leaving or ending removes recovery across instances")
	var invalid := ConfigFile.new()
	invalid.set_value("seat", "version", 1)
	invalid.set_value("seat", "resume", {"url": "file://not-a-host", "token": "test-seat"})
	assert(invalid.save(path) == OK and store.read().is_empty(), "Invalid saved endpoints are ignored")
	store.clear()
	print("PASS: persisted remote-seat recovery, replacement, cleanup and invalid data")
