extends RefCounted

func run(ui: Control) -> void:
	var early := {"players": [{"name": "You"}, {"name": "Bot"}], "connectionReady": true, "prompt": {"inputKind": "InputLockUI"}}
	assert(not ui._table_can_reveal(early, false) and ui._table_can_reveal(early, true), "An initial locked engine snapshot cannot finish a fresh boot; an existing table can resume between actions")
	early.prompt.inputKind = "InputSelectEntitiesFromList"
	assert(ui._table_can_reveal(early, false), "The startup choice is ready after Forge prepares and shuffles its libraries; do not wait for a hidden player decision")
	early.prompt.inputKind = "InputLockUI"
	early.asks = [{"kind": "message", "message": "AI deck warning"}]
	assert(ui._table_can_reveal(early, false), "A required Forge warning during preparation must open the table instead of deadlocking the boot screen")
	var log := preload("res://scripts/app/MatchBootLog.gd").new()
	ui.add_child(log)
	log.hide()
	var deck := {"name": "AtraxaV2", "sections": {"Commander": [{"name": "Atraxa, Praetors' Voice", "quantity": 1}], "Main": [{"name": "Forest", "quantity": 99, "typeLine": "Basic Land"}]}}
	var setup := {"human": {"name": "You"}, "bots": [{"name": "Bot 1"}, {"name": "Bot 2"}, {"name": "Bot 3"}]}
	var pulses := [0]
	log.activity.connect(func(): pulses[0] += 1)
	log.begin(deck, setup)
	log.set_process(false)
	log.hide()
	assert(log.disk_name == "ATRAXAV2" and log.commander == "ATRAXA, PRAETORS' VOICE" and log.card_count == 100 and log.names == "YOU, BOT 1, BOT 2, BOT 3", "Boot metadata comes from the inserted disk and current profiles")
	assert(log.rows.all(func(row): return row == row.to_upper()), "All boot labels are uppercase")
	var text_finished_at := -1.0
	for frame in range(160):
		log._process(0.01)
		if log.printed >= log.rows[0].length() and text_finished_at < 0: text_finished_at = log.elapsed
		if log._ok_lit:
			assert(log.elapsed - text_finished_at >= 0.35, "Dots print before the delayed OK lands")
			break
	for frame in range(1800): log._process(1.0 / 60)
	assert(log.done_count == 3 and not log.complete and log.value <= 0.68, "Elapsed time cannot finish the rules engine stage")
	log.table_ready()
	assert(log.unlocked == 3, "A premature completion signal cannot bypass the engine and seating gates")
	log.engine_ready()
	for frame in range(300): log._process(1.0 / 60)
	assert(log.done_count == 4, "Engine readiness alone cannot mark players seated")
	log.players_ready([{"name": "Pilot"}, {"name": "Robot"}])
	for frame in range(1800): log._process(1.0 / 60)
	assert(log.names == "PILOT, ROBOT" and log.done_count == 5 and log.value <= 0.96 and not log.complete, "The final line and 100% wait for the actual table, using authoritative player names")
	log.table_ready()
	for frame in range(300): log._process(1.0 / 60)
	assert(log.complete and log.value == 1 and log.ready_age >= 0.65 and pulses[0] > 20, "Ready table completes all lines, the meter, payoff beat and log-synchronized drive activity")
	log.begin(deck, setup, true)
	log.set_process(false)
	assert(log.resuming and log.done_count == 0 and log.value == 0 and log.unlocked == 3, "Session resume resets the log without pretending to start a new match")
	log.fail("Connection lost")
	var stopped: float = log.value
	log._process(1000)
	assert(log.failed == "CONNECTION LOST" and log.value == stopped and not log.complete, "Failure stops progress without reaching READY")
	log.stop()
	log.queue_free()
	await ui.get_tree().process_frame
	print("PASS: match boot metadata, delayed OK, real engine/table readiness gates, progress, drive activity, resume and failure")
