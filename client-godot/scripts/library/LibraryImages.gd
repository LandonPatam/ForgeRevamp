extends Node
signal available(key: String)
const Existing = preload("res://scripts/ui/CardImages.gd")
var api: Node
var textures: Dictionary = {}
var attempted: Dictionary = {}
var failures: Dictionary = {}
var image_keys: Dictionary = {}
var requests: Dictionary = {}
var downloads: Array = []
var active: Dictionary = {}
var downloaders: Array[HTTPRequest] = []
var next_download_at := 0
var priority_keys: Dictionary = {}
var urgent_keys: Dictionary = {}
var seen_public_faces: Dictionary = {}
var pending_public_faces: Dictionary = {}
const MAX_DOWNLOADS := 4
const MAX_LOOKUPS := 4
const DOWNLOAD_INTERVAL_MS := 150
var network_enabled := true
var queued_images: Array = []
var async_keys: Dictionary = {}
var image_jobs: Array = []
var deferred_results: Array = []
var game_faces: Dictionary = {}
var retry_after: Dictionary = {}
var visible_faces: Dictionary = {}
var next_visible_retry := 0
var last_preemption := 0
const CACHE := "user://library-art/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)
	for index in range(MAX_DOWNLOADS):
		var http := HTTPRequest.new()
		add_child(http)
		http.timeout = 15
		http.request_completed.connect(_downloaded.bind(http))
		downloaders.append(http)
	api.response.connect(_response)
	api.failed.connect(func(id, message):
		if requests.has(id):
			_fail(requests[id], message)
			requests.erase(id))

func texture_for(card: Dictionary) -> Texture2D:
	var key := cache_key(card)
	image_keys[key] = card.get("imageKey", "")
	if textures.has(key):
		Existing.register_texture(image_keys[key], textures[key])
		return textures[key]
	# The editor honors the selected printing, so only use an exact manifest key.
	Existing.texture_for({}) # initializes the shared manifest without a name fallback
	var local_path: String = Existing.manifest.get("byKey", {}).get(card.get("imageKey", ""), "")
	if not local_path.is_empty() and ResourceLoader.exists(local_path):
		var local: Texture2D = load(local_path)
		_accept(key, local)
		return local
	var cached := _load_image(CACHE + key.sha256_text() + ".img")
	if cached != null:
		_accept(key, cached)
		return cached
	if not key.is_empty() and not attempted.has(key):
		attempted[key] = true
		requests[api.request("image", {"key": card.key, "back": card.get("back", false)})] = key
	return null

func request_texture(card: Dictionary) -> Texture2D:
	# Grid/cover painting never opens or decodes a file on the input frame.
	var key := cache_key(card)
	if key.is_empty(): return null
	image_keys[key] = card.get("imageKey", "")
	if textures.has(key): return textures[key]
	if Existing.downloaded.has(image_keys[key]):
		_accept(key, Existing.downloaded[image_keys[key]])
		return textures[key]
	Existing.texture_for({})
	var path: String = Existing.manifest.get("byKey", {}).get(image_keys[key], "")
	if Existing.textures.get(path) != null:
		_accept(key, Existing.textures[path])
		return textures[key]
	if not path.is_empty() and ResourceLoader.has_cached(path):
		_accept(key, load(path))
		return textures[key]
	if not async_keys.has(key):
		async_keys[key] = true
		if not attempted.has(key): queued_images.append({"key": key, "card": card.duplicate(true), "path": path})
	return null

func prioritize(cards: Array, urgent_cards: Array = []) -> void:
	priority_keys.clear()
	urgent_keys.clear()
	for card in urgent_cards:
		var key := cache_key(card)
		if not urgent_keys.has(key): urgent_keys[key] = urgent_keys.size()
	for card in cards:
		var key := cache_key(card)
		if not priority_keys.has(key): priority_keys[key] = priority_keys.size()
	queued_images = _prioritized(queued_images)
	downloads = _prioritized(downloads)
	deferred_results = _prioritized(deferred_results)
	_preempt_background()

