extends Control
## CRT dashboard for the selected disk, with a typed deck search bar along the
## bottom. Layout stays inside the tube's rounded safe area.
const INK := Color("84e3ce")
const DIM := Color("85bfb2")
const EDGE := Color("387e76")
const DARK := Color("061712")
const DESIGN_SIZE := Vector2(1024, 744)
const SAFE_RECT := Rect2(64, 48, 896, 648)
const TYPES := ["CREATURES", "INSTANTS", "SORCERIES", "ARTIFACTS", "ENCHANTMENTS", "PLANESWALKERS", "BATTLES", "LANDS"]
const TYPE_WORDS := ["Creature", "Instant", "Sorcery", "Artifact", "Enchantment", "Planeswalker", "Battle", "Land"]
## Design-space bounds of the search bar; clicks inside it focus the search.
const SEARCH_RECT := Rect2(64, 640, 896, 52)
var disk_name := ""
var commanders := ""
var player_count := 3
var stats: Dictionary = {}
var legal := false
var validation := ""
var status_message := ""
var lobby_status := ""
var online := true
var empty_library := false
var reading := true
var text_bounds: Array[Rect2] = []
var search_query := ""
var search_focused := false
var search_matches := 0
var blink := 0.0
## Online lobby seats ({name, kind, ready, you}) and whether this seat has pressed PLAY.
var party: Array = []
var lobby_ready := false
var pulse := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if lobby_ready:
		# The ready screen's cursor and waiting dots step a few times a second, not every frame.
		var step := int(pulse * 3.0)
		pulse += delta
		if int(pulse * 3.0) != step: queue_redraw()
	if not search_focused: return
	var was_on := fmod(blink, 1.0) < 0.5
	blink += delta
	if (fmod(blink, 1.0) < 0.5) != was_on: queue_redraw()

func set_search(query: String, focused: bool, matches: int) -> void:
	if focused and not search_focused: blink = 0.0
	search_query = query
	search_focused = focused
	search_matches = matches
	queue_redraw()

static func summarize(info: Dictionary) -> Dictionary:
	var counts := {}
	for kind in TYPES: counts[kind] = 0
	var curve: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var total := 0
	var total_mana := 0.0
	var nonlands := 0
	var identity := 0
	var leaders: Array = info.get("sections", {}).get("Commander", [])
	for card in leaders: identity |= int(card.get("colorIdentity", 0))
	for section in ["Main", "Commander"]:
		for card in info.get("sections", {}).get(section, []):
			var quantity := int(card.get("quantity", 1))
			var type_line: String = card.get("typeLine", "")
			total += quantity
			if leaders.is_empty(): identity |= int(card.get("colorIdentity", 0))
			for index in range(TYPES.size()):
				if type_line.contains(TYPE_WORDS[index]): counts[TYPES[index]] += quantity
			if not type_line.contains("Land"):
				var mana := maxf(0, float(card.get("manaValue", 0)))
				total_mana += mana * quantity
				nonlands += quantity
				curve[mini(7, int(mana))] += quantity
	return {"types": counts, "curve": curve, "total": total, "identity": identity, "average": total_mana / nonlands if nonlands > 0 else 0.0}

func present(info: Dictionary, players: int, no_decks: bool, selected_name: String = "") -> void:
	player_count = players
	empty_library = no_decks
	reading = info.is_empty()
	disk_name = str(info.get("name", selected_name))
	commanders = " + ".join(info.get("sections", {}).get("Commander", []).map(func(card): return card.name))
	stats = summarize(info)
	legal = info.get("legal", false)
	validation = str(info.get("validation", ""))
	queue_redraw()

func set_status(message: String, connected: bool, lobby: String = "") -> void:
	status_message = message
	lobby_status = lobby
	online = connected
	queue_redraw()

func set_party(seats: Array, ready_now: bool) -> void:
	if seats == party and ready_now == lobby_ready: return
	if ready_now and not lobby_ready: pulse = 0.0
	party = seats
	lobby_ready = ready_now
	queue_redraw()

