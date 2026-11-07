extends "res://scripts/bridge/StateAdapter.gd"
## One local Forge seat. All mutations use the contextual bridge controller.
const PHASES := {"UNTAP": "Untap", "UPKEEP": "Upkeep", "DRAW": "Draw", "MAIN1": "Main 1", "COMBAT_BEGIN": "Begin combat", "COMBAT_DECLARE_ATTACKERS": "Declare attackers", "COMBAT_DECLARE_BLOCKERS": "Declare blockers", "COMBAT_FIRST_STRIKE_DAMAGE": "First strike damage", "COMBAT_DAMAGE": "Combat damage", "COMBAT_END": "End combat", "MAIN2": "Main 2", "END_OF_TURN": "End step", "CLEANUP": "Cleanup"}
var url := "ws://127.0.0.1:7777/ws"
## An online seat presents this on every connection; the host's own table needs none.
var seat_token := ""
## A restored client may reconnect only to the match that issued its saved seat.
var expected_session := ""
var absent_players: Array = []
var socket := WebSocketPeer.new()
var state: Dictionary = {}
var session := ""
var revision := -1
var seats: Array = []
var connected := false
var syncing := true
var retry_in := 0.0
var request_counter := 0
var last_card_intent := -1
var pending := ""
var pending_revision := -1
var pending_answer := -1
var acknowledged := false
var pending_age := 0.0
var draw_hint := false
var prepaid_target := -1
var prepaid_started := 0
var prepaid_after := 0
var prepaid_tried: Array = []
var prepaid_payment_seen := false
var prepaid_cancelling := false
var equip_source := -1
var equip_target := -1
var equip_target_sent := false
var auto_priority_sent := -1
var auto_priority_candidate := -1
var auto_priority_due := 0
var auto_priority_passes := 0
var auto_priority_request := ""
## Table setting: pass priority on every stack item; Forge still asks for every required decision.
var auto_resolve_all := false
var acknowledged_effects: Array[int] = []
var last_state_text := ""
var sync_wait := 0.0
var ended := false
var offline_seconds := 0.0
const REMOTE_TIMEOUT_SECONDS := 180.0

func start() -> void:
	if ended: return
	socket = WebSocketPeer.new()
	# Full Commander snapshots exceed the 64 KiB default on busy boards.
	socket.inbound_buffer_size = 8 * 1024 * 1024
	connected = false
	syncing = true
	retry_in = 2.0
	last_state_text = ""
	status_changed.emit("CONNECTING TO FORGE")
	var result := socket.connect_to_url(url)
	if result != OK:
		status_changed.emit("FORGE OFFLINE / retrying")
	_publish()

func poll(delta: float) -> void:
	if ended: return
	if not seat_token.is_empty():
		offline_seconds = offline_seconds + delta if not connected or syncing else 0.0
		if offline_seconds >= REMOTE_TIMEOUT_SECONDS:
			_finish_session("The host is no longer available. The online session has closed.")
			return
	socket.poll()
	var ready := socket.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN and not connected:
		connected = true
		syncing = true
		if not seat_token.is_empty(): socket.send_text(JSON.stringify({"type": "auth", "token": seat_token}))
		_hello()
	# A terminal message and close frame can arrive in one poll. Drain queued
	# frames even after STATE_CLOSED, before deciding whether to reconnect.
	while socket.get_available_packet_count() > 0:
		var text := socket.get_packet().get_string_from_utf8()
		if text == last_state_text and not state.is_empty():
			_receive_duplicate_state()
			continue
		var message = JSON.parse_string(text)
		if message is Dictionary:
			if message.get("type", "") == "state": sync_wait = 0.0
			_receive(message)
			if ended: return
			if message.get("type", "") == "state" and not syncing and int(message.get("revision", -1)) == revision:
				last_state_text = text
	if ready == WebSocketPeer.STATE_OPEN:
		# Snapshots follow every reported change; re-request only if one never arrives.
		sync_wait = sync_wait + delta if syncing else 0.0
		if sync_wait > 1.5:
			sync_wait = 0.0
			_hello()
		if not pending.is_empty():
			pending_age += delta
			if pending_age > 12:
				_clear_pending()
				syncing = true
				feedback.emit("No confirmation received. Refreshing Forge state; the action will not be replayed.")
				_hello()
				_publish()
		_service_prepaid()
		_service_equip()
		_service_effect_acknowledgment()
		_service_auto_priority()
	elif ready == WebSocketPeer.STATE_CLOSED:
		if connected:
			connected = false
			syncing = true
			_clear_pending()
			prepaid_target = -1
			draw_hint = false
			status_changed.emit("FORGE OFFLINE / retrying")
			_publish()
		retry_in -= delta
		if retry_in <= 0:
			start()

