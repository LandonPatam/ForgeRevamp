extends Node
## Newly visible cards and created tokens fetch each distinct public face once.
const Images = preload("res://scripts/ui/CardImages.gd")
const CACHE := "user://runtime-art/"
var http := HTTPRequest.new()
var pending: Array = []
var attempted: Dictionary = {}
var active: Dictionary = {}
var network_enabled := true
var shared_images: Node
var match_active := true

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)
	add_child(http)
	http.timeout = 15
	http.body_size_limit = 3000000
	http.request_completed.connect(_completed)

func observe(state: Dictionary) -> void:
	if match_active and is_instance_valid(shared_images): shared_images.observe_match(state)
	for player in state.get("players", []):
		for zone in player.get("zones", {}).values():
			for card in zone: request_card(card)
	for item in state.get("stack", []): request_card(item.get("card", {}))
	for card in state.get("revealed", []): request_card(card)
	for card in state.get("prompt", {}).get("cards", []): request_card(card)
	for card in state.get("prompt", {}).get("revealedCards", []): request_card(card)
	for ask in state.get("asks", []):
		request_card(ask.get("sourceCard", {}))
		for option in ask.get("options", []): request_card(option.get("card", {}))

func request_card(card: Dictionary) -> void:
	if is_instance_valid(shared_images) and shared_images.manages_card(card): return
	var key: String = card.get("imageKey", "")
	if card.get("hidden", false) or card.get("faceDown", false) or not (key.begins_with("t:") or key.begins_with("c:")): return
	if attempted.has(key) or Images.texture_for(card) != null: return
	attempted[key] = true
	var path := CACHE + key.sha256_text() + ".img"
	if FileAccess.file_exists(path) and _accept(key, FileAccess.get_file_as_bytes(path)): return
	var legacy := "user://token-art/" + key.sha256_text() + ".img"
	if FileAccess.file_exists(legacy) and _accept(key, FileAccess.get_file_as_bytes(legacy)): return
	if not network_enabled: return
	var urls: Array = card.get("imageUrls", card.get("tokenImageUrls", [])).duplicate()
	if urls.is_empty(): return
	pending.append({"key": key, "urls": urls, "path": path})
	_start()

func _start() -> void:
	if not active.is_empty() or pending.is_empty(): return
	active = pending.pop_front()
	_next_url()

func _next_url() -> void:
	if active.urls.is_empty():
		active.clear()
		_start.call_deferred()
		return
	var url: String = active.urls.pop_front()
	if http.request(url) != OK: _next_url.call_deferred()

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not _accept(active.key, body):
		_next_url.call_deferred()
		return
	var file := FileAccess.open(active.path, FileAccess.WRITE)
	if file != null: file.store_buffer(body)
	active.clear()
	_start.call_deferred()

func _accept(key: String, bytes: PackedByteArray) -> bool:
	var pixels := Image.new()
	if bytes.size() < 8 or not ((bytes[0] == 255 and bytes[1] == 216) or (bytes[0] == 137 and bytes[1] == 80)): return false
	var error := pixels.load_png_from_buffer(bytes) if bytes[0] == 137 else pixels.load_jpg_from_buffer(bytes)
	if error != OK or pixels.is_empty(): return false
	Images.register_texture(key, ImageTexture.create_from_image(pixels))
	return true
