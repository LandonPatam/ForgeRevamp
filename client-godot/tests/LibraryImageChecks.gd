extends RefCounted
const Images = preload("res://scripts/library/LibraryImages.gd")
const Faces = preload("res://scripts/ui/CardImages.gd")

class FakeApi extends Node:
	signal response(id: int, operation: String, value: Dictionary)
	signal failed(id: int, message: String)
	var calls: Array = []
	func request(operation: String, args: Dictionary) -> int:
		calls.append([operation, args])
		return calls.size()

func prepare(service: Node, deck: Dictionary, results: Array, progress: Array) -> void:
	results.append(await service.prepare_deck(deck, func(ready, total): progress.append([ready, total]), Callable(), 3.0))

func run(ui: Control) -> void:
	var api := FakeApi.new()
	ui.add_child(api)
	var service := Images.new()
	service.api = api
	service.network_enabled = false
	ui.add_child(service)
	var prefix := "Image check " + str(Time.get_ticks_usec())
	var front := {"key": prefix + " A", "name": "First card", "imageKey": "c:" + prefix + " A"}
	var flip := {"key": prefix + " B", "name": "Transform card", "imageKey": "c:" + prefix + " B", "backImageKey": "c:" + prefix + " B$alt"}
	var deck := {"sections": {"Main": [front, front, flip], "Commander": [front]}}
	var results: Array = []
	var progress: Array = []
	prepare(service, deck, results, progress)
	var lookup_deadline := Time.get_ticks_msec() + 3000
	while api.calls.size() < 3 and Time.get_ticks_msec() < lookup_deadline: await ui.get_tree().process_frame
	assert(results.is_empty() and api.calls.size() == 3, "Launch preparation waits for every unique face, including the back; quantities don't duplicate jobs")
	assert(api.calls[2][1].back, "Back artwork is requested separately from the printing's front")
	var image := Image.create(16, 24, false, Image.FORMAT_RGB8)
	image.fill(Color.TEAL)
	var data := {"data": Marshalls.raw_to_base64(image.save_png_to_buffer())}
	api.response.emit(1, "image", data)
	while not service.textures.has(front.key) and Time.get_ticks_msec() < lookup_deadline: await ui.get_tree().process_frame
	assert(Faces.texture_for(front) == service.textures[front.key], "Downloaded library artwork is immediately available to the game renderer")
	var hidden: Dictionary = front.duplicate()
	hidden.hidden = true
	assert(Faces.texture_for(hidden) == null, "Sharing artwork must preserve hidden-card privacy")
	api.response.emit(2, "image", {"data": Marshalls.raw_to_base64("not an image".to_utf8_buffer())})
	api.response.emit(3, "image", data)
	await ui.get_tree().create_timer(0.1).timeout
	assert(results.size() == 1 and results[0].missing == ["Transform card"] and progress.back() == [2, 3], "Invalid data fails preparation instead of silently accepting a placeholder")
	results.clear()
	prepare(service, deck, results, progress)
	while api.calls.size() < 4 and Time.get_ticks_msec() < lookup_deadline: await ui.get_tree().process_frame
	assert(api.calls.size() == 4 and results.is_empty(), "Retry requests only the failed face")
	api.response.emit(4, "image", data)
	await ui.get_tree().create_timer(0.1).timeout
	assert(results.size() == 1 and results[0].missing.is_empty() and progress.back() == [3, 3], "Launch becomes ready only after the missing face decodes")
	Faces.downloaded.erase(front.imageKey)
	var cached := Images.new()
	cached.api = api
	ui.add_child(cached)
	assert(cached.texture_for(front) != null and api.calls.size() == 4 and Faces.texture_for(front) != null, "A new image service loads the disk cache and registers it for gameplay without a new request")
	Faces.downloaded.erase(front.imageKey)
	var background := Images.new()
	background.api = api
	ui.add_child(background)
	assert(background.request_texture(front) == null and api.calls.size() == 4, "Painting a cold cached image queues it without decoding or requesting it on the input frame")
	var background_deadline := Time.get_ticks_msec()+3000
	while not background.textures.has(front.key) and Time.get_ticks_msec() < background_deadline: await ui.get_tree().process_frame
	assert(background.textures.has(front.key) and api.calls.size() == 4, "Background cache decoding publishes the image without a new network request")
	var remote := {"key": prefix + " C", "name": "Uncached image", "imageKey": "c:" + prefix + " C"}
	background.request_texture(remote)
	while api.calls.size() < 5 and Time.get_ticks_msec() < background_deadline: await ui.get_tree().process_frame
	assert(api.calls.size() == 5)
	api.response.emit(5, "image", data)
	assert(not background.textures.has(remote.key), "Cold image responses must queue decoding rather than block the animation frame")
	while not background.textures.has(remote.key) and Time.get_ticks_msec() < background_deadline: await ui.get_tree().process_frame
	assert(background.textures.has(remote.key) and Faces.texture_for(remote) != null, "Worker-decoded remote artwork must reach the editor and shared gameplay cache")
	var corrupt := {"key": prefix + " D", "name": "Corrupt cold image", "imageKey": "c:" + prefix + " D"}
	background.request_texture(corrupt)
	while api.calls.size() < 6 and Time.get_ticks_msec() < background_deadline: await ui.get_tree().process_frame
	assert(api.calls.size() == 6)
	api.response.emit(6, "image", {"data": Marshalls.raw_to_base64("bad image".to_utf8_buffer())})
	while not background.failures.has(corrupt.key) and Time.get_ticks_msec() < background_deadline: await ui.get_tree().process_frame
	assert(background.failures.has(corrupt.key), "Worker decode failures must finish with an error instead of hanging image readiness")
	await _check_lookups(ui, api, data, prefix)
	await _check_warmup(ui, api, data, prefix)
	DirAccess.remove_absolute(Images.CACHE + Images.cache_key(remote).sha256_text() + ".img")
	Faces.downloaded.erase(remote.imageKey)
	background.queue_free()
	for face in Images.deck_faces(deck):
		DirAccess.remove_absolute(Images.CACHE + Images.cache_key(face).sha256_text() + ".img")
		Faces.downloaded.erase(face.imageKey)
	await _check_downloads(ui, api, image.save_png_to_buffer(), prefix)
	await _check_preemption(ui, api, image.save_png_to_buffer(), prefix)
	service.queue_free()
	cached.queue_free()
	api.queue_free()
	await ui.get_tree().process_frame
	print("PASS: optional image batch completion, corrupt-data rejection, retries, shared gameplay textures and disk cache reuse")

