extends RefCounted

## After the host ends a match its lobby reopens on the same port. A joined player goes back in on its
## own: same profile and deck, retrying while the host's port is still closed, and seated not ready.
class FakeLibrary extends Node:
	signal response(id: int, operation: String, result: Dictionary)
	signal failed(id: int, message: String)
	var next := 0
	func request(operation: String, _arguments: Dictionary) -> int:
		next += 1
		var id := next
		(func(): response.emit(id, operation, {"deckData": "1 Forest"})).call_deferred()
		return id

func run(ui: Control, _directory: String = "") -> void:
	var probe := TCPServer.new()
	assert(probe.listen(0, "127.0.0.1") == OK, "A free local port for the fake host")
	var port := probe.get_local_port()
	probe.stop()

	var library := FakeLibrary.new()
	ui.add_child(library)
	var net = preload("res://scripts/app/OnlineSession.gd").new()
	net.api = library
	ui.add_child(net)
	# As if this player had joined and played a match: the session remembers how it joined.
	net.deck_id = "green"
	net.rejoin_info = {"address": "127.0.0.1:%d" % port, "profile": {"name": "Kleen", "avatar": 3, "portrait": ""}}

	assert(net.rejoin_after_match() and net.rejoining(), "The end of the host's match starts a rejoin")
	# The host's match still holds the port: the first attempts are refused, and the rejoin keeps trying.
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 2500: await ui.get_tree().process_frame
	assert(net.rejoining() and net.is_idle() == false, "A closed port while the lobby reopens is retried, not given up")

	var host := TCPServer.new()
	assert(host.listen(port, "127.0.0.1") == OK, "The reopened lobby listens again")
	var peer: WebSocketPeer = null
	var join: Dictionary = {}
	started = Time.get_ticks_msec()
	while join.is_empty() and Time.get_ticks_msec() - started < 8000:
		await ui.get_tree().process_frame
		if peer == null and host.is_connection_available():
			peer = WebSocketPeer.new()
			peer.inbound_buffer_size = 8 * 1024 * 1024
			peer.accept_stream(host.take_connection())
		if peer == null: continue
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var message = JSON.parse_string(peer.get_packet().get_string_from_utf8())
			if message is Dictionary and message.get("type", "") == "join": join = message
	assert(join.get("name", "") == "Kleen" and int(join.get("avatar", -1)) == 3 and join.get("deckData", "") == "1 Forest" and int(join.get("version", 0)) == net.NET_VERSION, "It rejoins with the same profile and deck: " + str(join))
	peer.send_text(JSON.stringify({"type": "lobby", "you": 2, "open": 1, "roster": [{"kind": "host", "name": "Host", "ready": false}, {"kind": "player", "id": 2, "name": "Kleen", "ready": false}]}))
	started = Time.get_ticks_msec()
	while not net.is_joined() and Time.get_ticks_msec() - started < 3000:
		peer.poll()
		await ui.get_tree().process_frame
	assert(net.is_joined() and not net.rejoining() and not net.is_ready(), "Back in the lobby, not ready until PLAY")

	net.leave()
	peer.close()
	host.stop()
	net.queue_free()
	library.queue_free()
	await ui.get_tree().process_frame
	print("PASS: online rejoin after the host's match")