func _hello() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify({"type": "hello"}))

## Gives this online seat up for good, so the rest of the table is not left waiting for a reconnect.
func leave_table() -> void:
	if ended: return
	ended = true
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify({"type": "leave"}))
		socket.close()
		socket.poll()

func _finish_session(message: String) -> void:
	if ended: return
	ended = true
	connected = false
	syncing = true
	_clear_pending()
	prepaid_target = -1
	equip_source = -1
	equip_target = -1
	absent_players.clear()
	seat_token = ""
	socket.close()
	socket.poll()
	_publish()
	session_ended.emit(message)

func _note_absent(names: Array) -> void:
	if names == absent_players: return
	var returned := absent_players.filter(func(player): return not names.has(player))
	absent_players = names.duplicate()
	if not names.is_empty(): feedback.emit("Waiting for %s to reconnect..." % ", ".join(names))
	elif not returned.is_empty(): feedback.emit("%s reconnected." % ", ".join(returned))

func _receive_duplicate_state() -> void:
	# Byte-identical to the applied snapshot: reuse it instead of normalizing again.
	var was_pending := pending
	if state.pendingDraws.is_empty():
		draw_hint = false
	_unlock()
	if syncing or pending != was_pending:
		syncing = false
		status_changed.emit("FORGE CONNECTED")
		_publish()

func _receive(message: Dictionary) -> void:
	if ended: return
	if int(message.get("protocolVersion", -1)) != 2:
		syncing = true
		status_changed.emit("UNSUPPORTED BRIDGE PROTOCOL")
		_publish()
		return
	var kind: String = message.get("type", "")
	if kind == "sessionEnded":
		if not session.is_empty() and message.get("sessionId", "") != session: return
		_finish_session(message.get("message", "The host ended the game."))
		return
	if kind == "state":
		if message.get("loading", false):
			syncing = true
			status_changed.emit("FORGE LOADING")
			_publish()
			return
		var next_session: String = message.get("sessionId", "")
		if next_session.is_empty():
			return
		if not expected_session.is_empty() and next_session != expected_session:
			_finish_session("This online game is no longer available.")
			return
		if next_session != session:
			session = next_session
			equip_source = -1
			equip_target = -1
			equip_target_sent = false
			acknowledged_effects.clear()
			auto_priority_sent = -1
			auto_priority_candidate = -1
			auto_priority_request = ""
			revision = -1
			state.clear()
			_clear_pending()
			prepaid_target = -1
			draw_hint = false
			session_reset.emit()
		if int(message.revision) < revision:
			return
		var normalized := normalize(message)
		if normalized.is_empty():
			syncing = true
			status_changed.emit("LIVE TABLE REQUIRES 3 PLAYERS / start with --opponents 2")
			_publish()
			return
		revision = int(message.revision)
		state = normalized
		offline_seconds = 0.0
		_note_absent(message.get("absentPlayers", []))
		if state.pendingDraws.is_empty():
			draw_hint = false
		syncing = false
		_unlock()
		status_changed.emit("FORGE CONNECTED")
		_publish()
	elif kind in ["ask", "askClosed"]:
		# A full snapshot replaces the decision set, including missed closures.
		# The bridge broadcasts one after every ask change; no hello is needed.
		syncing = true
		_publish()
	elif kind == "ack" and message.get("requestId", "") == pending:
		acknowledged = true
		prepaid_after = Time.get_ticks_msec() + 160
		_unlock()
		_publish()
	elif kind == "error":
		if message.get("requestId", "") == pending and last_card_intent >= 0:
			action_rejected.emit(last_card_intent)
		prepaid_target = -1
		equip_source = -1
		equip_target = -1
		if message.get("requestId", "") == pending and pending == auto_priority_request:
			auto_priority_sent = -1
			auto_priority_candidate = -1
			auto_priority_request = ""
		if message.get("requestId", "") == pending:
			_clear_pending()
		syncing = true
		feedback.emit(message.get("message", "Forge rejected the request"))
		_hello()
		_publish()
	elif kind == "flash":
		if last_card_intent >= 0: action_rejected.emit(last_card_intent)
		feedback.emit("Forge cannot use that selection here. Follow the current prompt.")

