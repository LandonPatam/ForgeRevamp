extends RefCounted
var ui: Control
var deadline := 0
var responses: Dictionary = {}
var errors: Dictionary = {}
var capture_root := ""
var fixture := ""

func check(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		ui.get_tree().quit(1)
	return value

func until(condition: Callable, message: String) -> bool:
	while Time.get_ticks_msec() < deadline:
		await ui.get_tree().create_timer(0.1).timeout
		if condition.call(): return true
	return check(false, "Timed out: " + message + " / " + ui.status_label.text)

func call_api(operation: String, args: Dictionary = {}) -> Dictionary:
	var id: int = ui.api.request(operation, args)
	if not await until(func(): return responses.has(id) or errors.has(id), operation): return {}
	if errors.has(id): return {"error": errors[id]}
	return responses[id]

func capture(name: String) -> void:
	if capture_root.is_empty(): return
	await ui.get_tree().process_frame
	await ui.get_tree().process_frame
	await RenderingServer.frame_post_draw
	ui.get_viewport().get_texture().get_image().save_png(capture_root.path_join(name + ".png"))

func run(table: Control) -> void:
	ui = table
	deadline = Time.get_ticks_msec() + 120000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--library-capture="): capture_root = arg.trim_prefix("--library-capture=")
		if arg.begins_with("--library-fixture="): fixture = arg.trim_prefix("--library-fixture=")
	ui.api.response.connect(func(id, _op, result): responses[id] = result)
	ui.api.failed.connect(func(id, error): errors[id] = error)
	if not await until(func(): return ui.online and not ui.draft.is_empty(), "initial Forge decks"): return
	if not check(ui.decks.filter(func(deck): return deck.source == "custom").size() == 9 and ui.draft.name == ui.decks[0].name, "Load installed-format decks and select the first deck"): return
	if not check(ui.decks.slice(9).size() > 150 and ui.decks.slice(9).all(func(deck): return deck.source == "precon"), "Forge's precons follow the saved decks"): return
	ui._request("open", {"id": "Atraxa.dck"})
	if not await until(func(): return ui.draft.name == "Atraxa", "open Atraxa"): return
	if not check(ui.shown_cards.size() >= 20 and ui.card_grid.get_child_count() == ui.shown_cards.size(), "Selected deck must display every distinct card entry"): return
	if not check(not ui.carousel.looping and ui.carousel.decks.back().get("create", false), "Editor carousel is bounded and ends with a New deck floppy"): return
	# A cold open enriches the cover descriptor during the carousel's move.
	# Keep the fractional position and avoid repainting every floppy for it.
	var shelf: Control = ui.carousel
	shelf.cursor = shelf.target - 0.4
	var in_flight: float = shelf.cursor
	var refreshed: Array = ui.decks.duplicate(true)
	refreshed[0].cover["coldLoadDetails"] = true
	var built: Array = shelf.tiles.filter(func(tile): return tile.face_view != null)
	if not check(built.size() < 40 and shelf.tiles.size() > 150, "Only on-screen floppies build face viewports: %d of %d" % [built.size(), shelf.tiles.size()]): return
	for tile in built: tile.face_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	shelf.set_decks(refreshed, ui.draft.id)
	if not check(is_equal_approx(shelf.cursor, in_flight) and not is_equal_approx(shelf.cursor, shelf.target), "Cold cover metadata must preserve the in-flight carousel animation instead of snapping to the selected disk"): return
	if not check(built.all(func(tile): return tile.face_view.render_target_update_mode == SubViewport.UPDATE_DISABLED), "Metadata refreshes must not repaint unchanged floppy faces"): return
	ui._render_decks()
	var original_tiles: Array = ui.card_grid.get_children()
	ui.select_deck(ui.decks[2].id)
	if not check(ui.loading_deck and ui.carousel.enabled, "The carousel stays interactive while an uncached deck loads"): return
	ui.select_deck(ui.decks[3].id)
	if not await until(func(): return ui.draft.id == ui.decks[3].id and not ui.loading_deck, "latest rapid deck selection wins"): return
	ui.select_deck("Atraxa.dck")
	if not check(ui.draft.id == "Atraxa.dck" and not ui.loading_deck, "Revisiting a cached deck is immediate"): return
	if not check(ui.card_grid.get_children().any(func(tile): return original_tiles.has(tile)), "Deck browsing reuses card widgets"): return
	var retained_deck: Dictionary = ui.draft.duplicate(true)
	var abandoned: int = ui._request("open", {"id": ui.decks[3].id})
	ui._show_import()
	ui._load_deck({"id": "", "version": "", "name": "Keep this new draft", "sections": {"Main": [], "Commander": []}})
	ui.dirty = true
	if not await until(func(): return not ui.contexts.has(abandoned), "the abandoned deck load finishes"): return
	if not check(ui.draft.name == "Keep this new draft" and ui.dirty, "A late deck response cannot replace a newly created unsaved draft"): return
	ui.overlay.hide()
	ui._load_deck(retained_deck)
	print("EDITOR GRID CPU: ", ui.last_card_render_ms, " ms for ", ui.card_grid.get_child_count(), " cards")
	ui.density_slider.value = 6
	if not check(ui.preferred_columns == 6 and ui.card_grid.columns == 6 and ui.density_value.text == "6", "Slider changes the cards-per-row layout immediately"): return
	await ui.get_tree().create_timer(0.3).timeout
	var layout := ConfigFile.new()
	if not check(layout.load(ui._density_path()) == OK and layout.get_value("cards", "columns") == 6, "Slider density persists after dragging stops"): return
	await capture("library-density-slider")
	ui.density_slider.value = 0
	await capture("library-collection-1600")
	ui.card_grid.get_child(0).hovered.emit(ui.shown_cards[0])
	await ui.get_tree().create_timer(0.5).timeout
	if not check(not ui.overlay.visible, "Hover leaves the editor grid unobstructed"): return
	await capture("library-card-hover")
	ui.card_grid.get_child(0).mouse_exited.emit()
	ui.get_window().size = Vector2i(1280, 800)
	await ui.get_tree().create_timer(0.4).timeout
	if not check(ui.card_grid.get_global_rect().end.x <= ui.size.x - 20, "Card grid stays inside the smaller screen"): return
	await capture("library-collection-1280")
	ui.get_window().size = Vector2i(1600, 1000)
	var next: Dictionary = ui.decks[1]
	ui.carousel.deck_selected.emit(1)
	if not await until(func(): return ui.draft.id == next.id, "deck tile selection"): return
	ui.carousel._emit_index(ui.carousel.decks.size()-1)
	if not check(ui.overlay.visible and is_instance_valid(ui.import_text) and ui.import_behavior.item_count == 3, "+ opens create/import options"): return
	if not check(ui.file_dialog == null, "Opening the editor and its plus menu does not construct filesystem browsers"): return
	ui._ensure_file_dialogs()
	ui.file_dialog.file_selected.emit(fixture.path_join("Atraxa.dck"))
	if not check(ui.import_text.text.contains("[Commander]"), "The lazily created file picker still loads a native deck"): return
	await capture("library-import-options")
	ui.import_name.text = "Integration Import"
	ui.import_text.text = "Commander\n1 Atraxa, Praetors' Voice\nDeck\n1 Sol Ring\n1 Forest\n1 Definitely Not A Real Card 12345"
	ui._preview_import()
	if not await until(func(): return not ui.preview.is_empty(), "Forge import preview"): return
	if not check(ui.preview.warnings.size() == 1 and ui.preview.count == 3, "Unknown import lines are reported, recognized cards remain visible"): return
	await capture("library-import-preview")
	ui._apply_import()
	if not check(ui.dirty and ui.draft.name == "Integration Import" and ui.draft.id == "", "Import creates an unsaved draft"): return
	ui.save_button.pressed.emit()
	if not await until(func(): return not ui.dirty and ui.draft.id == "Integration Import.dck", "save native Forge deck"): return
	if not check(FileAccess.file_exists(fixture.path_join("Integration Import.dck")), "Save must create an actual native deck file"): return
	var saved := FileAccess.get_file_as_string(fixture.path_join("Integration Import.dck"))
	if not check(saved.contains("[Commander]") and saved.contains("Sol Ring"), "Native output retains sections and cards"): return
	var ring: Dictionary = ui.draft.sections.Main.filter(func(card): return card.name == "Sol Ring")[0]
	ring.section = "Main"
	ui._card_context(ring)
	if not check(ui.context_menu.visible and ui.context_menu.item_count >= 8, "Right-click offers copy, removal, artwork and section actions"): return
	await capture("library-card-context")
	ui.context_menu.hide()
	ui._card_action(1)
	if not check(ui.draft.sections.Main.filter(func(card): return card.name == "Sol Ring")[0].quantity == 2, "Add quantity"): return
	ui.undo_button.pressed.emit()
	if not check(ui.draft.sections.Main.filter(func(card): return card.name == "Sol Ring")[0].quantity == 1, "Undo quantity"): return
	ui.redo_button.pressed.emit()
	if not check(ui.draft.sections.Main.filter(func(card): return card.name == "Sol Ring")[0].quantity == 2, "Redo quantity"): return
	ui._set_mode(true)
	if not check(ui.overlay.visible and ui.card_search.results.is_empty() and not ui.catalog_mode and ui.shown_cards.any(func(card): return card.name == "Sol Ring"), "Add Cards opens an empty search popup while retaining the deck grid"): return
	for query in ["TChalla", "t’challa", "T Challa"]:
		ui.card_search.query.text = query
		ui.card_search._search()
		var search_id: int = ui.card_search.request_id
		if not await until(func(): return not ui.api.pending.has(search_id) and ui.card_search.results.any(func(card): return card.name == "T'Challa, the Black Panther"), "punctuation-tolerant card search: " + query): return
	var ranked: Dictionary = await call_api("catalog", {"query": "Urzas Saga", "limit": 6})
	if not check(not ranked.cards.is_empty() and ranked.cards[0].name == "Urza's Saga", "A normalized exact card name ranks before rules-text matches"): return
	var search_draft: Dictionary = ui.draft.duplicate(true)
	var search_leader: Dictionary = ui.card_search.results.filter(func(card): return card.name == "T'Challa, the Black Panther")[0].duplicate(true)
	search_leader.quantity = 1
	ui.draft.sections.Main.append(search_leader)
	ui.search.text = "tchalla"
	ui._refresh_cards()
	if not check(ui.shown_cards.any(func(card): return card.name == "T'Challa, the Black Panther"), "The current-deck filter uses the same punctuation-tolerant matching"): return
	ui.draft = search_draft
	ui.search.clear()
	ui._refresh_cards()
	ui.card_search.query.text = "Sol Ring"
	ui.card_search._search()
	if not await until(func(): return ui.card_search.results.any(func(card): return card.name == "Sol Ring"), "popup card search"): return
	await capture("library-catalog")
	ui.card_search.results_box.get_child(0).get_child(2).pressed.emit()
	if not check(ui.overlay.visible and ui.draft.sections.Main.filter(func(card): return card.name == "Sol Ring").reduce(func(count, card): return count + card.quantity, 0) == 3, "Search adds a card without closing the popup or replacing the deck view"): return
	ui.card_search.done.pressed.emit()
	if not check(not ui.overlay.visible and not ui.catalog_mode, "Done clearly returns to the deck"): return
	ui._undo()
	var catalog: Dictionary = await call_api("catalog", {"query": ""})
	if not check(int(catalog.get("total", 0)) > 30000, "Catalog must expose the full Forge card database"): return
	print("CATALOG: ", catalog.total, " unique Forge cards")
	var long_deck: Dictionary = ui.draft.duplicate(true)
	var current_deck: Dictionary = ui.draft.duplicate(true)
	long_deck.sections.Main = catalog.cards.duplicate(true)
	ui._load_deck(long_deck)
	if not check(ui.shown_cards.size() > 60 and ui.card_grid.get_child_count() == ui.shown_cards.size(), "Decks show every card without page navigation"): return
	ui._load_deck(current_deck)
	ui.dirty = true
	var printings: Dictionary = await call_api("printings", {"name": "Sol Ring"})
	if not check(printings.cards.size() > 5, "All available printings are accessible"): return
	ui._set_mode(false)
	ui.density_slider.value = 4
	for frame in range(3): await ui.get_tree().process_frame
	var ring_entry: Dictionary = ui.shown_cards.filter(func(card): return card.name == "Sol Ring")[0]
	ui._inspect(ring_entry)
	if not await until(func(): return ui.dialog_body.get_children().any(func(child): return child is OptionButton), "printing picker"): return
	await capture("library-card-details")
	var picker: OptionButton = ui.dialog_body.get_children().filter(func(child): return child is OptionButton)[0]
	var alternative: Dictionary = printings.cards.filter(func(card): return card.key != ring.key)[0]
	var index: int = printings.cards.find(alternative)
	ui.card_scroll.scroll_vertical = 200
	await ui.get_tree().process_frame
	var details_scroll: int = ui.card_scroll.scroll_vertical
	if not check(details_scroll > 0, "Artwork scroll regression starts below the top of the deck"): return
	picker.select(index)
	picker.item_selected.emit(index)
	for frame in range(3): await ui.get_tree().process_frame
	if not check(ui.card_scroll.scroll_vertical == details_scroll, "Changing the printing in card details keeps the deck scroll position"): return
	if not check(ui.draft.sections.Main.any(func(card): return card.key == alternative.key and card.quantity == 2), "Printing selection replaces the entry without changing quantity"): return
	ui._undo()
	if not check(ui.draft.sections.Main.any(func(card): return card.key == ring.key and card.quantity == 2), "Undo restores the previous printing"): return
	ui.overlay.hide()
	ui._card_context(ring_entry)
	ui.context_menu.hide()
	ui._card_action(4)
	if not await until(func(): return not ui.artwork_cards.is_empty() and ui.dialog_body.get_child_count() > 0, "artwork gallery"): return
	if not check(ui.printing_cache.has(ring.name), "Printing metadata is cached across details and the artwork gallery"): return
	var requests_before: int = ui.api.next_id
	ui.overlay.hide()
	ui._card_action(4)
	if not check(ui.api.next_id == requests_before and not ui.artwork_cards.is_empty(), "Reopening the artwork gallery renders immediately without another printing request"): return
	var page_keys: Array = ui.artwork_cards.slice(0, ui.images.priority_keys.size()).map(func(card): return ui.images.cache_key(card))
	if not check(page_keys.all(func(key): return ui.images.priority_keys.has(key)), "The visible artwork page has image-loading priority"): return
	await capture("library-artwork-gallery")
	ui.card_scroll.scroll_vertical = 240
	await ui.get_tree().process_frame
	var artwork_scroll: int = ui.card_scroll.scroll_vertical
	var artwork_tile: Control = ui.dialog_body.get_child(0).get_children().filter(func(group): return group.get_child(0).card.key == alternative.key)[0].get_child(0)
	artwork_tile.chosen.emit(alternative)
	for frame in range(3): await ui.get_tree().process_frame
	if not check(not ui.overlay.visible and artwork_scroll > 0 and ui.card_scroll.scroll_vertical == artwork_scroll, "Choosing artwork closes the gallery and returns to the same deck scroll position"): return
	if not check(ui.draft.sections.Main.any(func(card): return card.key == alternative.key and card.quantity == 2), "Artwork gallery preserves quantities and section"): return
	ui._undo()
	ui.overlay.hide()
	# Apply-to-all merges mixed printings of one name without touching other cards.
	var main_before: Array = ui.draft.sections.Main.duplicate(true)
	var mixed_entry: Dictionary = main_before.filter(func(card): return card.name == ring.name)[0]
	var other_printing: Dictionary = mixed_entry.duplicate(true)
	other_printing.key = "test-other-printing"
	other_printing.quantity = 3
	ui.draft.sections.Main.append(other_printing)
	var others: Array = main_before.filter(func(card): return card.name != ring.name).map(func(card): return card.key)
	ui.inspect_card = mixed_entry
	ui.apply_art_to_all = true
	ui._replace_printing(alternative)
	ui.apply_art_to_all = false
	var rings: Array = ui.draft.sections.Main.filter(func(card): return card.name == ring.name)
	if not check(rings.size() == 1 and rings[0].key == alternative.key and rings[0].quantity == int(mixed_entry.quantity) + 3, "Apply-to-all merges every printing into the chosen art and sums quantities: " + str(rings)): return
	if not check(others.all(func(key): return ui.draft.sections.Main.any(func(card): return card.key == key)), "Apply-to-all leaves other cards alone"): return
	ui._undo()
	ui.draft.sections.Main = main_before
	ui._changed(true, true)
	ui.overlay.hide()
	ui.density_slider.value = 0
	var exported: Dictionary = await call_api("export", {"deck": ui.draft})
	if not check(exported.text.contains("[metadata]") and exported.text.contains("[Commander]"), "Native export"): return
	var native_import: Dictionary = await call_api("import", {"text": saved})
	if not check(not native_import.has("error") and native_import.count == 3 and native_import.warnings.is_empty(), "Native .dck import preserves the exact deck"): return
	ui.overlay.hide()
	var invalid_url: Dictionary = await call_api("import", {"url": "https://example.invalid/not-a-deck"})
	if not check(invalid_url.has("error"), "Unsupported URL providers report an error"): return
	var rejected: Dictionary = await call_api("open", {"id": "../escape.dck"})
	if not check(rejected.has("error"), "Out-of-library paths are rejected"): return
	var original: Dictionary = ui.draft.duplicate(true)
	var file := FileAccess.open(fixture.path_join(original.id), FileAccess.READ_WRITE)
	file.seek_end()
	file.store_string("\n# External edit\n")
	file.close()
	var conflict: Dictionary = await call_api("save", {"deck": original})
	if not check(conflict.has("error") and conflict.error.contains("changed on disk"), "External edits must prevent overwriting"): return
	if not check(ui.dirty, "Rejected save retains unsaved edits"): return
	var source: Dictionary = await call_api("open", {"id": "Atraxa.dck"})
	source.name = "Atraxa metadata preserved"
	var result: Dictionary = await call_api("save", {"deck": source})
	if not check(not result.has("error") and FileAccess.get_file_as_string(fixture.path_join("Atraxa.dck")).contains("Preserve this test metadata"), "Editing native decks preserves metadata"): return
	var duplicate := source.duplicate(true)
	duplicate.sourceId = source.id
	duplicate.id = ""
	duplicate.name = "Metadata copy"
	var copied: Dictionary = await call_api("save", {"deck": duplicate})
	if not check(not copied.has("error") and FileAccess.get_file_as_string(fixture.path_join("Metadata copy.dck")).contains("Preserve this test metadata"), "Duplicating decks preserves metadata"): return
	var commander_draft: Dictionary = source.duplicate(true)
	commander_draft.id = ""
	commander_draft.version = ""
	commander_draft.name = "Commander assignment"
	var leader: Dictionary = source.sections.Commander[0].duplicate(true)
	var forest: Dictionary = source.sections.Main.filter(func(card): return card.name == "Forest")[0].duplicate(true)
	forest.quantity = 99
	leader.quantity = 1
	commander_draft.sections = {"Commander": [], "Main": [forest, leader]}
	ui.search.clear()
	ui._load_deck(commander_draft)
	var initial_check: Dictionary = await call_api("validate", {"deck": ui.draft})
	if not check(not initial_check.legal, "A 100-card draft without a commander is invalid"): return
	ui.overlay.hide()
	ui._validate(true)
	if not await until(func(): return ui.validation_reason.visible and ui.validate_button.status == "validate", "invalid deck displays an inline reason"): return
	if not check(not ui.overlay.visible and ui.validation_reason.text == ui.draft.validation and ui.validation_reason.get_parent() == ui.validate_button.get_parent(), "Validation failures appear beside Validate without a popup"): return
	await capture("library-commander-invalid-inline")
	if not check(not ui.draft.legal and not ui.validate_button.disabled and not ui.validate_button.tooltip_text.is_empty(), "Invalid decks retain the yellow retry action and validation details"): return
	ui.overlay.hide()
	var leader_entry: Dictionary = ui.shown_cards.filter(func(card): return card.key == leader.key)[0]
	ui._move_card(leader_entry, "Commander")
	ui.overlay.hide()
	if not check(ui.validate_button.status == "validate" and ui.validate_button.get_parent().get_index() == ui.stats_label.get_index() + 1 and not ui.validation_reason.visible, "Unvalidated edits show Validate after the statistics and clear the outdated reason"): return
	ui.validate_button.pressed.emit()
	if not check(ui.validate_button.status == "checking" and ui.validate_button.disabled and ui.validate_button.is_processing(), "Validation animates inside the button and prevents duplicate checks"): return
	if not await until(func(): return ui.validate_button.status == "legal", "inline Commander validation"): return
	if not check(ui.draft.get("legal", false) and not ui.overlay.visible and ui.validate_button.text == "Legal", "Valid drafts replace the button with a green Legal status without a success popup"): return
	if not check(ui.draft.sections.Commander.size() == 1 and ui.shown_cards[0].commander and int(ui.draft.count) == 100, "Setting a commander must designate it and preserve card counts"): return
	await capture("library-commander-validation")
	ui._changed(false)
	if not check(ui.validate_button.status == "validate", "Editing invalidates the previous Legal light immediately"): return
	await ui.get_tree().create_timer(0.6).timeout
	if not check(ui.validate_button.status == "validate", "Background statistics must not silently validate an edited draft"): return
	ui.overlay.hide()
	var assigned: Dictionary = await call_api("save", {"deck": ui.draft})
	if not check(assigned.legal and assigned.sections.Commander[0].commander and FileAccess.get_file_as_string(fixture.path_join(assigned.id)).contains("[Commander]"), "The designation survives native save and reload as a valid Commander deck"): return
	ui._load_deck(assigned)
	var rhys_result: Dictionary = await call_api("catalog", {"query": "Rhys the Redeemed"})
	var rhys: Dictionary = rhys_result.cards.filter(func(card): return card.name == "Rhys the Redeemed")[0].duplicate(true)
	ui.draft.sections.Main[0].quantity = 98
	rhys.quantity = 1
	ui.draft.sections.Main.append(rhys)
	ui._refresh_cards()
	ui._move_card(ui.shown_cards.filter(func(card): return card.key == rhys.key)[0], "Commander")
	if not check(ui.draft.sections.Commander.size() == 1 and ui.draft.sections.Commander[0].key == rhys.key and ui.draft.sections.Main.any(func(card): return card.key == leader.key), "A new commander replaces the old one and returns the old commander to Main"): return
	ui._load_deck(copied)
	ui._show_delete()
	if not check(ui.overlay.visible, "Deleting a saved deck requires its named confirmation"): return
	await capture("library-delete-deck")
	ui.dialog_body.get_child(1).pressed.emit()
	if not check(not ui.overlay.visible and FileAccess.file_exists(fixture.path_join(copied.id)), "Canceling deletion keeps the native deck intact"): return
	ui._show_delete()
	ui.delete_button.pressed.emit()
	if not await until(func(): return not ui.busy and not ui.loading_deck and not ui.draft.is_empty() and ui.draft.id != copied.id and not ui.decks.any(func(deck): return deck.id == copied.id), "delete the deck and select a remaining deck"): return
	if not check(not FileAccess.file_exists(fixture.path_join(copied.id)), "Deletion removes the native file from the active library"): return
	if not check(DirAccess.open(fixture.path_join(".forgeui-trash")).get_files().size() == 1, "Deleted deck files are retained in the local archive"): return
	var delete_escape: Dictionary = await call_api("delete", {"id": "../escape.dck", "version": ""})
	if not check(delete_escape.has("error"), "Deleting outside the library is rejected"): return
	var stale_delete: Dictionary = await call_api("delete", {"id": assigned.id, "version": "stale"})
	if not check(stale_delete.has("error") and FileAccess.file_exists(fixture.path_join(assigned.id)), "A stale delete cannot remove a deck changed on disk"): return
	if "--library-online-images" in OS.get_cmdline_user_args():
		for land in [{"name": "Plains", "number": "46"}, {"name": "Swamp", "number": "48"}]:
			var editions: Dictionary = await call_api("printings", {"name": land.name})
			var japanese: Array = editions.cards.filter(func(card): return card.edition == "SLD" and str(card.collectorNumber) == land.number)
			if not check(not japanese.is_empty(), "The Japanese-only Secret Lair printing exists: " + str(land)): return
			var face: Dictionary = japanese[0]
			var image_result: Dictionary = await call_api("image", {"key": face.key})
			if not check(str(image_result.get("url", "")).contains("/sld/" + str(land.number) + "?") and not str(image_result.url).contains("/en?"), "Exact-printing image URLs must support non-English-only printings"): return
			var test_key := "Japanese printing HTTP check " + str(Time.get_ticks_usec())
			ui.images.image_keys[test_key] = face.imageKey
			ui.images.async_keys[test_key] = true
			ui.images._finish_response(test_key, {"url": image_result.url})
			if not await until(func(): return ui.images.textures.has(test_key) or ui.images.failures.has(test_key), "Japanese-only exact-printing HTTP download"): return
			if not check(ui.images.textures.has(test_key), "Secret Lair artwork must download and decode: " + str(ui.images.failures.get(test_key, ""))): return
			DirAccess.remove_absolute(ui.images.CACHE + test_key.sha256_text() + ".img")
		var alpha: Array = printings.cards.filter(func(card): return card.edition == "LEA")
		if not check(not alpha.is_empty(), "Alpha Sol Ring printing exists"): return
		ui.images.texture_for(alpha[0])
		if not await until(func(): return ui.images.textures.has(alpha[0].key), "on-demand printing artwork"): return
		if not check(preload("res://scripts/ui/CardImages.gd").texture_for({"imageKey": alpha[0].imageKey}) == ui.images.textures[alpha[0].key], "Downloaded exact-printing artwork is shared with the game renderer"): return
		var transform: Dictionary = await call_api("printings", {"name": "Delver of Secrets"})
		var innistrad_faces: Array = transform.get("cards", []).filter(func(card): return card.edition == "ISD")
		if not check(not innistrad_faces.is_empty() and innistrad_faces[0].has("backImageKey"), "Double-faced deck entries expose their alternate image key"): return
		var back: Dictionary = await call_api("image", {"key": innistrad_faces[0].key, "back": true})
		if not check(back.has("data") or str(back.get("url", "")).contains("face=back"), "Back artwork resolves from Forge or a back-face download URL"): return
		print("ARTWORK: exact-printing local/on-demand image loaded")
	print("PASS: Forge deck library integration (deck selection, responsive card grids, full catalog, printings, import warnings/preview, native save/export, quantities, undo/redo, metadata and conflict guards)")
	ui.get_tree().quit()
