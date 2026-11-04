extends RefCounted

func run(ui: Control) -> void:
	var log := preload("res://scripts/app/FormatLog.gd").new()
	ui.add_child(log)
	var stopped := [false]
	log.begin_format({"name": "Atraxa", "turn": 7, "phase": "Main 1", "life": 32}, func(): return stopped[0])
	log.set_process(false)
	log.hide()
	var pulses := [0]
	log.activity.connect(func(): pulses[0] += 1)
	for frame in range(360): log._process(1.0 / 60)
	assert(log.rows[0] == "FORMAT A: ATRAXA" and log.rows[1] == "ERASING TURN 7 / MAIN 1 / LIFE 32", "Format metadata is authoritative and uppercase")
	assert(log.done_count == 3 and log.value < 1 and not log.complete, "The final OK and full meter wait for real cleanup")
	stopped[0] = true
	for frame in range(120): log._process(1.0 / 60)
	assert(log.complete and log.value == 1 and log.ready_age >= 0.65 and pulses[0] > 8, "Cleanup releases delayed OK, meter, final hold and log-synchronized LED pulses")
	log.begin_format({}, func(): return false)
	log.set_process(false)
	for frame in range(660): log._process(1.0 / 60)
	assert(log.cleanup_timed_out and log.complete and log.value == 1, "An explicit warned timeout finishes presentation if cleanup is slow")
	log.stop()
	log.queue_free()
	await ui.get_tree().process_frame
	print("PASS: format session metadata, real cleanup gate, timeout, meter, hold and LED pulses")
