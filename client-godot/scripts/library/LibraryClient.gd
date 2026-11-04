extends Node
signal connected
signal disconnected
signal response(id: int, operation: String, result: Dictionary)
signal failed(id: int, message: String)
var url := "ws://127.0.0.1:7778/ws"
var socket := WebSocketPeer.new()
var next_id := 0
var pending: Dictionary = {}
var was_open := false
var reconnect_at := 0

func _ready() -> void:
	socket.inbound_buffer_size = 8 * 1024 * 1024
	socket.connect_to_url(url)

func request(operation: String, args: Dictionary = {}) -> int:
	next_id += 1
	var message := args.duplicate(true)
	message.op = operation
	message.requestId = next_id
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		failed.emit.call_deferred(next_id, "The deck library is disconnected. Reconnect before continuing.")
		return next_id
	pending[next_id] = {"op": operation, "time": Time.get_ticks_msec()}
	socket.send_text(JSON.stringify(message))
	return next_id

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not was_open:
			was_open = true
			connected.emit()
		var packet_start := Time.get_ticks_usec()
		while socket.get_available_packet_count() > 0 and Time.get_ticks_usec()-packet_start < 3000:
			var message = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if not message is Dictionary: continue
			var id := int(message.get("requestId", -1))
			if not pending.has(id): continue
			var operation: String = pending[id].op
			pending.erase(id)
			if message.get("ok", false): response.emit(id, operation, message.get("result", {}))
			else: failed.emit(id, message.get("error", "Library operation failed"))
	elif state == WebSocketPeer.STATE_CLOSED:
		if was_open:
			was_open = false
			disconnected.emit()
			var abandoned := pending.keys()
			pending.clear()
			for id in abandoned: failed.emit(id, "Connection lost. Your unsaved changes are still here.")
		if Time.get_ticks_msec() > reconnect_at:
			reconnect_at = Time.get_ticks_msec() + 3000
			socket.connect_to_url(url)
	for id in pending.keys():
		if Time.get_ticks_msec() - pending[id].time > 65000:
			pending.erase(id)
			failed.emit(id, "The library request timed out. Your unsaved changes are still here.")
