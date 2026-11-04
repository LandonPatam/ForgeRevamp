extends RefCounted
## Trait glyphs, their hanging placement and the + / - card zoom.
const Icons = preload("res://scripts/ui/TraitIcons.gd")
const Face = preload("res://scripts/ui/CardFace.gd")
const VECTOR_KEYS := ["FLYING", "TRAMPLE", "DEATHTOUCH", "LIFELINK", "VIGILANCE", "HASTE", "HEXPROOF", "WARD", "DEFENDER", "FIRST_STRIKE", "DOUBLE_STRIKE", "INFECT", "WITHER", "MENACE", "SKULK", "SHADOW", "FEAR", "INTIMIDATE", "HORSEMANSHIP", "REACH", "INDESTRUCTIBLE", "SHROUD", "PROTECTION"]

func run(ui: Control, directory: String = "") -> void:
	for key in Face.TRAITS:
		assert(VECTOR_KEYS.has(key), "Every trait the card can show has a glyph: " + key)
	for key in VECTOR_KEYS:
		assert(Icons.has_icon(key) and Face.TRAITS.has(key), "Every requested trait has a glyph: " + key)
		var image: Image = Icons.render_image(key, 48)
		# Menace's eyes are wide and short; every glyph still fills most of one axis.
		assert(image != null and image.get_used_rect().size.x > 24 and image.get_used_rect().size.y > 16, "Glyph SVG must rasterize: " + key)
	await _check_stats_clearance(ui)
	await _check_zoom(ui)
	await check_face_down(ui, directory)
	await check_stacking_and_colors(ui, directory)
	await check_victory_popup(ui)
	if not directory.is_empty(): await _capture(ui, directory)
	print("PASS: trait vector glyphs and + / - card zoom")

