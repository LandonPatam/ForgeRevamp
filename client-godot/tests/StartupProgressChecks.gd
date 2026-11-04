extends RefCounted

func run(ui: Control) -> void:
	var screen := preload("res://scripts/app/StartupScreen.gd").new()
	ui.add_child(screen)
	screen.hide()
	screen.set_process(false)
	screen.present("Loading Forge", "Loading rules", "cards")
	var previous := 0.0
	for frame in range(1800):
		screen._process(1.0 / 60.0)
		assert(screen.progress.value >= previous and screen.progress.value - previous <= 0.22 / 60.0 + 0.00001, "Estimated loading must advance smoothly and never move backwards")
		previous = screen.progress.value
	assert(screen.progress.value > 0.4 and screen.progress.value < 0.72 and screen.stage_index == 1, "Long Forge startup must visibly advance beyond 8% without marking later services ready")
	screen._process(10000)
	assert(screen.progress.value <= 0.72 and screen.progress.value < 1.0, "Slow startup must remain below its estimate ceiling")
	screen.present("Connecting", "Opening library", "online")
	screen._process(1.0 / 60.0)
	assert(screen.progress.value <= 0.724, "A burst of backend milestones must not jump the displayed percentage")
	screen._process(10000)
	assert(screen.progress.value <= 0.97, "Even an indefinitely slow connection cannot reach 100%")
	screen.present("Complete", "Premature milestone", "complete")
	assert(screen.phase == "connecting" and screen.target < 1.0, "A status label alone cannot authorize completion")
	screen.present("Failed", "Connection lost", "failed")
	var stopped: float = screen.progress.value
	screen._process(10)
	assert(screen.failed and not screen.progress.visible and screen.progress.value == stopped, "Failure must stop estimated progress and retain the failure screen")
	screen.queue_free()
	await ui.get_tree().process_frame
	print("PASS: smooth startup estimates, bounded slow progress, milestone bursts and readiness/failure guards")
