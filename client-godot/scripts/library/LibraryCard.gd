extends Control
signal chosen(card: Dictionary)
signal hovered(card: Dictionary)
signal context_requested(card: Dictionary)
const P = preload("res://scripts/ui/Palette.gd")
var card: Dictionary = {}
var images: Node
var texture: Texture2D
var hot := false
var ink := P.TEXT
var deck_tile := false
var selected := false
var choose_on_release := false
var selection_pressed := false
var context_pressed := false
var title := ""
var subtitle := ""
var deck_name_label: Label

func _ready() -> void:
	clip_contents = true
	if deck_tile:
		deck_name_label = Label.new()
		deck_name_label.text = title
		deck_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deck_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		deck_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		deck_name_label.max_lines_visible = 2
		deck_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		deck_name_label.add_theme_font_size_override("font_size", 16)
		deck_name_label.add_theme_color_override("font_color", Color.WHITE)
		add_child(deck_name_label)
		resized.connect(_layout_deck_name)
		_layout_deck_name()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if images != null:
		images.available.connect(func(key):
			if key == card.get("key", ""):
				texture = images.request_texture(card)
				queue_redraw())
		if not card.is_empty(): texture = images.request_texture(card)
	mouse_entered.connect(func(): hot = true; queue_redraw(); hovered.emit(card))
	mouse_exited.connect(func(): hot = false; queue_redraw())
	gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			if event.pressed: context_pressed = true
			elif context_pressed:
				context_pressed = false
				# Opening a Window on mouse-down steals the release and leaves
				# this tile holding mouse capture behind the next dialog.
				if Rect2(Vector2.ZERO, size).has_point(event.position): context_requested.emit(card)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if choose_on_release:
				if event.pressed: selection_pressed = true
				elif selection_pressed:
					selection_pressed = false
					if Rect2(Vector2.ZERO, size).has_point(event.position): chosen.emit(card)
			elif event.pressed: chosen.emit(card))
	resized.connect(queue_redraw)

func _layout_deck_name() -> void:
	if deck_name_label == null: return
	var top := 8 + (size.x - 12) * 1.4 + 10
	deck_name_label.position = Vector2(4, top)
	deck_name_label.size = Vector2(size.x - 8, maxf(40, size.y - top - (24 if card.is_empty() else 6)))

func _draw() -> void:
	var font := get_theme_default_font()
	var highlight := Color.WHITE
	if deck_tile:
		if selected or hot: draw_style_box(P.box(Color("34363a"), highlight if selected else Color("878b90"), 8, 0), Rect2(Vector2.ZERO, size))
		var base := Vector2(size.x / 2, 14 + (size.x - 12) * 1.4)
		draw_set_transform(base, 0, Vector2(1, 0.24))
		draw_circle(Vector2.ZERO, size.x * 0.4, Color(0, 0, 0, 0.3))
		draw_set_transform(Vector2.ZERO)
		if card.is_empty():
			draw_string(P.display_font(), Vector2(size.x / 2 - 17, size.y / 2 + 8), "+", HORIZONTAL_ALIGNMENT_CENTER, -1, 48, highlight)
		else:
			var w := size.x - 12
			_face(Rect2(9, 11, w, w * 1.4), font, Color("34363a"))
			_face(Rect2(6, 8, w, w * 1.4), font, Color("242528"), true)
		if card.is_empty(): draw_string(font, Vector2(3, size.y - 9), subtitle, HORIZONTAL_ALIGNMENT_CENTER, size.x - 6, 10, Color("a9afb6"))
		return
	var face := Rect2(3, 3, size.x - 6, (size.x - 6) * 1.4)
	_face(face, font, Color("242528"), true)
	if hot: draw_style_box(P.box(Color.TRANSPARENT, highlight, roundi(face.size.x*7.0/144.0+2), 0), face.grow(2))
	if int(card.get("quantity", 1)) > 1:
		var badge := Rect2(size.x - 46, 12, 37, 28)
		draw_style_box(P.box(Color("242528"), Color("878b90"), 6, 0), badge)
		draw_string(font, badge.position + Vector2(3, 20), "×" + str(int(card.quantity)), HORIZONTAL_ALIGNMENT_CENTER, 31, 15, Color.WHITE)
	if card.get("commander", false) or card.get("section", "") == "Commander":
		var commander_badge := Rect2(8, 12, minf(92, size.x - 16), 22)
		draw_style_box(P.box(Color("245d63"), Color("96c6bc"), 5, 0), commander_badge)
		draw_string(font, commander_badge.position + Vector2(3, 15), "COMMANDER", HORIZONTAL_ALIGNMENT_CENTER, commander_badge.size.x - 6, 11, Color.WHITE)
	draw_string(font, Vector2(2, face.end.y + 21), card.get("name", ""), HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, 12, ink)

func _face(rect: Rect2, font: Font, fill: Color, front: bool = false) -> void:
	if rect.size.x <= 4 or rect.size.y <= 4: return
	var radius := rect.size.x * 7.0 / 144.0
	draw_style_box(P.box(fill, Color("74787d") if front else Color("494e53"), roundi(radius), 0), rect)
	if not front: return
	if texture != null:
		_draw_rounded_image(rect.grow(-2), (rect.size.x-4.0)*7.0/144.0)
	else:
		var accent := P.accent(card.get("color", "C"))
		var inner := rect.grow(-5)
		draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.15), Vector2(inner.size.x, inner.size.y * 0.53)), accent.darkened(0.65))
		draw_circle(inner.get_center() - Vector2(0, inner.size.y * 0.1), inner.size.x * 0.22, accent.darkened(0.45))
		draw_string(font, inner.position + Vector2(2, 15), card.get("name", ""), HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 4, 11, Color.WHITE)
		draw_string(font, inner.position + Vector2(2, inner.size.y * 0.78), card.get("manaCost", ""), HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 4, 12, accent.lightened(0.2))
		draw_multiline_string(font, inner.position + Vector2(2, inner.size.y * 0.88), card.get("typeLine", ""), HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 4, 9, -1, Color("b9ccdb"))

func _draw_rounded_image(rect: Rect2, radius: float) -> void:
	# JPEG scans contain opaque pixels outside the physical card corners.
	# Mask the image geometry while retaining its complete artwork and UVs.
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var centers := [Vector2(rect.end.x-radius, rect.position.y+radius), rect.end-Vector2(radius, radius), Vector2(rect.position.x+radius, rect.end.y-radius), rect.position+Vector2(radius, radius)]
	for corner in range(4):
		for step in range(9):
			var angle := -PI*0.5 + corner*PI*0.5 + step*PI/16.0
			var point: Vector2 = centers[corner]+Vector2(cos(angle), sin(angle))*radius
			points.append(point)
			uvs.append((point-rect.position)/rect.size)
	draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, texture)
