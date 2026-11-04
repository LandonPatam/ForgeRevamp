extends VBoxContainer
signal card_added(card: Dictionary, section: String)
signal closed
const Tile = preload("res://scripts/library/LibraryCard.gd")
var api: Node
var images: Node
var ink := Color("304a55")
var query: LineEdit
var section: OptionButton
var status: Label
var results_box: VBoxContainer
var timer: Timer
var previous: Button
var next: Button
var done: Button
var request_id := -1
var offset := 0
var total := 0
var results: Array = []
const PAGE_SIZE := 6
static var search_pattern: RegEx

static func search_key(text: String) -> String:
	if search_pattern == null:
		search_pattern = RegEx.new()
		search_pattern.compile("[^\\p{L}\\p{N}]+")
	return search_pattern.sub(text.to_lower(), "", true)

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	query = LineEdit.new()
	query.placeholder_text = "Search a card name or rules text…"
	query.clear_button_enabled = true
	query.text_changed.connect(func(_text): offset = 0; request_id = -1; timer.start())
	query.text_submitted.connect(func(_text): offset = 0; _search())
	add_child(query)
	var target := HBoxContainer.new()
	add_child(target)
	var caption := Label.new()
	caption.text = "Add to"
	target.add_child(caption)
	section = OptionButton.new()
	for name in ["Main", "Commander", "Sideboard"]: section.add_item(name)
	section.tooltip_text = "Commander sets this card as commander and returns the previous commander to Main."
	target.add_child(section)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Search for a card to add. Your deck stays open behind this popup."
	add_child(status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 320
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	results_box = VBoxContainer.new()
	results_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_box.add_theme_constant_override("separation", 12)
	scroll.add_child(results_box)
	var footer := HBoxContainer.new()
	add_child(footer)
	previous = Button.new()
	previous.text = "Previous"
	previous.pressed.connect(func(): offset = maxi(0, offset - PAGE_SIZE); _search())
	footer.add_child(previous)
	next = Button.new()
	next.text = "Next"
	next.pressed.connect(func(): offset += PAGE_SIZE; _search())
	footer.add_child(next)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	done = Button.new()
	done.text = "Done — back to deck"
	done.pressed.connect(func(): closed.emit())
	footer.add_child(done)
	timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.25
	timer.timeout.connect(_search)
	add_child(timer)
	api.response.connect(_response)
	api.failed.connect(func(id, message):
		if id == request_id: status.text = message)
	_navigation()
	query.grab_focus.call_deferred()

func _search() -> void:
	timer.stop()
	var text := query.text.strip_edges()
	if text.is_empty():
		request_id = -1
		total = 0
		results = []
		_render()
		status.text = "Search for a card to add."
		return
	status.text = "Searching…"
	request_id = api.request("catalog", {"query": text, "offset": offset, "limit": PAGE_SIZE})

func _response(id: int, operation: String, result: Dictionary) -> void:
	if id != request_id or operation != "catalog": return
	results = result.cards
	total = int(result.total)
	_render()
	status.text = "%d matches · click Add beside a card." % total if total > 0 else "No matching cards. Try another name."

func _navigation() -> void:
	previous.visible = total > PAGE_SIZE
	next.visible = total > PAGE_SIZE
	previous.disabled = offset == 0
	next.disabled = offset + PAGE_SIZE >= total

func _render() -> void:
	for child in results_box.get_children():
		results_box.remove_child(child)
		child.queue_free()
	for card in results:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		results_box.add_child(row)
		var tile := Tile.new()
		tile.card = card
		tile.images = images
		tile.ink = ink
		tile.custom_minimum_size = Vector2(80, 142)
		row.add_child(tile)
		var info := Label.new()
		info.text = "%s\n%s · %s\n%s" % [card.name, card.manaCost, card.typeLine, card.text.replace("\\n", "\n")]
		info.max_lines_visible = 5
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.tooltip_text = card.text.replace("\\n", "\n")
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var add := Button.new()
		add.text = "+ Add"
		add.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add.pressed.connect(func():
			card_added.emit(card, section.text)
			status.text = "Set %s as commander." % card.name if section.text == "Commander" else "Added %s to %s." % [card.name, section.text])
		row.add_child(add)
	_navigation()
