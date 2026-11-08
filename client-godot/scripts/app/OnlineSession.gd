extends Node
## The online lobby, shared by the settings screen and the application. A host's lobby lives in the
## library service and is polled; a joined player holds a socket to the host. Once everyone is ready,
## the joined player's seat is an ordinary LiveAdapter connection presenting the seat token.
signal changed
signal notice(text: String)
signal match_started(url: String, token: String)
const NET_VERSION := 5
const DEFAULT_PORT := 36743
const CONNECT_TIMEOUT_MS := 10000
const OFFLINE_ROLE := ""
var api: Node
## "", "hosting", "connecting" or "joined".
var role := OFFLINE_ROLE
var host_status: Dictionary = {}
var roster: Array = []
var open_seats := 0
var you := -1
var last_roster: Array = []
var last_you := -1
var deck_id := ""
var address := ""
var error := ""
var requests: Dictionary = {}
var socket: WebSocketPeer
var server_host := ""
var server_port := DEFAULT_PORT
var connect_deadline := 0
var join_message: Dictionary = {}
var status_timer: Timer
var deck_request := -1

func _ready() -> void:
	status_timer = Timer.new()
	status_timer.wait_time = 1.0
	status_timer.timeout.connect(func(): if is_hosting(): _request("lobby.status"))
	add_child(status_timer)
	if api != null:
		api.response.connect(_response)
		api.failed.connect(_failed)

func is_hosting() -> bool: return role == "hosting"
func is_joined() -> bool: return role == "joined"
func is_idle() -> bool: return role == OFFLINE_ROLE

func is_ready() -> bool:
	if is_hosting(): return host_status.get("hostReady", false)
	return roster.any(func(entry): return entry.get("kind", "") == "player" and int(entry.get("id", -1)) == you and entry.get("ready", false))

func all_ready() -> bool:
	return is_hosting() and host_status.get("allReady", false)

func set_ready(value: bool) -> void:
	if is_hosting(): _request("lobby.ready", {"ready": value})
	elif is_joined() and socket != null and deck_request < 0:
		socket.send_text(JSON.stringify({"type": "ready", "ready": value}))

## Players who have joined this host's lobby.
func players() -> Array: return host_status.get("players", [])

## Everyone at the table for the ready screen: {name, kind (host/bot/player/open), ready, you}.
## Bots never confirm; only humans count toward readiness. The host passes its own profile and bots.
func party(human: Dictionary = {}, bots: Array = []) -> Array:
	var seats: Array = []
	if is_hosting():
		seats.append({"name": str(human.get("name", "HOST")), "kind": "host", "ready": is_ready(), "you": true})
		for bot in bots: seats.append({"name": str(bot.get("name", "BOT")), "kind": "bot", "ready": true, "you": false})
		for player in players(): seats.append({"name": str(player.get("name", "PLAYER")), "kind": "player", "ready": player.get("ready", false), "you": false})
		for index in range(maxi(0, 4 - seats.size())): seats.append({"name": "OPEN SEAT", "kind": "open", "ready": false, "you": false})
	elif is_joined():
		for entry in roster:
			var kind := str(entry.get("kind", "player"))
			seats.append({"name": str(entry.get("name", "PLAYER")), "kind": kind, "ready": kind == "bot" or entry.get("ready", false),
				"you": kind == "player" and int(entry.get("id", -1)) == you})
		for index in range(open_seats): seats.append({"name": "OPEN SEAT", "kind": "open", "ready": false, "you": false})
	return seats

## What the host reads out to friends. The port is left out when it is the one joining assumes.
func share_address() -> String:
	var ip: String = host_status.get("public", "")
	if ip.is_empty(): ip = host_status.get("lan", "")
	if ip.is_empty(): return ""
	return ip if host_status.get("defaultPort", true) else "%s:%d" % [ip, int(host_status.get("port", DEFAULT_PORT))]

func host(config: Dictionary, discover := true) -> void:
	if not is_idle(): return
	error = ""
	_request("lobby.host", {"config": config, "discover": discover})

func configure(config: Dictionary) -> void:
	if is_hosting(): _request("lobby.config", {"config": config})

func kick(id: int) -> void:
	if is_hosting(): _request("lobby.kick", {"id": id})

func stop_hosting() -> void:
	if is_hosting(): _request("lobby.stop")

func library_lost() -> void:
	if is_hosting():
		_become_idle("The connection to Forge was lost, so hosting has stopped.")

## Starts joining: the host must be able to read the deck before it gives up a seat.
func join(text: String, profile: Dictionary, selected_deck: String) -> void:
	if not is_idle(): return
	var parsed := parse_address(text)
	if parsed.is_empty():
		error = "Type the IP address the host gave you."
		changed.emit()
		return
	error = ""
	address = text.strip_edges()
	server_host = parsed.host
	server_port = parsed.port
	deck_id = selected_deck
	join_message = {"type": "join", "version": NET_VERSION, "name": profile.get("name", ""), "avatar": profile.get("avatar", 0), "portrait": profile.get("portrait", "")}
	role = "connecting"
	deck_request = _request("lobby.deckText", {"id": selected_deck})
	changed.emit()