func _clear_pending() -> void:
	pending = ""
	pending_answer = -1
	acknowledged = false
	pending_age = 0
	if not connected or syncing:
		equip_source = -1
		equip_target = -1

func _unlock() -> void:
	# A blocking UI callback can run inside the click handler, before its ack.
	# A newer authoritative ask proves that click reached its decision boundary.
	if not pending.is_empty() and pending_answer < 0 and revision > pending_revision and not state.get("asks", []).is_empty():
		_clear_pending()
		return
	if not acknowledged or state.is_empty():
		return
	if pending_answer >= 0:
		if not state.asks.any(func(ask): return int(ask.id) == pending_answer):
			_clear_pending()
	elif revision > pending_revision:
		_clear_pending()

func _publish() -> void:
	if state.is_empty():
		return
	state.connectionReady = connected and not syncing and pending.is_empty() and not state.get("undoPending", false)
	var automatic_payment: bool = prepaid_target >= 0 and state.asks.is_empty() and state.prompt.get("inputKind", "") in ["InputPassPriority", "InputPayManaOfCostPayment"]
	state.connectionReady = state.connectionReady and not automatic_payment
	state.drawHint = draw_hint and not state.get("pendingDraws", []).is_empty()
	state.availableActions.draw = state.connectionReady and not state.get("pendingDraws", []).is_empty() and state.asks.is_empty()
	var visible_state := state.duplicate(true)
	visible_state.pendingCastId = prepaid_target
	visible_state.pendingEquipId = equip_source
	visible_state.autoResolveAll = auto_resolve_all
	if prepaid_target >= 0:
		# A card being paid for is provisional, not yet a committed stack item.
		visible_state.autoPassStackId = -1
	state_changed.emit(visible_state)