func _press(ui: Control, keycode: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = keycode
	ui._unhandled_key_input(event)

## Power/toughness starts past a full row of four traits at every card size.
func _check_stats_clearance(ui: Control) -> void:
	var view = preload("res://scripts/ui/CardView.gd").new()
	ui.add_child(view)
	for card_size in [ui.BASE_CARD_SIZE * ui.MIN_CARD_ZOOM, ui.BASE_CARD_SIZE, ui.BASE_CARD_SIZE * ui.MAX_CARD_ZOOM]:
		view.size = card_size
		await ui.get_tree().process_frame
		var unit: float = view.size.x / 144.0
		var badge: float = view._trait_badge_size()
		var row_end: float = -badge * 0.5 + 4.0 * badge + 3.0 * 2.0 * unit
		var rect: Rect2 = view.stats_rect("3/3", 20)
		assert(rect.position.x >= row_end, "Power/toughness clears four trait icons at card width %f" % view.size.x)
	view.queue_free()
	await ui.get_tree().process_frame

func _check_zoom(ui: Control) -> void:
	var base: Vector2 = ui.BASE_CARD_SIZE
	_press(ui, KEY_EQUAL)
	assert(is_equal_approx(ui.card_zoom, 1.1) and ui.HAND_CARD_SIZE.is_equal_approx(base * 1.1) and ui.TABLE_CARD_SIZE.is_equal_approx(base * 1.1), "+ enlarges hand and table cards together")
	await ui.get_tree().create_timer(0.3).timeout
	for view in ui.cards.values():
		if view.hand_mode: assert(view.size.is_equal_approx(base * 1.1), "Hand cards resize with the zoom")
		elif view.data.get("owner", -1) == 0 and view.data.get("zone", "") == "Battlefield": assert(view.size.is_equal_approx(base * 1.1), "Local table cards resize with the zoom: " + str(view.size))
	for i in range(12): _press(ui, KEY_MINUS)
	assert(is_equal_approx(ui.card_zoom, ui.MIN_CARD_ZOOM), "Zoom stops at its minimum")
	for i in range(12): _press(ui, KEY_KP_ADD)
	assert(is_equal_approx(ui.card_zoom, ui.MAX_CARD_ZOOM), "Zoom stops at its maximum")
	ui._adjust_card_zoom(1.0 - ui.card_zoom)
	assert(is_equal_approx(ui.card_zoom, 1.0) and ui.HAND_CARD_SIZE.is_equal_approx(base))
	await ui.get_tree().create_timer(0.3).timeout

func _capture(ui: Control, directory: String) -> void:
	var sheet := Control.new()
	sheet.z_index = 100
	sheet.position = Vector2.ZERO
	sheet.size = ui.size
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.draw.connect(func():
		sheet.draw_rect(Rect2(Vector2.ZERO, sheet.size), Color("151a20"))
		for i in range(VECTOR_KEYS.size()):
			var key: String = VECTOR_KEYS[i]
			var at := Vector2(40 + (i % 8) * 150, 40 + (i / 8) * 190)
			var color: Color = Face.trait_color(key)
			sheet.draw_style_box(ui.P.box(Color("11171e"), Color.TRANSPARENT, 24, 0), Rect2(at, Vector2(96, 96)))
			Icons.draw_icon(sheet, key, Rect2(at + Vector2(10, 10), Vector2(76, 76)), color)
			for j in range(3):
				var small: float = [16.0, 22.0, 30.0][j]
				var tile := Vector2(at.x + j * 40, at.y + 104)
				sheet.draw_style_box(ui.P.box(Color("11171e"), Color.TRANSPARENT, 5, 0), Rect2(tile, Vector2(small, small)))
				Icons.draw_icon(sheet, key, Rect2(tile, Vector2(small, small)).grow(-small * 0.12), color))
	ui.add_child(sheet)
	await ui._save_frame(directory.path_join("trait-icons-sheet.png"))
	sheet.queue_free()
	await ui.get_tree().process_frame
	var base := {"zone": "Battlefield", "owner": 0, "color": "G", "typeLine": "Creature - Test", "stats": "3/3", "power": 3, "toughness": 3}
	var fixtures := [
		{"id": 9911, "name": "Two Traits", "keywords": ["FLYING", "LIFELINK"]},
		{"id": 9912, "name": "Four Traits", "keywords": ["TRAMPLE", "DEATHTOUCH", "VIGILANCE", "HASTE"]},
		{"id": 9913, "name": "Seven Traits", "keywords": ["FLYING", "TRAMPLE", "HEXPROOF", "WARD", "DEFENDER", "FIRST_STRIKE", "MENACE"]},
		{"id": 9914, "name": "Big Stats", "stats": "10/10", "keywords": ["SHADOW", "SHROUD", "WITHER", "REACH"], "counters": {"P1P1": 2, "LOYALTY": 12, "M1M1": 1, "EVERY_LONG_COUNTER_NAME_FITS": 3}},
	]
	var views: Array = []
	for i in range(fixtures.size()):
		var view = preload("res://scripts/ui/CardView.gd").new()
		ui.add_child(view)
		view.z_index = 90
		view.size = ui.TABLE_CARD_SIZE
		view.position = Vector2(140 + i * 300, 60)
		var value: Dictionary = base.duplicate()
		value.merge(fixtures[i], true)
		view.update_card(value)
		views.append(view)
	await ui.get_tree().create_timer(0.2).timeout
	await ui._save_frame(directory.path_join("trait-icons-cards.png"))
	var source = views[2]
	source.hover_active = true
	ui._card_hovered(source.data, source)
	ui._sync_raised_card()
	await ui.get_tree().process_frame
	assert(ui.inspection_traits.get_child_count() == 7, "The magnified card lists every trait underneath")
	assert(ui.inspection_traits.get_global_rect().end.y <= ui.size.y, "The trait list stays on screen")
	await ui._save_frame(directory.path_join("trait-icons-hover.png"))
	source.hover_active = false
	ui._card_unhovered(source)
	ui._fill_inspection_traits({})
	for view in views: view.queue_free()
	await ui.get_tree().process_frame

## A face-down permanent shows the standard Magic back and its public 2/2, never the real card.
func check_face_down(ui: Control, directory: String) -> void:
	var view = preload("res://scripts/ui/CardView.gd").new()
	ui.add_child(view)
	view.z_index = 90
	view.size = ui.TABLE_CARD_SIZE
	view.position = Vector2(160, 120)
	view.update_card({"id": 9920, "name": "", "zone": "Battlefield", "owner": 2, "faceDown": true, "typeLine": "Creature", "power": 2, "toughness": 2, "stats": "2/2", "sick": true, "imageKey": "t:morph|MKC|30"})
	await ui.get_tree().create_timer(0.2).timeout
	assert(view.face.full_image == preload("res://scripts/ui/CardImages.gd").card_back(), "Face-down permanents draw the official card back")
	var back: Image = preload("res://scripts/ui/CardImages.gd").card_back().get_image()
	assert(back.get_size() == Vector2i(360, 500) and back.get_pixel(180, 250).a > 0.99, "The back is the first sleeve tile, fully opaque in its center")
	if not directory.is_empty(): await ui._save_frame(directory.path_join("face-down-back.png"))
	view.queue_free()
	await ui.get_tree().process_frame

const Layout = preload("res://scripts/ui/BattlefieldLayout.gd")

## Identical permanents share a stack key; a different chosen color or a face-down card never does.
func check_stacking_and_colors(ui: Control, directory: String) -> void:
	var forest := {"id": 1, "name": "Forest", "typeLine": "Basic Land - Forest", "tapped": false, "stats": "", "counters": {}, "keywords": []}
	var twin: Dictionary = forest.duplicate(true)
	twin.id = 2
	assert(Layout.stack_key(forest) == Layout.stack_key(twin) and not Layout.stack_key(forest).is_empty(), "Identical cards share a stack key regardless of instance id")
	twin.tapped = true
	assert(Layout.stack_key(forest) == Layout.stack_key(twin), "A tapped card stays in its pile")
	var painted: Dictionary = forest.duplicate(true)
	painted.chosenColors = ["R"]
	assert(Layout.stack_key(forest) != Layout.stack_key(painted), "Different chosen colors stay separate")
	assert(Layout.stack_key({"name": "", "faceDown": true}).is_empty(), "Face-down cards never stack")
	# Chosen color indicator draws on a battlefield card.
	var view = preload("res://scripts/ui/CardView.gd").new()
	ui.add_child(view)
	view.z_index = 90
	view.size = ui.TABLE_CARD_SIZE
	view.position = Vector2(160, 120)
	var value := {"id": 9930, "name": "Hall of the Bandit Lord", "zone": "Battlefield", "owner": 0, "color": "R", "typeLine": "Creature - Test", "stats": "3/3", "power": 3, "toughness": 3, "chosenColors": ["R", "G"], "stackCount": 12}
	view.update_card(value)
	var second = preload("res://scripts/ui/CardView.gd").new()
	ui.add_child(second)
	second.z_index = 90
	second.size = ui.TABLE_CARD_SIZE
	second.position = Vector2(460, 120)
	second.update_card({"id": 9931, "name": "Commander With Tax", "zone": "Command", "owner": 0, "color": "W", "typeLine": "Legendary Creature - Test", "commanderTax": 4, "commander": true})
	await ui.get_tree().create_timer(0.2).timeout
	if not directory.is_empty(): await ui._save_frame(directory.path_join("chosen-color-and-badges.png"))
	view.queue_free()
	second.queue_free()
	await ui.get_tree().process_frame

## The victory announcement has one button and Escape continues, never cancels.
func check_victory_popup(ui: Control) -> void:
	var popup: Control = preload("res://scripts/app/GameConfirm.gd").new()
	popup.title = "Victory!"
	popup.dialog_text = "You won the game."
	popup.ok_button_text = "Continue"
	popup.show_cancel = false
	var result := [0, 0]
	popup.confirmed.connect(func(): result[0] += 1)
	popup.canceled.connect(func(): result[1] += 1)
	ui.add_child(popup)
	popup.popup_centered()
	assert(popup.visible and not popup.cancel.visible and popup.ok.visible, "The victory popup has a single Continue button")
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	popup._unhandled_key_input(escape)
	assert(result[0] == 1 and result[1] == 0, "Escape continues from the victory popup")
	popup.queue_free()
	await ui.get_tree().process_frame