static func parse_address(text: String) -> Dictionary:
	var value := text.strip_edges().trim_prefix("ws://")
	value = value.trim_suffix("/ws").trim_suffix("/")
	if value.is_empty() or " " in value: return {}
	var parts := value.split(":")
	if parts.size() > 2 or parts[0].is_empty(): return {}
	var port := DEFAULT_PORT
	if parts.size() == 2:
		if not parts[1].is_valid_int() or int(parts[1]) < 1 or int(parts[1]) > 65535: return {}
		port = int(parts[1])
	return {"host": parts[0], "port": port}

## The carousel selection follows through to the host while waiting in a lobby.
func set_deck(id: String) -> void:
	if id == deck_id: return
	deck_id = id
	if is_hosting():
		set_ready(false)
	elif is_joined():
		deck_request = _request("lobby.deckText", {"id": id})

## A joined player's portrait change, applied by the host without leaving or losing readiness.
func set_profile(profile: Dictionary) -> void:
	if is_joined() and socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(JSON.stringify({"type": "profile", "avatar": int(profile.get("avatar", 0)), "portrait": str(profile.get("portrait", ""))}))

func leave() -> void:
	if role in ["connecting", "joined"]: _become_idle("")

func _request(operation: String, arguments: Dictionary = {}) -> int:
	if api == null: return -1
	var id: int = api.request(operation, arguments)
	requests[id] = operation
	return id

func _response(id: int, operation: String, result: Dictionary) -> void:
	if not requests.has(id): return
	requests.erase(id)
	match operation:
		"lobby.host", "lobby.config", "lobby.kick", "lobby.status", "lobby.stop", "lobby.ready":
			_host_status(result)
		"lobby.deckText":
			if id != deck_request: return
			deck_request = -1
			if role == "connecting":
				join_message.deckData = result.get("deckData", "")
				_open_socket()
			elif is_joined() and socket != null:
				socket.send_text(JSON.stringify({"type": "deck", "deckData": result.get("deckData", "")}))

func _failed(id: int, message: String) -> void:
	if not requests.has(id): return
	var operation: String = requests[id]
	requests.erase(id)
	if operation == "lobby.deckText":
		if id != deck_request: return
		deck_request = -1
	if operation == "lobby.status": return
	if operation == "lobby.deckText" and role == "connecting":
		_become_idle(message)
		return
	error = message
	notice.emit(message)
	changed.emit()

func _host_status(result: Dictionary) -> void:
	var hosting: bool = result.get("hosting", false)
	if hosting and not is_hosting():
		role = "hosting"
		status_timer.start()
	elif not hosting and is_hosting():
		role = OFFLINE_ROLE
		status_timer.stop()
	host_status = result if hosting else {}
	changed.emit()

func _open_socket() -> void:
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 8 * 1024 * 1024
	# A join carries a whole deck and a portrait, well over the 64 KiB default.
	socket.outbound_buffer_size = 2 * 1024 * 1024
	connect_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	if socket.connect_to_url("ws://%s:%d/ws" % [server_host, server_port]) != OK:
		_become_idle("That address could not be used. Check the IP the host gave you.")

func _process(_delta: float) -> void:
	if socket == null: return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and role == "connecting" and not join_message.is_empty():
		socket.send_text(JSON.stringify(join_message))
		join_message = {}
	# The host closes the lobby right after sending "start", so read before reacting to a close.
	while socket != null and socket.get_available_packet_count() > 0:
		var message = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if message is Dictionary: _lobby_message(message)
	if socket == null or state == WebSocketPeer.STATE_OPEN: return
	if state == WebSocketPeer.STATE_CLOSED:
		_become_idle("Could not reach that host. Check the IP, and that the host's port is open." if role == "connecting" else "The connection to the host was lost.")
	elif role == "connecting" and Time.get_ticks_msec() > connect_deadline:
		_become_idle("Could not reach that host. Check the IP, and that the host's port is open.")

func _lobby_message(message: Dictionary) -> void:
	match message.get("type", ""):
		"lobby":
			role = "joined"
			roster = message.get("roster", [])
			open_seats = int(message.get("open", 0))
			you = int(message.get("you", -1))
			error = ""
			changed.emit()
		"rejected":
			if is_joined():
				error = message.get("message", "The host refused that request.")
				notice.emit(error)
				changed.emit()
			else: _become_idle(message.get("message", "The host refused to seat you."))
		"closed":
			_become_idle(message.get("message", "The host closed the session."))
		"start":
			var url := "ws://%s:%d/ws" % [server_host, int(message.get("port", server_port))]
			var token: String = message.get("token", "")
			last_roster = roster.duplicate(true)
			last_you = you
			_become_idle("")
			match_started.emit(url, token)

func _become_idle(message: String) -> void:
	if socket != null: socket.close()
	socket = null
	role = OFFLINE_ROLE
	status_timer.stop()
	host_status = {}
	roster = []
	join_message = {}
	deck_request = -1
	error = message
	if not message.is_empty(): notice.emit(message)
	changed.emit()