func send_intent(intent: Dictionary) -> void:
	var action: String = intent.get("action", "")
	if not state.is_empty() and not state.get("pendingDraws", []).is_empty() and not action in ["draw", "refresh", "phase_stop", "phase_stops", "answer"]:
		draw_hint = true
		_publish()
		feedback.emit("Take your draw from the library first.")
		return
	if action == "draw":
		if state.is_empty() or state.get("pendingDraws", []).is_empty():
			return
		intent = intent.duplicate()
		intent.id = int(state.pendingDraws[0])
		action = "draw_ack"
	if action == "return_to_hand":
		var allowed: bool = not state.is_empty() and state.players[0].zones.Battlefield.any(func(card): return int(card.id) == int(intent.id) and card.get("availableActions", {}).get("returnToHand", false))
		allowed = allowed or (int(state.get("takebackCast", {}).get("id", -1)) == int(intent.id) and state.get("takebackCast", {}).get("availableActions", {}).get("returnToHand", false))
		if not allowed:
			feedback.emit("That card's play can no longer be undone.")
			return
		action = "undo_card"
	if action == "refresh":
		syncing = true
		_hello()
		_publish()
		return
	if action == "phase_stops":
		return # Mock bulk settings are not replayed into live matches; use phase_stop edits.
	if state.is_empty() or not connected or syncing or not pending.is_empty() or state.get("undoPending", false):
		return
	if prepaid_target >= 0 and state.asks.is_empty() and state.prompt.get("inputKind", "") in ["InputPassPriority", "InputPayManaOfCostPayment"] and not action in ["mana", "cancel", "answer", "phase_stop"]:
		return # Finish/refund this cast before accepting another gameplay action.
	var request := {"protocolVersion": 2, "sessionId": session, "revision": revision}
	if action == "answer":
		if not state.asks.any(func(ask): return int(ask.id) == int(intent.id)):
			return
		request.merge({"type": "answer", "id": int(intent.id), "value": intent.get("value")})
		pending_answer = int(intent.id)
	else:
		if (not state.asks.is_empty() and action != "phase_stop") or not action in ["ok", "cancel", "card", "equip", "player", "attack", "undeclare", "phase_stop", "stack", "mana", "undo", "undo_card", "undo_tap", "draw_ack", "pass_turn"]:
			return
		if action in ["ok", "cancel"] and not state.prompt.get(action + "Enabled", false):
			return
		request.merge({"type": "action", "action": action})
		if action == "equip":
			equip_source = int(intent.id)
			equip_target = int(intent.target)
			equip_target_sent = false
			prepaid_tried.clear()
			request.target = equip_target
		if action == "cancel":
			equip_source = -1
			equip_target = -1
		if action == "card" and equip_source >= 0 and state.prompt.get("inputKind", "") == "InputPayManaOfCostPayment":
			prepaid_tried.clear()
		if action == "phase_stop":
			request.phase = str(intent.get("phase", ""))
			request.enabled = bool(intent.get("enabled", true))
		if action == "attack":
			var target := int(intent.get("target", -1))
			if target <= 0 or target >= seats.size():
				return
			request.target = seats[target]
		if action == "card" and intent.has("id") and state.prompt.get("inputKind", "") == "InputPassPriority":
			var castable: Array = state.players[0].zones.Hand + state.players[0].zones.Command + state.players[0].zones.Graveyard + state.players[0].zones.Exile
			if castable.any(func(card): return int(card.id) == int(intent.id) and not card.get("typeLine", "").contains("Land")):
				prepaid_target = int(intent.id)
				prepaid_started = Time.get_ticks_msec()
				prepaid_after = prepaid_started + 160
				prepaid_tried.clear()
				prepaid_payment_seen = false
				prepaid_cancelling = false
		if intent.has("id"):
			request.id = int(intent.id)
			if action in ["player", "phase_stop"]:
				if request.id < 0 or request.id >= seats.size():
					return
				request.id = seats[request.id]
	request_counter += 1
	last_card_intent = int(intent.get("id", -1)) if action in ["card", "attack", "undeclare"] else -1
	pending = "godot-" + str(Time.get_ticks_usec()) + "-" + str(request_counter)
	request.requestId = pending
	pending_revision = revision
	pending_age = 0
	acknowledged = false
	if socket.send_text(JSON.stringify(request)) != OK:
		_clear_pending()
		syncing = true
		feedback.emit("Connection lost before submission. Review the refreshed state.")
	_publish()

