extends RefCounted

func run() -> void:
	var adapter = load("res://scripts/bridge/LiveAdapter.gd").new()
	var raw := {"type": "state", "protocolVersion": 2, "sessionId": "first", "revision": 8, "me": 42, "game": {"activePlayer": 42, "phaseKey": "COMBAT_DECLARE_ATTACKERS", "phase": "localized name"}, "players": [], "asks": [{"id": 7, "kind": "choose", "options": [], "min": 0, "max": 0}], "stack": [{"id": 42, "sourceId": 90, "text": "Spell"}], "combat": [{"attacker": 90, "defenderId": 0, "defenderKind": "card"}], "revealed": [], "prompt": {"okEnabled": true}, "log": []}
	for id in [0, 42, 71]:
		raw.players.append({"id": id, "name": str(id), "life": 40, "mana": {}, "zones": {"Battlefield": [], "Hand": [{"id": id + 100, "hidden": true}], "Command": [], "Graveyard": [], "Exile": []}})
	adapter.connected = true
	raw.phaseStops = {"42": {"MAIN1": true}, "0": {"MAIN1": false}, "71": {"MAIN1": true}}
	adapter._receive(raw)
	raw.startingToss = {"id": 1, "winnerId": 71, "winnerName": "Opponent", "heads": true, "choosing": true}
	adapter._receive(raw)
	assert(adapter.state.startingToss.winnerSeat == 2 and adapter.state.startingToss.winnerId == 71, "The shared toss must map the winner to the local seat order without changing engine identity")
	var notice: Dictionary = {"id": 1, "stackId": 900, "controller": 71, "controllerName": "Opponent", "source": {"id": 901, "name": "Mortify", "imageKey": "c:Mortify|ACR|1"}, "targets": [{"id": 142, "name": "Your creature", "kind": "card"}]}
	raw.targetedEffects = [notice]
	adapter._receive(raw)
	assert(adapter.state.targetedEffects[0].source.name == "Mortify" and adapter.state.targetedEffects[0].source.owner == 2 and adapter.state.targetedEffects[0].targets[0].id == 142, "Targeted effects must preserve spell identity/card IDs while mapping caster seats")
	assert(adapter.state.phaseStops[0]["Main 1"] and not adapter.state.phaseStops[1]["Main 1"] and adapter.state.phaseStops[2]["Main 1"], "Per-player phase stops must map engine IDs and stable phase keys to the correct table rows")
	assert(adapter.seats == [42, 0, 71], "Engine player IDs must map to UI seats without changing card/stack IDs")
	assert(adapter.state.game.activePlayer == 0 and adapter.state.game.phase == "Declare attackers", "Phase identity must not depend on locale")
	assert(adapter.state.stack[0].id == 42 and adapter.state.combat[0].defenderId == -1, "Player/card/stack namespaces must remain distinct")
	assert(not adapter.state.players[1].zones.Hand[0].has("name"), "Hidden cards must not gain invented visible details")
	adapter.pending = "inflight"
	adapter.pending_revision = 8
	raw.asks = []
	raw.revision = 9
	adapter._receive(raw)
	assert(not adapter.state.connectionReady, "A snapshot cannot unlock an unacknowledged submission")
	adapter._receive({"type": "ack", "protocolVersion": 2, "requestId": "inflight"})
	assert(adapter.state.connectionReady, "Acknowledgment plus newer snapshot must unlock controls")
	adapter.pending = "blocking-click"
	adapter.pending_revision = 8
	adapter.acknowledged = false
	raw.asks = [{"id": 7, "kind": "choose", "options": [], "min": 0, "max": 0}]
	adapter._receive(raw)
	assert(adapter.pending.is_empty() and adapter.state.connectionReady, "A newer blocking decision must be answerable before the original click returns its ack")
	adapter.pending = "answer"
	adapter.pending_answer = 7
	adapter._receive({"type": "ack", "protocolVersion": 2, "requestId": "answer"})
	assert(not adapter.state.connectionReady and adapter.state.asks.size() == 1, "Accepted answers must keep the dialog until authoritative removal")
	raw.revision = 10
	raw.asks = []
	adapter._receive(raw)
	assert(adapter.state.asks.is_empty() and adapter.state.connectionReady, "A full snapshot must remove closed asks")
	raw.revision = 9
	raw.asks = [{"id": 7}]
	adapter._receive(raw)
	assert(adapter.state.asks.is_empty(), "Old snapshots must not resurrect decisions")
	adapter.pending = "stale"
	adapter._receive({"type": "error", "protocolVersion": 2, "requestId": "stale", "message": "State changed"})
	assert(adapter.pending.is_empty() and not adapter.state.connectionReady, "Rejected requests must refresh without replay")
	var resets := [0]
	adapter.session_reset.connect(func(): resets[0] += 1)
	raw.sessionId = "second"
	raw.revision = 1
	raw.asks = []
	adapter._receive(raw)
	assert(resets[0] == 1 and adapter.revision == 1 and adapter.state.asks.is_empty(), "New sessions must clear caches and accept their own revision sequence")
	raw.revision = 2
	raw.pendingDraws = [142]
	adapter._receive(raw)
	assert(adapter.state.players[0].zones.Hand.is_empty() and adapter.state.pendingDraws == [142], "Pending automatic draws must stay out of the visible hand until acknowledged")
	var sent: int = adapter.request_counter
	adapter.send_intent({"action": "ok"})
	assert(adapter.state.drawHint and adapter.request_counter == sent, "An out-of-order action must cue the library without submitting gameplay")
	raw.revision = 3
	raw.pendingDraws = []
	adapter._receive(raw)
	assert(not adapter.state.drawHint and adapter.state.players[0].zones.Hand.size() == 1, "Acknowledged draws must reveal without a duplicate card or lingering cue")
	raw.revision = 4
	raw.undoPending = true
	adapter._receive(raw)
	sent = adapter.request_counter
	adapter.send_intent({"action": "ok"})
	assert(not adapter.state.connectionReady and adapter.request_counter == sent, "An in-progress land undo must block inputs even after request acknowledgement")
	raw.revision = 5
	raw.undoPending = false
	adapter._receive(raw)
	assert(adapter.state.connectionReady, "Completion of the land undo must unlock inputs")
	adapter.prepaid_target = 90
	raw.revision = 6
	raw.prompt.inputKind = "InputPayManaOfCostPayment"
	adapter._receive(raw)
	sent = adapter.request_counter
	adapter.send_intent({"action": "card", "id": 142})
	adapter.send_intent({"action": "ok"})
	assert(not adapter.state.connectionReady and adapter.request_counter == sent, "Automatic payment must block overlapping casts and manual priority passes")
	raw.revision = 7
	raw.asks = [{"id": 8, "kind": "choose", "options": [], "min": 0, "max": 0}]
	adapter._receive(raw)
	assert(adapter.state.connectionReady, "A required choice during a cast must remain answerable")
	raw.revision = 8
	raw.asks = []
	raw.prompt.inputKind = "InputSelectTargets"
	adapter._receive(raw)
	assert(adapter.state.connectionReady, "Targets during a cast must remain selectable")
	adapter.prepaid_target = -1
	adapter._publish()
	var endings := [0]
	adapter.session_ended.connect(func(_message): endings[0] += 1)
	adapter.seat_token = "online-seat"
	adapter.pending = "pending-choice"
	adapter._receive({"type": "sessionEnded", "protocolVersion": 2, "sessionId": "first"})
	assert(not adapter.ended, "A stale session-ended event cannot close the current match")
	var ended := {"type": "sessionEnded", "protocolVersion": 2, "sessionId": "second", "message": "Host ended the game"}
	adapter._receive(ended)
	adapter._receive(ended)
	adapter._receive(raw)
	adapter.poll(1000.0)
	assert(adapter.ended and endings[0] == 1 and adapter.seat_token.is_empty() and adapter.pending.is_empty() and not adapter.state.connectionReady, "Host stop is terminal, clears credentials, and never reconnects or resurrects state")
	var unavailable = load("res://scripts/bridge/LiveAdapter.gd").new()
	unavailable.seat_token = "unreachable-seat"
	unavailable.offline_seconds = unavailable.REMOTE_TIMEOUT_SECONDS - 1.0
	unavailable.poll(2.0)
	assert(unavailable.ended, "An unavailable host cannot leave the client reconnecting forever")
	var restored = load("res://scripts/bridge/LiveAdapter.gd").new()
	restored.seat_token = "saved-seat"
	restored.expected_session = "original-match"
	restored._receive(raw)
	assert(restored.ended and restored.seat_token.is_empty() and restored.state.is_empty(), "Saved credentials cannot restore a different match at the same address")
	await _terminal_departure()
	print("PASS: live adapter recovery and privacy checks")

