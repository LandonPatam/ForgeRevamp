extends RefCounted

## Online lobby ready screen: who is ready, who we wait for, from the host's and a joiner's view.
func run(ui: Control, directory: String = "") -> void:
	var net = preload("res://scripts/app/OnlineSession.gd").new()
	net.role = "hosting"
	net.host_status = {"hostReady": true, "players": [{"id": 2, "name": "Kleen", "ready": false}, {"id": 3, "name": "Mags", "ready": true}]}
	var party: Array = net.party({"name": "Landon"}, [{"name": "AI 1"}])
	assert(party.map(func(seat): return seat.kind) == ["host", "bot", "player", "player"], "Host sees itself, its bots and joined players")
	assert(party[0].you and party[0].ready and party[1].ready and not party[2].ready, "Bots never need confirmation")
	net.role = "joined"
	net.you = 2
	net.open_seats = 1
	net.roster = [{"kind": "host", "name": "Landon", "ready": true}, {"kind": "player", "id": 2, "name": "Kleen", "ready": true}, {"kind": "player", "id": 3, "name": "Mags", "ready": false}]
	var joined: Array = net.party()
	assert(joined.size() == 4 and joined[1].you and not joined[0].you and joined[3].kind == "open", "A joiner sees the host, marks itself and lists open seats")
	net.free()

	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.z_index = 140
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(backdrop)
	var console: Control = preload("res://scripts/app/DeckConsole.gd").new()
	backdrop.add_child(console)
	console.position = Vector2(40, 40)
	console.size = Vector2(1024, 744)
	console.present({"name": "Green machine", "legal": true, "sections": {"Commander": [{"name": "Omnath, Locus of Mana"}]}}, 4, false)
	console.set_status("", true, "[READY] WAITING FOR PLAYERS")
	console.set_party(party, true)
	assert(console.lobby_ready and console.is_processing(), "Pressing PLAY in a lobby switches the CRT to the ready screen")
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("ready-screen-waiting.png"))
		var all_ready := party.map(func(seat): return seat.merged({"ready": true}, true))
		console.set_party(all_ready, true)
		await ui._save_frame(directory.path_join("ready-screen-all.png"))
	console.set_party(party, false)
	assert(not console.lobby_ready, "Not ready keeps the normal disk dashboard")
	backdrop.queue_free()
	await ui.get_tree().process_frame
	print("PASS: online ready screen lists ready seats, waiting players and open seats for host and joiner")