func _check_warmup(ui: Control, api: Node, data: Dictionary, prefix: String) -> void:
	var service := Images.new()
	service.api = api
	service.network_enabled = false
	ui.add_child(service)
	var first_call: int = api.calls.size()
	var cards: Array = []
	for index in range(9):
		cards.append({"key": prefix + " warm " + str(index), "name": "Early card " + str(index), "imageKey": "c:" + prefix + " warm " + str(index) + "|TEST|1", "manaValue": index})
	var second_land := {"key": prefix + " second land", "name": "Early card 0", "imageKey": "c:" + prefix + " warm 0|OTHER|1", "manaValue": 0}
	cards.append(second_land)
	service.warm_deck({"sections": {"Main": cards}})
	assert(api.calls.size() == first_call and service.queued_images.size() == cards.size(), "Warmup must return immediately without decoding files or waiting on downloads")
	assert(service.queued_images[0].card.key == cards[0].key and service.queued_images[1].card.key == cards[1].key and service.queued_images.back().card.key == second_land.key, "Cheap early plays and a first printing take priority over repeated basic-land artwork")
	var deadline := Time.get_ticks_msec() + 3000
	while service.requests.size() < Images.MAX_LOOKUPS and Time.get_ticks_msec() < deadline: await ui.get_tree().process_frame
	var late: Dictionary = cards[8]
	var hidden_key := "c:" + prefix + " hidden|TEST|1"
	service.observe_match({"players": [{"zones": {"Hand": [{"id": 500, "hidden": true, "imageKey": hidden_key}], "Battlefield": [{"id": 501, "name": late.name, "imageKey": late.imageKey}]}}]})
	assert(service.priority_keys.has(late.key) and not service.game_faces.has(hidden_key), "Public cards overtake background warmup; hidden hand information must not affect requests or priorities")
	var released: int = service.requests.keys()[0]
	api.response.emit(released, "image", data)
	while not service.requests.values().has(late.key) and Time.get_ticks_msec() < deadline: await ui.get_tree().process_frame
	assert(service.requests.values().has(late.key), "A newly played card must get the next lookup slot instead of waiting for the rest of its deck")
	var visible_request: int = service.requests.find_key(late.key)
	api.failed.emit(visible_request, "Temporary artwork failure")
	var calls_before_retry: int = api.calls.size()
	service.observe_match({"stack": [{"card": {"imageKey": late.imageKey}}]})
	assert(service.failures.has(late.key) and api.calls.size() == calls_before_retry, "Failed artwork must cool down without blocking play or creating a request loop")
	service.retry_after[late.key] = 0
	service.observe_match({"stack": [{"card": {"imageKey": late.imageKey}}]})
	while not service.requests.values().has(late.key) and Time.get_ticks_msec() < deadline: await ui.get_tree().process_frame
	assert(service.requests.values().has(late.key), "Visible artwork can retry after its cooldown")
	while service.textures.size() < cards.size() and Time.get_ticks_msec() < deadline:
		for id in service.requests.keys(): api.response.emit(id, "image", data)
		await ui.get_tree().process_frame
	assert(service.textures.size() == cards.size(), "Background faces continue warming after a visible-card failure and retry")
	service.clear_match_focus()
	assert(service.visible_faces.is_empty() and service.priority_keys.is_empty(), "Leaving a match releases its image priorities for the editor without discarding cached faces")
	for card in cards:
		DirAccess.remove_absolute(Images.CACHE + str(card.key).sha256_text() + ".img")
		Faces.downloaded.erase(card.imageKey)
		Faces.name_textures.erase(Faces._face_identity(card.imageKey))
	service.queue_free()
	await ui.get_tree().process_frame
	print("PASS: nonblocking deck warmup, early-play ordering, exact visible-card priority, hidden guards and bounded retry")
	var bands := Images.new()
	bands.api = api
	bands.network_enabled = false
	ui.add_child(bands)
	var spread: Array = []
	for mana in range(4):
		for index in range(6):
			spread.append({"key": prefix + " band %s %s" % [mana, index], "name": "Band %s %s" % [mana, index], "imageKey": "c:" + prefix + " band %s %s|TEST|1" % [mana, index], "manaValue": mana})
	bands.warm_deck({"sections": {"Main": spread}})
	assert(bands.queued_images.slice(0, 4).map(func(job): return int(job.card.manaValue)) == [0, 1, 2, 3], "Combined deck warmup must cover early spell costs before exhausting all lands")
	bands.queue_free()
	await ui.get_tree().process_frame