func warm_deck(deck: Dictionary) -> void:
	# Queue work only; launch and Forge decisions never await artwork.
	var faces := deck_faces(deck)
	faces.sort_custom(func(a, b): return _early_rank(a) < _early_rank(b))
	# Each early mana band gets a turn. A large combined land catalog must not
	# postpone every opponent's one-, two- and three-mana spell until it finishes.
	var commanders: Array = []
	var lanes: Array = [[], [], [], []]
	var later: Array = []
	for card in faces:
		var rank := _early_rank(card)
		if rank < 0: commanders.append(card)
		elif rank < 4: lanes[int(rank)].append(card)
		else: later.append(card)
	faces = commanders
	var remaining := true
	while remaining:
		remaining = false
		for lane in lanes:
			if not lane.is_empty():
				faces.append(lane.pop_front())
				remaining = true
	faces.append_array(later)
	var names := {}
	var ranks := {}
	for card in faces:
		var identity: String = str(card.get("imageKey", "")).trim_prefix("c:").get_slice("|", 0)
		var duplicate: bool = names.has(identity)
		names[identity] = true
		ranks[cache_key(card)] = ranks.size() + (10000 if duplicate else 0)
		game_faces[str(card.get("imageKey", ""))] = card
		_retry(card)
		request_texture(card)
	for queue in [queued_images, downloads, deferred_results]:
		var current: Array = queue.filter(func(job): return ranks.has(job.key))
		current.sort_custom(func(a, b): return int(ranks[a.key]) < int(ranks[b.key]))
		var ordered := _prioritized(current + queue.filter(func(job): return not ranks.has(job.key)))
		queue.assign(ordered)

func _early_rank(card: Dictionary) -> float:
	if card.get("commander", false) and not card.get("back", false): return -1
	return clampf(float(card.get("manaValue", 8)), 0, 20) + (30 if card.get("back", false) else 0)

func observe_match(state: Dictionary) -> void:
	var visible_cards: Array = []
	for item in state.get("stack", []): visible_cards.append(item.get("card", {}))
	for ask in state.get("asks", []):
		visible_cards.append(ask.get("sourceCard", {}))
		for option in ask.get("options", []): visible_cards.append(option.get("card", {}))
	visible_cards.append_array(state.get("revealed", []))
	visible_cards.append_array(state.get("prompt", {}).get("cards", []))
	visible_cards.append_array(state.get("prompt", {}).get("revealedCards", []))
	var urgent_cards: Array = visible_cards.duplicate()
	for player in state.get("players", []):
		for card in player.get("zones", {}).get("Battlefield", []):
			var descriptor := _game_descriptor(card)
			if descriptor.is_empty(): continue
			var key := cache_key(descriptor)
			if not seen_public_faces.has(key): pending_public_faces[key] = descriptor
			seen_public_faces[key] = true
		for zone in ["Hand", "Battlefield", "Command", "Graveyard", "Exile"]:
			visible_cards.append_array(player.get("zones", {}).get(zone, []))
	var descriptors: Array = []
	visible_faces.clear()
	for card in visible_cards:
		var descriptor := _game_descriptor(card)
		if descriptor.is_empty(): continue
		descriptors.append(descriptor)
		visible_faces[cache_key(descriptor)] = descriptor
		_retry(descriptor)
		request_texture(descriptor)
	var urgent: Array = []
	for card in urgent_cards:
		var descriptor := _game_descriptor(card)
		if not descriptor.is_empty(): urgent.append(descriptor)
	for key in pending_public_faces.keys():
		if textures.has(key) or not visible_faces.has(key): pending_public_faces.erase(key)
		else: urgent.append(pending_public_faces[key])
	prioritize(urgent + descriptors, urgent)

func clear_match_focus() -> void:
	visible_faces.clear()
	seen_public_faces.clear()
	pending_public_faces.clear()
	prioritize([])

