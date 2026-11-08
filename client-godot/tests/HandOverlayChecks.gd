extends RefCounted
## Hand mana-cost pips, the playable glow and their Table settings toggles.
const Card = preload("res://scripts/ui/CardView.gd")
const Pips = preload("res://scripts/ui/ManaPips.gd")

func run(ui: Control, directory: String = "") -> void:
	assert(Array(Pips.parse("{4}{B}")) == ["4", "B"], "Generic mana is one numbered pip, colored mana one pip each")
	assert(Array(Pips.parse("{X}{2}{G}{G}")) == ["X", "2", "G", "G"])
	assert(Array(Pips.parse("{W/U}{B/P}{2/R}{C}")) == ["W/U", "B/P", "2/R", "C"], "Hybrid, Phyrexian and colorless symbols survive parsing")
	assert(Pips.parse("no cost").is_empty() and Pips.parse("{0}").is_empty(), "Lands and free spells draw no pips")

	var saved: Dictionary = ui.ui_layout.duplicate()
	ui._set_ui_layout("mana_overlay", 1.0)
	ui._set_ui_layout("playable_glow", 1.0)
	assert(Card.mana_overlay and Card.playable_glow, "The Table settings toggles drive every card's overlays")
	ui._set_ui_layout("mana_overlay", 0.0)
	assert(not Card.mana_overlay, "The mana overlay switches off")
	ui._set_ui_layout("mana_overlay", 1.0)

	# Playability is Forge's weakSelection on your own non-battlefield cards, only at plain priority.
	var real_snapshot: Dictionary = ui.snapshot
	var real_live: bool = ui.live
	ui.live = true
	ui.snapshot = {"prompt": {"inputKind": "InputPassPriority"}, "asks": []}
	assert(ui._playable({"weakSelection": 1}, 0, "Hand") and ui._playable({"weakSelection": 1}, 0, "Command") and ui._playable({"weakSelection": 1}, 0, "Graveyard"), "Castable hand, commander and graveyard cards are playable")
	assert(not ui._playable({"weakSelection": 0}, 0, "Hand"), "Unaffordable cards are not")
	assert(not ui._playable({"weakSelection": 1}, 0, "Battlefield") and not ui._playable({"weakSelection": 1}, 1, "Hand"), "Battlefield abilities and other seats never glow")
	ui.snapshot = {"prompt": {"inputKind": "InputPayManaOfCostPayment"}, "asks": []}
	assert(not ui._playable({"weakSelection": 1}, 0, "Hand"), "Payment-time mana-source highlights are not playability")
	ui.snapshot = real_snapshot
	ui.live = real_live

	var bubble = preload("res://scripts/ui/ZoneBubble.gd").new()
	ui.add_child(bubble)
	bubble.playable = true
	assert((bubble.get_theme_stylebox("normal") as StyleBoxFlat).border_color == Color("b48cff"), "A zone holding a castable card gets a purple rim")
	bubble.playable = false
	assert((bubble.get_theme_stylebox("normal") as StyleBoxFlat).border_color != Color("b48cff"))
	bubble.queue_free()

	var backdrop := ColorRect.new()
	backdrop.color = Color("1b1f24")
	backdrop.z_index = 140
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(backdrop)
	var samples := [
		{"id": 990001, "name": "Murder", "manaCost": "{1}{B}{B}", "typeLine": "Instant", "zone": "Hand", "owner": 0, "playable": true},
		{"id": 990002, "name": "Craw Wurm", "manaCost": "{4}{G}{G}", "typeLine": "Creature - Wurm", "zone": "Hand", "owner": 0, "playable": false},
		{"id": 990003, "name": "Fireball", "manaCost": "{X}{R}", "typeLine": "Sorcery", "zone": "Hand", "owner": 0, "playable": true},
		{"id": 990004, "name": "Kitchen Finks", "manaCost": "{1}{G/W}{G/W}", "typeLine": "Creature - Ouphe", "zone": "Hand", "owner": 0, "playable": false},
		{"id": 990005, "name": "Forest", "manaCost": "no cost", "typeLine": "Basic Land - Forest", "zone": "Hand", "owner": 0, "playable": true},
	]
	var views: Array = []
	for i in range(samples.size()):
		var view: Control = Card.new()
		view.table_angle = false
		backdrop.add_child(view)
		view.size = ui.HAND_CARD_SIZE
		view.position = Vector2(60 + i * (ui.HAND_CARD_SIZE.x + 36), 120)
		view.update_card(samples[i])
		views.append(view)
	await ui.get_tree().process_frame
	if not directory.is_empty(): await ui._save_frame(directory.path_join("hand-overlay.png"))
	backdrop.queue_free()
	for key in ["mana_overlay", "playable_glow"]: ui._set_ui_layout(key, float(saved.get(key, 0.0)))
	await ui.get_tree().process_frame
	print("PASS: hand mana pips, playable glow and their table settings")