func _check_lookups(ui: Control, api: Node, data: Dictionary, prefix: String) -> void:
	var service := Images.new()
	service.api = api
	ui.add_child(service)
	var first_call: int = api.calls.size()
	var cards: Array = []
	for index in range(12):
		var card := {"key": prefix + " lookup " + str(index), "imageKey": "c:" + prefix + " lookup " + str(index)}
		cards.append(card)
		service.request_texture(card)
	await ui.get_tree().create_timer(0.15).timeout
	assert(api.calls.size() - first_call == Images.MAX_LOOKUPS and service.requests.size() == Images.MAX_LOOKUPS, "A full-table warmup must bound cached/base64 lookup responses as well as HTTP downloads")
	var deadline := Time.get_ticks_msec() + 3000
	while service.textures.size() < cards.size() and Time.get_ticks_msec() < deadline:
		assert(service.requests.size() <= Images.MAX_LOOKUPS)
		for id in service.requests.keys(): api.response.emit(id, "image", data)
		await ui.get_tree().process_frame
	assert(service.textures.size() == cards.size(), "All queued faces must complete as bounded lookup slots reopen")
	for card in cards:
		DirAccess.remove_absolute(Images.CACHE + str(card.key).sha256_text() + ".img")
		Faces.downloaded.erase(card.imageKey)
	service.queue_free()
	await ui.get_tree().process_frame