func _service_equip() -> void:
	if equip_source < 0 or state.is_empty() or not connected or syncing or not pending.is_empty() or not state.asks.is_empty(): return
	var kind: String = state.prompt.get("inputKind", "")
	if kind == "InputSelectTargets" and not equip_target_sent:
		if state.prompt.get("selectable", []).any(func(id): return int(id) == equip_target):
			equip_target_sent = true
			send_intent({"action": "card", "id": equip_target})
		else:
			equip_source = -1
			equip_target = -1
	elif kind == "InputSelectTargets" and equip_target_sent and state.prompt.get("okEnabled", false):
		send_intent({"action": "ok"})
	elif kind == "InputPayManaOfCostPayment":
		# Spend only the existing pool. An incomplete payment stays open so the
		# player can add mana from the board or cancel through Forge's controls.
		for i in range(6):
			var color: String = ["W", "U", "B", "R", "G", "C"][i]
			var count := int(state.players[0].mana.get(color, 0))
			var attempt := color + ":" + str(count)
			if count > 0 and not prepaid_tried.has(attempt):
				prepaid_tried.append(attempt)
				send_intent({"action": "mana", "id": [1, 2, 4, 8, 16, 0][i]})
				return
	elif kind == "InputPassPriority" and equip_target_sent:
		equip_source = -1
		equip_target = -1

func normalize(raw: Dictionary) -> Dictionary:
	var players: Array = raw.get("players", [])
	if players.size() < 2 or players.size() > 4 or not players.any(func(p): return int(p.id) == int(raw.me)):
		return {}
	# One deep copy keeps the caller's message intact; everything below edits the copy in place.
	var result := raw.duplicate(true)
	players = result.players
	var ordered: Array = players.filter(func(p): return int(p.id) == int(raw.me))
	ordered.append_array(players.filter(func(p): return int(p.id) != int(raw.me)))
	seats = ordered.map(func(p): return int(p.id))
	result.mode = "live"
	result.me = 0
	result.players = []
	result.availableActions = {"draw": false}
	if raw.has("phaseStops"):
		result.phaseStops = {}
		for seat in range(seats.size()):
			result.phaseStops[seat] = {}
			for key in raw.phaseStops.get(str(seats[seat]), {}):
				result.phaseStops[seat][PHASES.get(key, key)] = raw.phaseStops[str(seats[seat])][key]
	result.pendingDraws = raw.get("pendingDraws", []).map(func(id): return int(id))
	result.game.activePlayer = seats.find(int(raw.game.activePlayer))
	if result.has("startingToss"):
		result.startingToss.winnerSeat = seats.find(int(result.startingToss.winnerId))
	result.game.turn = int(raw.game.get("turn", 0))
	result.game.phase = PHASES.get(raw.game.get("phaseKey", ""), raw.game.get("phase", ""))
	for seat in range(ordered.size()):
		var p: Dictionary = ordered[seat]
		p.engineId = int(p.id)
		p.id = seat
		p.life = int(p.get("life", 0))
		p.libraryCount = int(p.get("libraryCount", 0))
		p.handCount = int(p.get("handCount", 0))
		p.color = ["G", "U", "R", "W"][seat]
		p.initials = str(p.name).substr(0, 2).to_upper()
		for zone in p.zones:
			p.zones[zone] = p.zones[zone].map(func(c): return _card(c, seat, zone))
		if seat == 0:
			p.zones.Hand = p.zones.Hand.filter(func(card): return not result.pendingDraws.has(card.id))
			p.handCount -= result.pendingDraws.size()
			p.libraryCount += result.pendingDraws.size()
		result.players.append(p)
	for item in result.stack:
		item.id = int(item.id)
		item.sourceId = int(item.get("sourceId", -1))
		if item.has("card"): item.card = _card(item.card, seats.find(int(item.get("controller", -1))), "Stack")
	for entry in result.combat:
		entry.attacker = int(entry.attacker)
		entry.blockers = entry.get("blockers", []).map(func(id): return int(id))
		if entry.get("defenderKind", "") == "player":
			entry.defenderId = seats.find(int(entry.get("defenderId", -1)))
		else:
			# Card and player IDs belong to distinct namespaces.
			entry.defenderCardId = int(entry.get("defenderId", -1))
			entry.defenderId = -1
	result.asks = result.get("asks", [])
	result.targetedEffects = result.get("targetedEffects", [])
	for effect in result.targetedEffects:
		effect.id = int(effect.id)
		effect.stackId = int(effect.stackId)
		effect.source = _card(effect.source, seats.find(int(effect.get("controller", -1))), "Stack")
	for ask in result.asks:
		ask.id = int(ask.id)
		ask.mode = "live"
	result.revealed = result.get("revealed", []).map(func(c): return _card(c, -1, "Revealed"))
	if result.has("takebackCast"):
		result.takebackCast = _card(result.takebackCast, 0, "Stack")
	result.prompt.cards = result.prompt.get("cards", []).map(func(c): return _card(c, -1, "Selection"))
	result.prompt.entities = result.prompt.get("entities", [])
	for entity in result.prompt.entities:
		if entity.kind == "player":
			entity.engineId = int(entity.id)
			entity.id = seats.find(int(entity.id))
		if entity.has("card"): entity.card = _card(entity.card, -1, "Selection")
	return result