func _game_descriptor(card: Dictionary) -> Dictionary:
	if card.get("hidden", false) or card.get("faceDown", false): return {}
	var key: String = card.get("imageKey", "")
	if game_faces.has(key): return game_faces[key]
	if not key.begins_with("c:") or (key.contains("$") and not key.ends_with("$alt")): return {}
	var printing := key.trim_prefix("c:").trim_suffix("$alt")
	if printing.split("|").size() != 3: return {}
	var descriptor := {"key": printing + "|false", "imageKey": key, "name": card.get("name", "Card"), "back": key.ends_with("$alt")}
	game_faces[key] = descriptor
	return descriptor

func manages_card(card: Dictionary) -> bool:
	return not _game_descriptor(card).is_empty()

func _retry(card: Dictionary) -> void:
	var key := cache_key(card)
	if not failures.has(key) or Time.get_ticks_msec() < int(retry_after.get(key, 0)): return
	failures.erase(key)
	attempted.erase(key)
	async_keys.erase(key)

func _fail(key: String, message: String) -> void:
	failures[key] = message
	retry_after[key] = Time.get_ticks_msec() + 30000

func _preempt_background() -> void:
	# A newly played card need not wait behind four stalled background transfers.
	if Time.get_ticks_msec() - last_preemption < 250 or not downloads.any(func(job): return priority_keys.has(job.key)): return
	if active.size() < MAX_DOWNLOADS: return
	var urgent_waiting := downloads.any(func(job): return urgent_keys.has(job.key))
	var candidates: Array = active.keys()
	candidates.sort_custom(func(a, b): return int(active[a].get("started", 0)) > int(active[b].get("started", 0)))
	for http in candidates:
		var job: Dictionary = active[http]
		if urgent_waiting:
			if urgent_keys.has(job.key): continue
		elif priority_keys.has(job.key) or Time.get_ticks_msec() - int(job.get("started", 0)) < 750: continue
		http.cancel_request()
		active.erase(http)
		downloads.append(job)
		downloads = _prioritized(downloads)
		last_preemption = Time.get_ticks_msec()
		return