func _check_downloads(ui: Control, api: Node, pixels: PackedByteArray, prefix: String) -> void:
	# A local HTTP fixture holds one transfer open while later artwork completes.
	var server := TCPServer.new()
	var listen_result := server.listen(0, "127.0.0.1")
	assert(listen_result == OK)
	var service := Images.new()
	service.api = api
	ui.add_child(service)
	var cards: Array = []
	for index in range(6):
		var card := {"key": prefix + " download " + str(index), "imageKey": "c:" + prefix + " download " + str(index)}
		cards.append(card)
		service.image_keys[card.key] = card.imageKey
		service.async_keys[card.key] = true
		service.attempted[card.key] = true
		service._finish_response(card.key, {"url": "http://127.0.0.1:%d/%d" % [server.get_local_port(), index]})
	service.prioritize([cards[4]])
	assert(service.downloads[0].key == cards[4].key, "Visible artwork overtakes queued background downloads")
	var connections: Array = []
	var order: Array = []
	var starts: Array[int] = []
	var peak := 0
	var finished_before_slow := false
	var deadline := Time.get_ticks_msec() + 6000
	var slow_release := Time.get_ticks_msec() + 1400
	while service.textures.size() + service.failures.size() < cards.size() and Time.get_ticks_msec() < deadline:
		while server.is_connection_available():
			connections.append({"peer": server.take_connection(), "request": "", "sent": false})
		for connection in connections:
			var peer: StreamPeerTCP = connection.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: continue
			if not connection.sent and peer.get_available_bytes() > 0:
				connection.request += peer.get_utf8_string(peer.get_available_bytes())
				if connection.request.contains("\r\n\r\n") and not connection.has("index"):
					connection.index = int(str(connection.request).split(" ")[1].trim_prefix("/"))
					order.append(connection.index)
					starts.append(Time.get_ticks_msec())
			if connection.sent or not connection.has("index"): continue
			if connection.index == 0 and Time.get_ticks_msec() < slow_release: continue
			var code := "404 Not Found" if connection.index == 5 else "200 OK"
			var headers := "HTTP/1.1 %s\r\nContent-Type: image/png\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [code, pixels.size()]
			peer.put_data(headers.to_utf8_buffer())
			peer.put_data(pixels)
			connection.sent = true
		peak = maxi(peak, service.active.size())
		if service.textures.has(cards[4].key) and not service.textures.has(cards[0].key): finished_before_slow = true
		await ui.get_tree().process_frame
	assert(service.textures.size() == 5 and service.failures.has(cards[5].key), "Concurrent images finish independently and a failed image releases its slot")
	assert(finished_before_slow and peak > 1 and peak <= Images.MAX_DOWNLOADS, "A slow image cannot block other artwork; download concurrency stays bounded")
	assert(order[0] == 0 and order[1] == 4, "The next request belongs to the visible page")
	for index in range(1, starts.size()):
		assert(starts[index] - starts[index-1] >= Images.DOWNLOAD_INTERVAL_MS - 35, "Parallel transfers retain the global request-start interval")
	var calls_before: int = api.calls.size()
	for card in cards.slice(0, 5):
		assert(service.request_texture(card) != null, "Revisiting an artwork uses its cached texture")
	assert(api.calls.size() == calls_before, "Cached artwork does not request metadata again")
	for connection in connections: connection.peer.disconnect_from_host()
	server.stop()
	for card in cards:
		DirAccess.remove_absolute(Images.CACHE + str(card.key).sha256_text() + ".img")
		Faces.downloaded.erase(card.imageKey)
	service.queue_free()
	await ui.get_tree().process_frame
	print("PASS: bounded parallel artwork downloads, visible-page priority, request spacing, failures and cache reuse")