func _service_prepaid() -> void:
	if prepaid_target < 0 or state.is_empty() or not connected or syncing or not pending.is_empty() or Time.get_ticks_msec() < prepaid_after or not state.asks.is_empty():
		return
	var input_kind: String = state.prompt.get("inputKind", "")
	if input_kind == "InputPayManaOfCostPayment":
		if prepaid_cancelling: return
		prepaid_payment_seen = true
		if state.prompt.has("cardId") and int(state.prompt.cardId) != prepaid_target:
			return
		var colors := ["W", "U", "B", "R", "G", "C"]
		var codes := [1, 2, 4, 8, 16, 0]
		for i in range(colors.size()):
			var count := int(state.players[0].mana.get(colors[i], 0))
			# Retry a color after its count decreases; Forge decides whether each
			# individual floating mana can pay the current cost/restrictions.
			var attempt: String = colors[i] + ":" + str(count)
			if count > 0 and not prepaid_tried.has(attempt):
				prepaid_tried.append(attempt)
				send_intent({"action": "mana", "id": codes[i]})
				return
		if state.prompt.get("cancelEnabled", false):
			prepaid_cancelling = true
			send_intent({"action": "cancel"})
			feedback.emit("The floating mana could not pay that cost. Returning the card.")
	elif input_kind == "InputPassPriority" and (prepaid_payment_seen or Time.get_ticks_msec() - prepaid_started > 900):
		prepaid_target = -1
		_publish()

func acknowledge_effect(stack_id: int) -> void:
	# Bind the user's explicit OK to this effect, never to a later stack item.
	if stack_id < 0 or not state.get("stack", []).any(func(item): return int(item.id) == stack_id): return
	if not acknowledged_effects.has(stack_id): acknowledged_effects.append(stack_id)
	_service_effect_acknowledgment()

func _service_effect_acknowledgment() -> void:
	if acknowledged_effects.is_empty(): return
	var stack: Array = state.get("stack", [])
	acknowledged_effects.assign(acknowledged_effects.filter(func(id): return stack.any(func(item): return int(item.id) == id)))
	if acknowledged_effects.is_empty(): return
	if not connected or syncing or not pending.is_empty() or prepaid_target >= 0: return
	if not state.get("connectionReady", false) or state.get("undoPending", false) or state.get("game", {}).get("gameOver", false): return
	if not state.get("asks", []).is_empty() or not state.get("pendingDraws", []).is_empty(): return
	if not acknowledged_effects.has(int(stack[0].id)): return
	var prompt: Dictionary = state.get("prompt", {})
	if prompt.get("inputKind", "") != "InputPassPriority" or not prompt.get("okEnabled", false): return
	acknowledged_effects.erase(int(stack[0].id))
	send_intent({"action": "ok"})

static func is_automatic_cast(state_value: Dictionary) -> bool:
	return not state_value.get("takebackCast", {}).is_empty() and not state_value.get("stack", []).is_empty() and int(state_value.get("autoPassStackId", -1)) == int(state_value.stack[0].id)