func _prioritized(jobs: Array) -> Array:
	var urgent: Array = jobs.filter(func(job): return urgent_keys.has(job.key))
	urgent.sort_custom(func(a, b): return int(urgent_keys[a.key]) < int(urgent_keys[b.key]))
	var visible: Array = jobs.filter(func(job): return priority_keys.has(job.key) and not urgent_keys.has(job.key))
	visible.sort_custom(func(a, b): return int(priority_keys[a.key]) < int(priority_keys[b.key]))
	return urgent + visible + jobs.filter(func(job): return not priority_keys.has(job.key))

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() >= next_visible_retry:
		next_visible_retry = Time.get_ticks_msec() + 1000
		for card in visible_faces.values():
			_retry(card)
			request_texture(card)
	_preempt_background()
	_start_download()
	# Limit texture uploads and cache writes to one completed image per frame.
	if not deferred_results.is_empty() and image_jobs.size() < 3:
		var result: Dictionary = deferred_results.pop_front()
		_finish_response(result.key, result.result)
		return
	for job in image_jobs:
		var texture: Texture2D
		var done := false
		if job.has("thread"):
			if not job.thread.is_alive():
				var pixels: Image = job.thread.wait_to_finish()
				if pixels != null: texture = ImageTexture.create_from_image(pixels)
				done = true
		else:
			var status := ResourceLoader.load_threaded_get_status(job.path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				texture = ResourceLoader.load_threaded_get(job.path)
				Existing.textures[job.path] = texture
				done = true
			elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]: done = true
		if done:
			image_jobs.erase(job)
			if texture != null:
				_accept(job.key, texture)
				available.emit(job.key)
			elif job.get("remote", false) or job.get("downloaded", false): _fail(job.key, "Image data could not be decoded.")
			else: _request_remote(job)
			return
	if queued_images.is_empty() or image_jobs.size() >= 3: return
	var job: Dictionary = queued_images.pop_front()
	if textures.has(job.key): return
	var cache_path: String = job.get("cache_file", CACHE + str(job.key).sha256_text() + ".img")
	if not str(job.path).is_empty() and ResourceLoader.exists(job.path):
		var status := ResourceLoader.load_threaded_request(job.path)
		if status == OK or ResourceLoader.load_threaded_get_status(job.path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			image_jobs.append(job)
		else: _request_remote(job)
	elif FileAccess.file_exists(cache_path):
		var worker := Thread.new()
		if worker.start(_read_pixels.bind(cache_path)) == OK:
			job.thread = worker
			image_jobs.append(job)
		else: _request_remote(job)
	else: _request_remote(job)

func _request_remote(job: Dictionary) -> void:
	if attempted.has(job.key): return
	# Cached Forge faces arrive as base64 over WebSocket. Bound those responses
	# as well as HTTP transfers so a whole table cannot flood the receive buffer.
	if requests.size() >= MAX_LOOKUPS:
		queued_images.append(job)
		return
	attempted[job.key] = true
	requests[api.request("image", {"key": job.card.key, "back": job.card.get("back", false)})] = job.key

func _read_pixels(path: String) -> Image:
	return _decode_pixels(FileAccess.get_file_as_bytes(path))

func _decode_remote(key: String, encoded: String) -> Image:
	var bytes := Marshalls.base64_to_raw(encoded)
	var pixels := _decode_pixels(bytes)
	if pixels != null: _save_bytes(key, bytes)
	return pixels

func _exit_tree() -> void:
	for job in image_jobs:
		if job.has("thread"): job.thread.wait_to_finish()

static func cache_key(card: Dictionary) -> String:
	return str(card.get("key", "")) + ("|back" if card.get("back", false) else "")

static func deck_faces(deck: Dictionary) -> Array:
	var unique := {}
	for section in deck.get("sections", {}).values():
		for card in section:
			unique[cache_key(card)] = card
			if not str(card.get("backImageKey", "")).is_empty():
				var back: Dictionary = card.duplicate(true)
				back.back = true
				back.imageKey = card.backImageKey
				back.name = str(card.name) + " (back)"
				unique[cache_key(back)] = back
	return unique.values()

func prepare_deck(deck: Dictionary, progress: Callable = Callable(), canceled: Callable = Callable(), timeout: float = 300.0) -> Dictionary:
	var faces := deck_faces(deck)
	for card in faces:
		var key := cache_key(card)
		if failures.has(key):
			failures.erase(key)
			attempted.erase(key)
			async_keys.erase(key)
		request_texture(card)
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while true:
		if canceled.is_valid() and canceled.call(): return {"canceled": true, "missing": []}
		var ready := 0
		var missing: Array = []
		var pending := false
		for card in faces:
			var key := cache_key(card)
			if textures.has(key): ready += 1
			else:
				missing.append(str(card.get("name", "Card")))
				if not failures.has(key): pending = true
		if progress.is_valid(): progress.call(ready, faces.size())
		if missing.is_empty() or not pending or Time.get_ticks_msec() >= deadline:
			# A deadline failure must be retryable, without duplicating still-active jobs.
			var errors: Array = []
			for card in faces:
				if not textures.has(cache_key(card)): errors.append(str(card.get("name", "Card")) + ": " + str(failures.get(cache_key(card), "Download timed out")))
			return {"canceled": false, "missing": missing, "errors": errors}
		await get_tree().create_timer(0.05).timeout
	return {"canceled": false, "missing": []}

func _accept(key: String, texture: Texture2D) -> void:
	textures[key] = texture
	failures.erase(key)
	Existing.register_texture(str(image_keys.get(key, "")), texture)

func _save_bytes(key: String, bytes: PackedByteArray) -> void:
	var path := CACHE + key.sha256_text()
	var file := FileAccess.open(path + ".part", FileAccess.WRITE)
	if file == null: return
	file.store_buffer(bytes)
	file.close()
	DirAccess.rename_absolute(path + ".part", path + ".img")

func _load_image(path: String) -> Texture2D:
	if not FileAccess.file_exists(path): return null
	return _decode(FileAccess.get_file_as_bytes(path))

func _decode(bytes: PackedByteArray) -> Texture2D:
	var image := _decode_pixels(bytes)
	return ImageTexture.create_from_image(image) if image != null else null

func _decode_pixels(bytes: PackedByteArray) -> Image:
	var image := Image.new()
	if bytes.size() < 8 or not ((bytes[0] == 255 and bytes[1] == 216) or (bytes[0] == 137 and bytes[1] == 80 and bytes[2] == 78 and bytes[3] == 71)): return null
	var status := image.load_jpg_from_buffer(bytes) if bytes.size() > 2 and bytes[0] == 255 and bytes[1] == 216 else image.load_png_from_buffer(bytes)
	if status != OK: return null
	return image

func _response(id: int, operation: String, result: Dictionary) -> void:
	if operation != "image" or not requests.has(id): return
	var key: String = requests[id]
	requests.erase(id)
	if async_keys.has(key):
		deferred_results.append({"key": key, "result": result})
		return
	_finish_response(key, result)

func _finish_response(key: String, result: Dictionary) -> void:
	if result.has("data"):
		if async_keys.has(key):
			var worker := Thread.new()
			if worker.start(_decode_remote.bind(key, str(result.data))) == OK:
				image_jobs.append({"key": key, "thread": worker, "remote": true})
			else: _fail(key, "Could not start image decoding.")
			return
		var bytes := Marshalls.base64_to_raw(result.data)
		var texture := _decode(bytes)
		if texture != null:
			_accept(key, texture)
			_save_bytes(key, bytes)
			available.emit(key)
			return
	if result.has("url") and network_enabled:
		downloads.append({"key": key, "url": result.url})
		downloads = _prioritized(downloads)
		_start_download()
	else: _fail(key, "No downloadable image is available for this printing.")

func _start_download() -> void:
	# Overlap slow transfers, retaining a global interval between request starts.
	# Visible artwork jumps ahead of background deck/next-page work.
	if not network_enabled or downloads.is_empty() or Time.get_ticks_msec() < next_download_at: return
	for http in downloaders:
		if active.has(http): continue
		var job: Dictionary = downloads.pop_front()
		job.started = Time.get_ticks_msec()
		active[http] = job
		http.download_file = CACHE + str(job.key).sha256_text() + ".part"
		next_download_at = Time.get_ticks_msec() + DOWNLOAD_INTERVAL_MS
		if http.request(job.url) != OK:
			_fail(job.key, "Could not start the image download.")
			active.erase(http)
		return

func _downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, http: HTTPRequest) -> void:
	if not active.has(http): return
	var job: Dictionary = active[http]
	active.erase(http)
	var success := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if success and async_keys.has(job.key):
		var path := CACHE + str(job.key).sha256_text() + ".img"
		if DirAccess.rename_absolute(http.download_file, path) == OK:
			queued_images.push_front({"key": job.key, "path": "", "cache_file": path, "downloaded": true})
		else: _fail(job.key, "Could not cache the downloaded image.")
	elif success:
		var texture := _load_image(http.download_file)
		if texture != null:
			DirAccess.rename_absolute(http.download_file, CACHE + str(job.key).sha256_text() + ".img")
			_accept(job.key, texture)
			available.emit(job.key)
		else: _fail(job.key, "Image data could not be decoded.")
	else:
		_fail(job.key, "Image download failed (HTTP %d)." % code)
		if FileAccess.file_exists(http.download_file): DirAccess.remove_absolute(http.download_file)
	_start_download()