func _fit(text: String, font: Font, font_size: int, width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width: return text
	var clipped := text
	while not clipped.is_empty() and font.get_string_size(clipped + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		clipped = clipped.left(clipped.length() - 1)
	return clipped + "..."

func _text(text: String, position: Vector2, font_size: int, color: Color = INK, width: float = 896) -> void:
	var font := get_theme_default_font()
	var visible := _fit(text, font, font_size, width)
	var extent := font.get_string_size(visible, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	text_bounds.append(Rect2(position - Vector2(0, font.get_ascent(font_size)), Vector2(extent.x, font.get_height(font_size))))
	draw_string(font, position, visible, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)

func _right_text(text: String, right: float, baseline: float, font_size: int, color: Color = INK) -> void:
	var width := get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(text, Vector2(right - width, baseline), font_size, color, width)

func _commander_lines(width: float) -> Array[String]:
	var lines: Array[String] = [""]
	var font := get_theme_default_font()
	for word in (commanders if not commanders.is_empty() else "NOT ASSIGNED").split(" "):
		var candidate := (lines[-1] + " " + word).strip_edges()
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x > width and lines.size() < 2 and not lines[-1].is_empty():
			lines.append(word)
		else: lines[-1] = candidate
	return lines

func _draw() -> void:
	text_bounds.clear()
	draw_set_transform(Vector2.ZERO, 0, size / DESIGN_SIZE)
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), DARK)
	_text("DISK: " + (disk_name.to_upper() if not disk_name.is_empty() else "NO DISK"), Vector2(64, 98), 40)
	_text("CMDR", Vector2(64, 144), 28, DIM, 106)
	var lines := _commander_lines(764)
	for index in range(lines.size()): _text(lines[index], Vector2(196, 144 + index * 32), 30, INK, 764)
	if lobby_ready and online and status_message.is_empty():
		_draw_ready()
		_draw_search()
		draw_set_transform(Vector2.ZERO)
		return
	_text("FORMAT  COMMANDER    PLAYERS  %d" % player_count, Vector2(64, 210), 28, DIM)
	var colors := ""
	for index in range(5):
		if int(stats.get("identity", 0)) & (1 << index): colors += "WUBRG"[index] + " "
	if colors.is_empty(): colors = "C "
	_text("COLORS  %s | AVG MV  %.2f" % [colors.strip_edges(), stats.get("average", 0.0)], Vector2(64, 248), 28)
	draw_line(Vector2(64, 266), Vector2(960, 266), EDGE, 1)
	_text("MANA CURVE", Vector2(64, 302), 26, DIM, 460)
	_text("CARD TYPES", Vector2(594, 302), 26, DIM, 366)
	var curve: Array = stats.get("curve", [0, 0, 0, 0, 0, 0, 0, 0])
	var maximum := maxi(1, int(curve.max()))
	for index in range(8):
		var baseline := 335.0 + index * 30
		var count := int(curve[index])
		var bar := "#".repeat(ceili(float(count) / maximum * 16))
		_text("%2s %-16s %2d" % [str(index) if index < 7 else "7+", bar, count], Vector2(64, baseline), 30, INK, 460)
		_text(TYPES[index], Vector2(594, baseline), 30, DIM, 300)
		_right_text(str(stats.get("types", {}).get(TYPES[index], 0)), 960, baseline, 30)
	draw_line(Vector2(64, 564), Vector2(960, 564), EDGE, 1)
	var check := "[ OK ] COMMANDER LEGAL" if legal else "[CHECK] OPEN DECK EDITOR"
	if legal and not lobby_status.is_empty(): check = lobby_status
	if reading: check = ("[ -- ] NO MATCHING DECKS" if not search_query.is_empty() else "[ -- ] NO DECKS") if empty_library else "[ .. ] READING DISK"
	if not online: check = "[LINK] CONNECTING TO FORGE"
	if not status_message.is_empty(): check = "[ERR] " + status_message
	_text(check, Vector2(64, 599), 28, INK if legal else Color("bd9bf2"), 620)
	_right_text("%03d / 100" % int(stats.get("total", 0)), 960, 599, 28)
	var ratio := clampf(float(stats.get("total", 0)) / 100.0, 0, 1)
	preload("res://scripts/app/TerminalMeter.gd").paint(self, Rect2(64, 614, 896, 12), ratio)
	_draw_search()
	draw_set_transform(Vector2.ZERO)

## Online lobby after PLAY: a big READY banner, how many humans are ready, and each seat's state.
func _draw_ready() -> void:
	var humans := party.filter(func(seat): return seat.kind in ["host", "player"])
	var ready_count := humans.filter(func(seat): return seat.ready).size()
	var waiting := humans.filter(func(seat): return not seat.ready).map(func(seat): return str(seat.name).to_upper())
	var cursor_on := fmod(pulse, 1.0) < 0.5
	draw_line(Vector2(64, 186), Vector2(960, 186), EDGE, 1)
	var banner_rect := Rect2(64, 204, 896, 92)
	draw_rect(banner_rect, Color("0b2320"))
	draw_rect(banner_rect, INK, false, 2)
	var font := get_theme_default_font()
	_text(">> READY", Vector2(92, 274), 64, INK, 420)
	if cursor_on: draw_rect(Rect2(92 + font.get_string_size(">> READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x + 14, 274 - font.get_ascent(64) + 10, 30, font.get_ascent(64) - 12), INK)
	_right_text("%d/%d READY" % [ready_count, humans.size()], 932, 266, 40, INK)
	var dots := ".".repeat(int(pulse * 3.0) % 4)
	var line := "ALL PLAYERS READY - STARTING" + dots if waiting.is_empty() else "WAITING FOR " + ", ".join(waiting) + dots
	_text(line, Vector2(64, 336), 28, INK if waiting.is_empty() else DIM, 896)
	preload("res://scripts/app/TerminalMeter.gd").paint(self, Rect2(64, 352, 896, 12), float(ready_count) / maxi(1, humans.size()))
	for index in range(mini(party.size(), 4)):
		var seat: Dictionary = party[index]
		var baseline := 412.0 + index * 46
		var tag: String = {"host": "HOST", "player": "NET", "bot": "BOT", "open": "----"}.get(seat.kind, "NET")
		var state: String = "OPEN" if seat.kind == "open" else ("AUTO" if seat.kind == "bot" else ("READY" if seat.ready else "WAITING" + dots))
		var mark: String = "[ -- ]" if seat.kind == "open" else ("[ OK ]" if seat.ready else ("[ .. ]" if cursor_on else "[    ]"))
		var color: Color = EDGE if seat.kind == "open" else (INK if seat.ready else Color("bd9bf2"))
		_text(mark, Vector2(64, baseline), 30, color, 120)
		_text(tag, Vector2(188, baseline), 24, DIM, 80)
		_text(str(seat.name).to_upper() + ("  (YOU)" if seat.get("you", false) else ""), Vector2(272, baseline), 30, INK if seat.kind != "open" else EDGE, 470)
		_right_text(state, 960, baseline, 28, color)
	draw_line(Vector2(64, 600), Vector2(960, 600), EDGE, 1)
	_text("> SELECTING ANOTHER DISK CANCELS READY", Vector2(64, 628), 22, DIM, 896)

func _draw_search() -> void:
	draw_rect(SEARCH_RECT, Color("0b2320"))
	draw_rect(SEARCH_RECT, INK if search_focused else EDGE, false, 2)
	var baseline := SEARCH_RECT.position.y + 35
	_text("FIND>", Vector2(80, baseline), 28, DIM, 90)
	var font := get_theme_default_font()
	var right_label := ""
	if not search_query.is_empty(): right_label = "%d MATCH%s" % [search_matches, "" if search_matches == 1 else "ES"]
	elif not search_focused: right_label = "TYPE TO SEARCH"
	var right_width := font.get_string_size(right_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	if not right_label.is_empty(): _right_text(right_label, SEARCH_RECT.end.x - 16, baseline, 24, DIM)
	var field := Vector2(182, baseline)
	var width := SEARCH_RECT.end.x - 16 - right_width - 24 - field.x
	var shown := search_query.to_upper()
	# Keep the end of a long query (and the cursor) in view.
	while not shown.is_empty() and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x > width - 20:
		shown = shown.substr(1)
	if not shown.is_empty(): _text(shown, field, 28, INK, width)
	if search_focused and fmod(blink, 1.0) < 0.5:
		var cursor_x := field.x + font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 3
		draw_rect(Rect2(cursor_x, baseline - font.get_ascent(28) + 4, 14, font.get_ascent(28) - 2), INK)
