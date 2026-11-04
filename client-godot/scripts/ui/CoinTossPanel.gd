extends PanelContainer
## Shared presentation of Forge's starting toss. Never submits a game decision.
signal settled
const Avatar = preload("res://scripts/ui/PlayerAvatar.gd")
const P = preload("res://scripts/ui/Palette.gd")
const SPIN_SECONDS := 1.8
const TOTAL_SECONDS := 2.65
var toss_id := -1
var elapsed := 0.0
var complete := false
var toss: Dictionary = {}
var local_winner := false
var connected := true
var coin: Control
var title: Label
var status: Label
var hint: Label
var portrait: Control
var layout_scale := 1.0
var participants: Label
var players: Array = []
var outcome_marks: Array[String] = []
var winner_index := 0

func _ready() -> void:
	# The Mac table uses a 2x UI viewport; keep the full panel inside short windows.
	layout_scale = clampf((get_viewport_rect().size.y - 80.0) / 760.0, 0.42, 1.0)
	P.style_popup(self, roundi(28 * layout_scale))
	custom_minimum_size.x = 520 * layout_scale
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(12 * layout_scale))
	add_child(column)
	title = _label("COIN TOSS", 30)
	column.add_child(title)
	coin = Control.new()
	coin.custom_minimum_size = Vector2(460, 210) * layout_scale
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.draw.connect(_draw_coin)
	column.add_child(coin)
	status = _label("Flipping...", 25)
	status.custom_minimum_size = Vector2(460, 64) * layout_scale
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(status)
	portrait = Avatar.new()
	portrait.portrait_only = true
	portrait.custom_minimum_size = Vector2(136, 88) * layout_scale
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(portrait)
	participants = _label("", 16)
	participants.custom_minimum_size = Vector2(460, 48) * layout_scale
	participants.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(participants)
	hint = _label("The winner chooses who starts.", 16)
	hint.custom_minimum_size.x = 460 * layout_scale
	hint.custom_minimum_size.y = 48 * layout_scale
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("85bfb2"))
	column.add_child(hint)
	_update_text()

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", roundi(font_size * layout_scale))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func present(state: Dictionary) -> void:
	toss = state.get("startingToss", {}).duplicate(true)
	toss_id = int(toss.get("id", -1))
	local_winner = int(toss.get("winnerSeat", -1)) == 0
	connected = state.get("connectionReady", false)
	players = state.get("players", []).duplicate(true)
	# Snapshot seats rotate per viewer; engine IDs keep the die identical for all.
	players.sort_custom(func(a, b): return _engine_id(a) < _engine_id(b))
	outcome_marks.clear()
	var initials: Array[String] = []
	for player in players:
		var initial := str(player.get("name", "Player")).strip_edges().left(1).to_upper()
		initials.append(initial if not initial.is_empty() else "?")
	var winner_id := int(toss.get("winnerId", -1))
	var seat := int(toss.get("winnerSeat", -1))
	if seat >= 0 and seat < state.get("players", []).size():
		winner_id = _engine_id(state.players[seat])
	var key: Array[String] = []
	for index in range(players.size()):
		var mark := initials[index]
		if initials.count(mark) > 1: mark += str(initials.slice(0, index + 1).count(mark))
		outcome_marks.append(mark)
		key.append("%s · %s" % [mark, players[index].name])
		if _engine_id(players[index]) == winner_id: winner_index = index
	participants.text = "\n".join(key) if players.size() > 2 else ""
	if seat >= 0 and seat < state.get("players", []).size(): portrait.set_player(state.players[seat], false)
	_update_text()

func _engine_id(player: Dictionary) -> int:
	return int(player.get("engineId", player.get("id", -1)))

func _process(delta: float) -> void:
	if complete: return
	elapsed = minf(TOTAL_SECONDS, elapsed + delta)
	coin.queue_redraw()
	_update_text()
	if elapsed >= TOTAL_SECONDS:
		complete = true
		settled.emit()

func _update_text() -> void:
	if status == null: return
	var landed := elapsed >= SPIN_SECONDS
	portrait.modulate.a = 1.0 if landed else 0.0
	var dice := players.size() > 2
	title.text = "%d-SIDED DIE" % players.size() if dice else "COIN TOSS"
	status.text = str(toss.get("winnerName", "Player")) + (" won the roll" if dice else " won the toss") if landed else ("Rolling..." if dice else "Flipping...")
	if not landed:
		hint.text = "Each player has a 1 in %d chance.\nThe winner chooses who starts." % maxi(2, players.size())
	elif not connected:
		hint.text = "Reconnecting to Forge..."
	elif toss.get("choosing", false):
		hint.text = "You choose who starts." if local_winner else "%s is choosing who starts." % toss.get("winnerName", "The winner")
	else:
		hint.text = "%s will start. Preparing opening hands..." % toss.get("firstName", "The selected player")