func _terminal_departure() -> void:
	# The host keeps the socket open until the client reads its terminal notice.
	var listener := TCPServer.new()
	var listen_result := listener.listen(0, "127.0.0.1")
	assert(listen_result == OK)
	var adapter = load("res://scripts/bridge/LiveAdapter.gd").new()
	adapter.url = "ws://127.0.0.1:%d" % listener.get_local_port()
	adapter.seat_token = "test-seat"
	adapter.start()
	var peer: WebSocketPeer
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		adapter.poll(0.01)
		if peer == null and listener.is_connection_available():
			peer = WebSocketPeer.new()
			var accept_result := peer.accept_stream(listener.take_connection())
			assert(accept_result == OK)
		if peer != null:
			peer.poll()
			if peer.get_ready_state() == WebSocketPeer.STATE_OPEN and adapter.connected: break
		await tree.process_frame
	assert(peer != null and adapter.connected, "The terminal-close fixture must connect")
	peer.send_text(JSON.stringify({"type": "sessionEnded", "protocolVersion": 2, "sessionId": "test-session", "message": "The host ended the game."}))
	while Time.get_ticks_msec() < deadline and not adapter.ended:
		peer.poll()
		adapter.poll(0.01)
		await tree.process_frame
	assert(adapter.ended and adapter.seat_token.is_empty(), "The terminal notice must close the session instead of entering reconnect")
	while Time.get_ticks_msec() < deadline and peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		peer.poll()
		await tree.process_frame
	assert(peer.get_ready_state() == WebSocketPeer.STATE_CLOSED, "The host must observe the client's departure after delivering the notice")
	listener.stop()