static func is_automatic_stack(state_value: Dictionary) -> bool:
	return not state_value.get("stack", []).is_empty() and int(state_value.get("autoPassStackId", -1)) == int(state_value.stack[0].id) and state_value.get("prompt", {}).get("inputKind", "") == "InputPassPriority" and state_value.get("asks", []).is_empty() and state_value.get("pendingDraws", []).is_empty()

## Auto-resolve still stops for the stack top when it targets this seat's things or is a board
## wipe AND Forge found a legal response (with none, the bridge already marks it autoPassStackId).
static func holds_for_response(state_value: Dictionary) -> bool:
	var stack: Array = state_value.get("stack", [])
	if stack.is_empty() or int(state_value.get("autoPassStackId", -1)) == int(stack[0].id): return false
	if stack[0].get("targetsLocal", false): return true
	return state_value.get("targetedEffects", []).any(func(event): return int(event.get("stackId", -1)) == int(stack[0].id) and event.get("kind", "") == "massRemoval")

## Auto-resolve everything else: any stack item at plain priority, never a decision, draw or your
## own just-cast spell's undo window (that keeps its existing commit behavior).
static func can_resolve_all(state_value: Dictionary) -> bool:
	return not holds_for_response(state_value) and state_value.get("connectionReady", false) and not state_value.get("game", {}).get("gameOver", false) and state_value.get("asks", []).is_empty() and state_value.get("pendingDraws", []).is_empty() and state_value.get("prompt", {}).get("inputKind", "") == "InputPassPriority" and state_value.get("prompt", {}).get("okEnabled", false) and not state_value.get("stack", []).is_empty() and state_value.get("takebackCast", {}).is_empty()

static func can_auto_pass(state_value: Dictionary) -> bool:
	if not state_value.get("takebackCast", {}).is_empty() and not is_automatic_cast(state_value):
		return false # Unclassified effects retain their decision window.
	return state_value.get("connectionReady", false) and not state_value.get("game", {}).get("gameOver", false) and state_value.get("asks", []).is_empty() and state_value.get("pendingDraws", []).is_empty() and state_value.get("prompt", {}).get("inputKind", "") == "InputPassPriority" and state_value.get("prompt", {}).get("okEnabled", false) and not state_value.get("stack", []).is_empty() and int(state_value.get("autoPassStackId", -1)) == int(state_value.stack[0].id)

func _service_auto_priority() -> void:
	if state.get("stack", []).is_empty():
		auto_priority_sent = -1
	elif int(state.stack[0].id) != auto_priority_sent:
		# A response creates a new priority cycle for the original effect.
		auto_priority_sent = -1
	if prepaid_target >= 0 or not connected or syncing or not pending.is_empty() or not (can_auto_pass(state) or (auto_resolve_all and can_resolve_all(state))):
		auto_priority_candidate = -1
		return
	var stack_id := int(state.stack[0].id)
	if auto_priority_sent == stack_id:
		return
	if auto_priority_candidate != stack_id:
		auto_priority_candidate = stack_id
		auto_priority_due = Time.get_ticks_msec() + 160
		return
	if Time.get_ticks_msec() >= auto_priority_due:
		auto_priority_sent = stack_id
		auto_priority_passes += 1
		send_intent({"action": "ok"})
		auto_priority_request = pending

func _card(raw: Dictionary, owner: int, zone: String) -> Dictionary:
	if raw.get("hidden", false):
		return {"id": int(raw.id), "hidden": true, "owner": owner, "zone": zone, "mode": "live"}
	var card := raw # normalize already owns a private copy of every card
	card.id = int(card.id)
	card.owner = owner
	card.zone = zone
	card.mode = "live"
	card.color = "C"
	card.art = "ruins"
	card.stats = str(int(card.power)) + " / " + str(int(card.toughness)) if card.has("power") else (str(int(card.loyalty)) if card.has("loyalty") else "")
	card.availableActions = {"returnToHand": raw.get("availableActions", {}).get("returnToHand", false), "undoTap": raw.get("availableActions", {}).get("undoTap", false)}
	return card