func _draw_coin() -> void:
	if players.size() > 2:
		_draw_die()
		return
	var progress := clampf(elapsed / SPIN_SECONDS, 0.0, 1.0)
	var spin := (1.0 - pow(1.0 - progress, 2.0)) * TAU * 4.0
	var width := maxf(0.075, absf(cos(spin))) if progress < 1.0 else 1.0
	var center := Vector2(coin.size.x * 0.5, (125 - sin(progress * PI) * 46) * layout_scale)
	coin.draw_set_transform(Vector2(coin.size.x * 0.5, 192 * layout_scale), 0, Vector2(1, 0.16) * layout_scale)
	coin.draw_circle(Vector2.ZERO, 63, Color(0, 0, 0, 0.25))
	coin.draw_set_transform(center + Vector2(4, 3) * layout_scale, 0, Vector2(width, 1) * layout_scale)
	coin.draw_circle(Vector2.ZERO, 66, Color("78542a"))
	coin.draw_set_transform(center, 0, Vector2(width, 1) * layout_scale)
	coin.draw_circle(Vector2.ZERO, 66, Color("d9af60"))
	coin.draw_arc(Vector2.ZERO, 60, 0, TAU, 80, Color("ffe3a2"), 3, true)
	coin.draw_arc(Vector2.ZERO, 51, 0, TAU, 80, Color("9e7537"), 2, true)
	var glyph := "H" if toss.get("heads", true) else "T"
	if progress < 1.0 and cos(spin) < 0: glyph = "T" if glyph == "H" else "H"
	var font := get_theme_default_font()
	var extent := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 56)
	coin.draw_string(font, Vector2(-extent.x * 0.5, 19), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color("694b28"))
	coin.draw_set_transform(Vector2.ZERO)

func _draw_die() -> void:
	var count := players.size()
	var vertices: Array[Vector3] = []
	var faces: Array = []
	if count == 3:
		# A triangular prism: three equal rectangular rolling faces.
		for y in [-0.8, 0.8]:
			for index in range(3):
				var angle := TAU * index / 3.0
				vertices.append(Vector3(sin(angle), y, cos(angle)))
		faces = [[0, 1, 4, 3], [1, 2, 5, 4], [2, 0, 3, 5], [0, 2, 1], [3, 4, 5]]
	else:
		# A tetrahedron: four equal triangular faces.
		vertices.assign([Vector3(1, 1, 1), Vector3(-1, -1, 1), Vector3(-1, 1, -1), Vector3(1, -1, -1)])
		faces = [[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]]
	var winning_face: Array = faces[winner_index]
	var normal := _face_normal(vertices, winning_face)
	var landing := Basis(Vector3.RIGHT, -0.5 if count == 4 else -0.25) * Basis(Vector3.UP, 0.6 if count == 4 else 0.30) * Basis(Quaternion(normal, Vector3(0, 0, 1)))
	var progress := clampf(elapsed / SPIN_SECONDS, 0.0, 1.0)
	var remaining := pow(1.0 - progress, 2.3)
	var orientation := Basis(Vector3.RIGHT, remaining * TAU * 2.0) * Basis(Vector3.UP, remaining * TAU * 3.0) * landing
	var center := Vector2(coin.size.x * 0.5, (115 - sin(progress * PI) * 18) * layout_scale)
	var radius := (54.0 if count == 4 else 68.0) * layout_scale
	coin.draw_set_transform(Vector2(coin.size.x * 0.5, 192 * layout_scale), 0, Vector2(1, 0.16) * layout_scale)
	coin.draw_circle(Vector2.ZERO, 70, Color(0, 0, 0, 0.25))
	coin.draw_set_transform(Vector2.ZERO)
	var surfaces: Array = []
	for index in range(faces.size()):
		var face: Array = faces[index]
		var facing := orientation * _face_normal(vertices, face)
		if facing.z <= 0: continue
		var points := PackedVector2Array()
		var midpoint := Vector2.ZERO
		var depth := 0.0
		for vertex in face:
			var rotated := orientation * vertices[vertex]
			var point := center + Vector2(rotated.x, -rotated.y) * radius
			points.append(point)
			midpoint += point / face.size()
			depth += rotated.z / face.size()
		surfaces.append({"points": points, "midpoint": midpoint, "depth": depth, "light": facing.z, "index": index})
	surfaces.sort_custom(func(a, b): return a.depth < b.depth)
	for surface in surfaces:
		var points: PackedVector2Array = surface.points
		var color := Color("745ba0").lerp(Color("c8afe8"), float(surface.light))
		coin.draw_colored_polygon(points, color)
		var outline := points.duplicate()
		outline.append(points[0])
		coin.draw_polyline(outline, Color("eadbff"), 2.0 * layout_scale, true)
		if surface.index < count and surface.light > 0.3:
			var mark: String = outcome_marks[surface.index]
			var font := get_theme_default_font()
			var font_size := roundi((34 if mark.length() == 1 else 27) * layout_scale)
			var extent := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			coin.draw_string(font, surface.midpoint + Vector2(-extent.x * 0.5, font_size * 0.34), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("231a36"))

func _face_normal(vertices: Array[Vector3], face: Array) -> Vector3:
	var normal := (vertices[face[1]] - vertices[face[0]]).cross(vertices[face[2]] - vertices[face[0]]).normalized()
	var center := Vector3.ZERO
	for vertex in face: center += vertices[vertex]
	return normal if normal.dot(center) > 0 else -normal