func _check_preemption(ui: Control, api: Node, pixels: PackedByteArray, prefix: String) -> void:
	var server := TCPServer.new()
	var listen_result := server.listen(0, "127.0.0.1")
	assert(listen_result == OK)
	var service := Images.new()
	service.api = api
	ui.add_child(service)
	var cards: Array = []
	for index in range(5):
		var card := {"key": prefix + " preempt " + str(index), "imageKey": "c:" + prefix + " preempt " + str(index)}
		cards.append(card)
		service.game_faces[card.imageKey] = card
		service.image_keys[card.key] = card.imageKey
		service.async_keys[card.key] = true
		service.attempted[card.key] = true
		service._finish_response(card.key, {"url": "http://127.0.0.1:%d/%d" % [server.get_local_port(), index]})
	service.prioritize(cards.slice(0, 4))
	var connections: Array = []
	var deadline := Time.get_ticks_msec() + 7000
	var began := Time.get_ticks_msec()
	var promoted := false
	var promoted_at := 0
	var urgent_started_at := 0
	var urgent_finished := false
	while service.textures.size() < cards.size() and Time.get_ticks_msec() < deadline:
		while server.is_connection_available(): connections.append({"peer": server.take_connection(), "request": "", "sent": false})
		for connection in connections:
			var peer: StreamPeerTCP = connection.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: continue
			if not connection.sent and peer.get_available_bytes() > 0:
				connection.request += peer.get_utf8_string(peer.get_available_bytes())
				if connection.request.contains("\r\n\r\n") and not connection.has("index"):
					connection.index = int(str(connection.request).split(" ")[1].trim_prefix("/"))
					if connection.index == 4: urgent_started_at = Time.get_ticks_msec()
			if connection.sent or not connection.has("index") or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or (connection.index != 4 and not urgent_finished): continue
			peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % pixels.size()).to_utf8_buffer())
			peer.put_data(pixels)
			connection.sent = true
		if not promoted and service.active.size() == Images.MAX_DOWNLOADS and Time.get_ticks_msec() - began > 500:
			promoted_at = Time.get_ticks_msec()
			service.observe_match({"stack": [{"card": cards[4]}], "players": [{"zones": {"Hand": cards.slice(0, 4)}}]})
			assert(service.urgent_keys.has(cards[4].key) and not service.urgent_keys.has(cards[0].key), "A newly played opposing spell outranks artwork for already-visible hand cards")
			promoted = true
		if service.textures.has(cards[4].key): urgent_finished = true
		await ui.get_tree().process_frame
	assert(promoted and urgent_finished and service.textures.size() == cards.size(), "A visible card must preempt stalled background transfers, and every interrupted background image must still finish afterward")
	assert(urgent_started_at - promoted_at < 350, "A newly played card must start within the normal request interval instead of waiting for the old 750ms transfer age limit")
	for connection in connections: connection.peer.disconnect_from_host()
	server.stop()
	for card in cards:
		DirAccess.remove_absolute(Images.CACHE + str(card.key).sha256_text() + ".img")
		Faces.downloaded.erase(card.imageKey)
	service.queue_free()
	await ui.get_tree().process_frame
	print("PASS: newly played artwork preempts young visible-hand transfers without losing interrupted images")
