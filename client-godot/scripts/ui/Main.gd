extends Control
var app_host: Node
var library_return_button: Button
var transition_preview := false
var transition_reveal := false
var presentation_alpha := 1.0
var presentation_tween: Tween
var grid_tween: Tween
var table_backdrop: Control
var preview_overlay_colors: Dictionary = {}
var pending_command_cast := -1
var board_choice: Control
const SelectionDialog = preload("res://scripts/ui/SelectionPanel.gd")
const StartingPlayerDialog = preload("res://scripts/ui/StartingPlayerPanel.gd")
const CoinTossDialog = preload("res://scripts/ui/CoinTossPanel.gd")
var coin_toss_seen: Dictionary = {}
const ManaPaymentDialog = preload("res://scripts/ui/ManaPaymentPanel.gd")
const ManaColorDialog = preload("res://scripts/ui/ManaColorPanel.gd")
var deferred_mana_payment := ""
var target_gallery_requested := false
var target_gallery_on_board := false
const FieldLayout = preload("res://scripts/ui/BattlefieldLayout.gd")
var previous_fields: Dictionary = {}
const P = preload("res://scripts/ui/Palette.gd")
const Card = preload("res://scripts/ui/CardView.gd")
const TraitFace = preload("res://scripts/ui/CardFace.gd")
const TraitIcons = preload("res://scripts/ui/TraitIcons.gd")
const Divider = preload("res://scripts/ui/FieldDivider.gd")
const Library = preload("res://scripts/ui/LibraryPile.gd")
const Avatar = preload("res://scripts/ui/PlayerAvatar.gd")
const Backdrop = preload("res://scripts/ui/TableBackdrop.gd")
const Targets = preload("res://scripts/ui/TargetOverlay.gd")
const Prompt = preload("res://scripts/ui/PromptPanel.gd")
const Opening = preload("res://scripts/ui/OpeningHand.gd")
const StackAttention = preload("res://scripts/ui/StackAttention.gd")
const NotificationSound = preload("res://scripts/ui/NotificationSound.gd")
const IncomingEffect = preload("res://scripts/ui/IncomingEffect.gd")
const ManaCounter = preload("res://scripts/ui/ManaCounter.gd")
const Mock = preload("res://scripts/bridge/MockAdapter.gd")
const Live = preload("res://scripts/bridge/LiveAdapter.gd")
const TURN_STEPS := ["Upkeep", "Draw", "Main 1", "Begin combat", "Declare attackers", "Declare blockers", "First strike damage", "Combat damage", "End combat", "Main 2", "End step", "Cleanup"]
const STEP_NAMES := ["UP", "DR", "M1", "BC", "DA", "DB", "FS", "CD", "EC", "M2", "ET", "CL"]
const DEFAULT_STOPS := ["Main 1", "Declare attackers", "Declare blockers", "Main 2"]
const BASE_CARD_SIZE := Vector2(200, 280.555556)
const MIN_CARD_ZOOM := 0.6
const MAX_CARD_ZOOM := 1.4
## Hand and table cards scale together with the + / - keys.
var card_zoom := 1.0
var HAND_CARD_SIZE := BASE_CARD_SIZE
var TABLE_CARD_SIZE := BASE_CARD_SIZE
const LOCAL_CONTROL_LANE_WIDTH := 88.0
const LOCAL_CONTROL_GAP := 12.0
## Opponent boards auto-pack; leave room for one card's hanging P/T badge and the next card's trait icons.
const OPPONENT_CARD_GAP := 34.0
const LOCAL_CONTROL_GROUP_GAP := 52.0
const LOCAL_MANA_ROW_GAP := 9
const LOCAL_CONTROL_TOP_GAP := 36.0
const LOCAL_CONTROL_ROW_GAP := 4
const MIN_OPPONENT_FIELD_HEIGHT := 484.0
const MIN_LOCAL_FIELD_HEIGHT := 434.0
const MIN_TABLE_HEIGHT := MIN_OPPONENT_FIELD_HEIGHT + 16 + MIN_LOCAL_FIELD_HEIGHT
var adapter = Mock.new()
var live := false
var status_label: Label
var cancel_button: Button
var mana_buttons: Array[Button] = []
var mana_pool: VBoxContainer
var live_buttons: Array[Button] = []
var integration_checks: RefCounted
var snapshot: Dictionary = {}
var sandbox_starting := false
var hand_pick_shade: ColorRect
var hand_pick_panel: PanelContainer
var hand_pick_title: Label
var hand_pick_message: Label
var hand_pick_count: Label
var hand_pick_confirm: Button
var hand_pick_cancel: Button
var sandbox_start: RefCounted
var selected: Dictionary = {}
var targeting := false
var cards: Dictionary = {}
var seen: Dictionary = {}
var rows: Dictionary = {}
var hud: Dictionary = {}
var phase_labels: Dictionary = {}
var board: Control
var board_scroller: ScrollContainer
var free_cards: Control
var dragged_source: Control
var drag_offset := Vector2.ZERO
var drag_origin := Vector2.ZERO
var drag_origin_parent: Node
var manual_positions: Dictionary = {}
var split_pile_cards: Dictionary = {}
var victory_announced := false
var defeat_announced := false
var outcome_screen: Control
var local_pile_members: Dictionary = {}
## Where a right-dragged pile sits, by its identity apart from tap and combat-round state.
var pile_anchors: Dictionary = {}
var pile_drag_ids: Array = []
const UI_LAYOUT_SETTINGS := [
	{"key": "hand_x", "title": "Hand position", "low": "Left", "high": "Right", "min": -800.0, "max": 800.0, "step": 5.0, "default": 0.0},
	{"key": "hand_show", "title": "How much of your hand shows", "low": "Less", "high": "More", "min": -90.0, "max": 90.0, "step": 5.0, "default": 0.0},
	{"key": "library_x", "title": "Library position", "low": "Left", "high": "Right", "min": -800.0, "max": 800.0, "step": 5.0, "default": 0.0},
	{"key": "library_show", "title": "How much of your library shows", "low": "Less", "high": "More", "min": 0.25, "max": 1.0, "step": 0.01, "default": 0.78},
	{"key": "hand_spread", "title": "Hand spread", "low": "Tight", "high": "Wide", "min": 0.5, "max": 2.0, "step": 0.05, "default": 1.0},
	{"key": "hand_count", "title": "Cards shown in hand at once", "low": "Fewer", "high": "More", "min": 3.0, "max": 14.0, "step": 1.0, "default": 8.0},
	{"key": "hand_angle", "title": "Hand angle", "low": "Flat", "high": "Curved", "min": 0.0, "max": 25.0, "step": 1.0, "default": 10.0},
	{"key": "pile_spread", "title": "Space between stacked cards", "low": "Tight", "high": "Wide", "min": 8.0, "max": 60.0, "step": 2.0, "default": 26.0},
	{"key": "pile_tap", "title": "Tapped cards in a stack", "low": "In place", "high": "Aside", "min": 0.0, "max": 1.0, "step": 1.0, "default": 0.0},
	{"key": "hud_x", "title": "Health and portrait position", "low": "Left", "high": "Right", "min": -1600.0, "max": 0.0, "step": 10.0, "default": 0.0},
	{"key": "hud_y", "title": "Health and portrait height", "low": "Lower", "high": "Higher", "min": 0.0, "max": 900.0, "step": 10.0, "default": 0.0},
	{"key": "notify_volume", "title": "Notification volume", "low": "Quiet", "high": "Loud", "min": 0.0, "max": 1.0, "step": 0.05, "default": 0.6},
]
## Table setting "Stack responses": when this seat stops to respond to the stack.
const STACK_MODES := [
	{"name": "Everything", "hint": "Stop for every spell and ability you could respond to."},
	{"name": "Smart", "hint": "Stop for opponents' instants and sorceries, board wipes and anything aimed at your things. Routine abilities pass; effects like \"each opponent loses 1 life\" show a notice."},
	{"name": "Only threats", "hint": "Pass everything except respondable effects aimed at your things and board wipes. Forge still asks for every required choice."},
]
## Built-in library backs: regions of Forge's sleeve atlas. The first is the original back.
const CARD_BACKS := [
	{"name": "Black Lotus", "region": Rect2(360, 1500, 360, 500)},
	{"name": "Classic", "region": Rect2(0, 0, 360, 500)},
	{"name": "Skyline", "region": Rect2(1080, 1500, 360, 500)},
	{"name": "Crossed swords", "region": Rect2(1440, 1500, 360, 500)},
	{"name": "Gold crest", "region": Rect2(720, 1500, 360, 500)},
	{"name": "Spiral", "region": Rect2(0, 1500, 360, 500)},
]
var ui_layout := {"hand_x": 0.0, "hand_show": 0.0, "library_x": 0.0, "library_show": 0.78, "hand_spread": 1.0, "hand_count": 8.0, "hand_angle": 10.0, "pile_spread": 26.0, "pile_tap": 0.0, "hud_x": 0.0, "hud_y": 0.0, "stack_mode": 1.0, "notify_volume": 0.6, "card_back": 0.0, "notify_sound": 0.0, "mana_overlay": 0.0, "playable_glow": 1.0}
var play_positions: Dictionary = {}
var pending_returns: Dictionary = {}
var rail: VBoxContainer
var turn_label: Label
var phase_title: Label
var library_pile: Control
var library_count: Label
var library_ghost: Control
var hand_copies: Dictionary = {}
var primary: Button
var return_button: Button
var hand_root: Control
var hand_previous: Button
var hand_next: Button
var hand_offset := 0
var hand_order: Array = []
var hand_gap_index := -1
var hand_fan_width := 300.0
var pending_hand_slot := -1
var pending_hand_origin := Vector2.INF
var library_draw_pending := false
var hand_focus_id := -1
var synthetic_hover := false
var capture_size := Vector2i(1600, 1000)
var player_areas: Dictionary = {}
var step_panels: Dictionary = {}
var phase_stops: Dictionary = {}
var opponent_ratio := 0.5
var field_ratio := 0.46
var table_minimum_height := MIN_TABLE_HEIGHT
var opponent_divider: Control
var local_divider: Control
var layout_guard: Node
var layout_retry_button: Button
var layout_recovery: Control
var layout_process_modes: Dictionary = {}
var layout_paused := false
var client_diagnostics: RefCounted
var verification_mode := false
var hovered_source: Control
var raised_card: Control
var prompt_title: Label
var prompt_body: Label
var stack_box: VBoxContainer
var stack_header: Label
var stack_attention: Control
var notify_sound: AudioStreamPlayer
var stack_waiting := false
var token_artwork: Node
var stack_scroll: ScrollContainer
var incoming_effect: Control
## "Counterspell -> Wrath of God": target choices for a spell you are casting at the stack.
var response_target: Control
var interaction_panel: Control
var decision_scroll: ScrollContainer
var rail_space: Control
var inspection: Control
var inspection_card: Control
var inspection_traits: VBoxContainer
var inspection_traits_panel: Panel
var targeting_overlay: Control
var modal: Control
var zone_panel: PanelContainer
var zone_title: Label
var zone_scroll: ScrollContainer
var zone_content: Control
var zone_empty: Label
var zone_views: Dictionary = {}
var zone_owner := -1
var zone_name := ""
var zone_expansion := 1.0
var zone_animation: Tween
var zone_card_size := TABLE_CARD_SIZE
var opening_hand: Control
var opening_hand_released := false
var modal_center: CenterContainer
var modal_panel: Control
var decision_board_button: Button
var native_reveal := false
var open_ask := -1
var hud_values: Dictionary = {}
var toast: Label
var toast_tween: Tween

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--sandbox":
			# tools/sandbox.mjs: click through startup onto the prepared board, then play by hand.
			sandbox_starting = true
			sandbox_start = load("res://tests/SandboxStart.gd").new()
			sandbox_start.run.call_deferred(self)
		if arg == "--live-check":
			integration_checks = load("res://tests/LiveIntegration.gd").new()
			integration_checks.run.call_deferred(self)
		if arg.begins_with("--live="):
			live = true
			adapter = Live.new()
			adapter.url = arg.trim_prefix("--live=")
	verification_mode = Array(OS.get_cmdline_user_args()).any(func(arg): return arg in ["--smoke", "--live-check", "--app-check", "--hand-hover-check", "--layout-loop-check"] or arg.begins_with("--visual-checks=") or arg.begins_with("--capture="))
	_load_table_settings()
	theme = P.make_theme()
	table_backdrop = Backdrop.new()
	table_backdrop.cinematic_tint = 1.0 if transition_preview else 0.0
	table_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(table_backdrop)
	_build_shell()
	token_artwork = preload("res://scripts/ui/RuntimeArtwork.gd").new()
	if is_instance_valid(app_host): token_artwork.shared_images = app_host.images
	token_artwork.network_enabled = not verification_mode or "--token-online-images" in OS.get_cmdline_user_args()
	add_child(token_artwork)
	if live:
		_update_live_actions()
	RenderingServer.frame_pre_draw.connect(_prepare_render)
	_sync_transition_preview()
	adapter.state_changed.connect(_apply_state)
	adapter.feedback.connect(_notify)
	adapter.action_rejected.connect(_reject_card_action)
	adapter.status_changed.connect(func(message): status_label.text = message)
	adapter.session_reset.connect(_clear_live_session)
	if not verification_mode and ProjectSettings.get_setting("application/config/client_diagnostics", false):
		client_diagnostics = preload("res://scripts/app/ClientDiagnostics.gd").new()
		client_diagnostics.start(self)
	layout_guard = preload("res://scripts/ui/LayoutLoopGuard.gd").new()
	add_child(layout_guard)
	layout_guard.tripped.connect(_pause_layout_loop)
	layout_guard.watch(self)
	adapter.start()
	_intent("phase_stops", {"stops": phase_stops})
	get_window().focus_exited.connect(_cancel_pointer_gesture)
	resized.connect(_layout_board)
	_layout_board.call_deferred()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_capture.call_deferred(arg.trim_prefix("--capture="))
		if arg == "--smoke":
			_smoke.call_deferred()
		if arg == "--hand-hover-check":
			_hand_hover_check.call_deferred()
		if arg == "--layout-loop-check":
			_layout_loop_check.call_deferred()
		if arg.begins_with("--visual-checks="):
			_visual_checks.call_deferred(arg.trim_prefix("--visual-checks="))

func _label(text: String, font_size: int = 14, color: Color = P.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", maxi(12, font_size))
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, callback: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	button.tooltip_text = tooltip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE
	return button

func _terminal_button(text: String, callback: Callable, tooltip: String = "", primary_action: bool = false) -> Button:
	var button := _button(text, callback, tooltip)
	preload("res://scripts/ui/TerminalStyle.gd").button(button, primary_action)
	return button

func _intent(action: String, extra: Dictionary = {}) -> void:
	if layout_paused: return
	if live and action == "card" and snapshot.get("connectionReady", false) and snapshot.get("prompt", {}).get("inputKind", "") == "InputPassPriority":
		pending_command_cast = int(extra.get("id", -1)) if snapshot.players[0].zones.Command.any(func(card): return int(card.id) == int(extra.get("id", -1))) else -1
	if action == "cancel": pending_command_cast = -1
	if live and action == "ok" and snapshot.get("connectionReady", false) and snapshot.get("asks", []).is_empty() and snapshot.get("prompt", {}).get("inputKind", "") == "InputPassPriority" and snapshot.prompt.get("okEnabled", false) and not snapshot.get("stack", []).is_empty():
		var stack_id := int(snapshot.stack[0].id)
		incoming_effect.acknowledge_stack(stack_id)
		adapter.acknowledge_effect(stack_id)
		return
	var intent := extra.duplicate()
	intent.action = action
	adapter.send_intent(intent)

func set_transition_preview(value: bool) -> void:
	if presentation_tween != null: presentation_tween.kill()
	if grid_tween != null: grid_tween.kill()
	transition_preview = value
	transition_reveal = false
	presentation_alpha = 0.0 if value else 1.0
	if is_instance_valid(table_backdrop): table_backdrop.cinematic_tint = 1.0 if value else 0.0
	_sync_transition_preview()

func begin_transition_zoom() -> void:
	if not is_instance_valid(table_backdrop): return
	if grid_tween != null: grid_tween.kill()
	grid_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	grid_tween.tween_property(table_backdrop, "cinematic_tint", 0.0, 1.1)

func fade_in_game_ui() -> void:
	transition_preview = false
	transition_reveal = true
	presentation_alpha = 0.0
	table_backdrop.cinematic_tint = 0.0
	_sync_transition_preview()
	presentation_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	presentation_tween.tween_property(self, "presentation_alpha", 1.0, 0.65)
	await presentation_tween.finished
	transition_reveal = false
	_sync_transition_preview()
	if live and not snapshot.is_empty(): _present_card_selection()

func _sync_transition_preview() -> void:
	# Mask every foreground root, including cards, portraits, rail and field
	# borders. Engine visibility/decision state continues normally underneath.
	if is_instance_valid(toast): toast.self_modulate.a = presentation_alpha if transition_preview or transition_reveal else 1.0
	if transition_preview or transition_reveal:
		for overlay in get_children():
			if not overlay is CanvasItem or overlay == table_backdrop or overlay == toast: continue
			if not preview_overlay_colors.has(overlay): preview_overlay_colors[overlay] = overlay.modulate
			overlay.modulate = preview_overlay_colors[overlay]
			overlay.modulate.a *= presentation_alpha
	else:
		for overlay in preview_overlay_colors:
			if is_instance_valid(overlay): overlay.modulate = preview_overlay_colors[overlay]
		preview_overlay_colors.clear()

func _build_shell() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	status_label = _label("", 12)
	status_label.hide()
	add_child(status_label)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	column.add_child(content)
	board_scroller = ScrollContainer.new()
	board_scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board_scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	content.add_child(board_scroller)
	board = Control.new()
	board.custom_minimum_size.y = table_minimum_height
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.mouse_filter = Control.MOUSE_FILTER_PASS
	board.resized.connect(_layout_board)
	board_scroller.add_child(board)
	for id in [0, 1, 2]:
		_make_player_area(id)
	for key in ["enemy1", "enemy2", "lands1", "lands2", "your_creatures", "your_lands", "hand"]:
		_make_row(key)
	for id in [0, 1, 2]:
		_make_hud(id)
	# Input order follows child order rather than z_index. Keep phase controls
	# above card-row containers, including while their minimum sizes shrink.
	for id in [0, 1, 2]:
		board.move_child(step_panels[id].panel, -1)
	opponent_divider = Divider.new()
	opponent_divider.moved.connect(_resize_fields.bind(false))
	opponent_divider.finished.connect(_save_table_settings)
	board.add_child(opponent_divider)
	local_divider = Divider.new()
	local_divider.horizontal = true
	local_divider.moved.connect(_resize_fields.bind(true))
	local_divider.finished.connect(_save_table_settings)
	board.add_child(local_divider)
	free_cards = Control.new()
	free_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	free_cards.z_index = 5
	add_child(free_cards)
	var rail_panel := preload("res://scripts/ui/TerminalRail.gd").new()
	rail_panel.custom_minimum_size.x = 248
	content.add_child(rail_panel)
	rail = VBoxContainer.new()
	rail.add_theme_constant_override("separation", 8)
	rail_panel.add_child(rail)
	var terminal = preload("res://scripts/ui/TerminalStyle.gd")
	rail.add_child(_terminal_button("Table settings", _show_table_settings, "Move your hand, library and health panel. Your layout is saved for every game."))
	rail.add_child(_label("COMMANDER / TERMINAL",12,terminal.MUTED))
	turn_label = _label("Turn 1", 30, terminal.INK)
	turn_label.add_theme_font_override("font", terminal.font())
	rail.add_child(turn_label)
	phase_title = _label("", 18, terminal.ACCENT)
	phase_title.add_theme_font_override("font", terminal.font())
	phase_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rail.add_child(phase_title)
	rail.add_child(HSeparator.new())
	decision_scroll = ScrollContainer.new()
	decision_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	decision_scroll.custom_minimum_size.y = 120
	decision_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(decision_scroll)
	decision_scroll.hide()
	stack_header = _label("STACK / ACTIVITY", 12, terminal.MUTED)
	var feed_font := SystemFont.new()
	feed_font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono"])
	stack_header.add_theme_font_override("font", feed_font)
	rail.add_child(stack_header)
	stack_box = preload("res://scripts/ui/StackActivityFeed.gd").new()
	stack_box.item_selected.connect(func(item): _select_stack_card(item if live else item.card))
	stack_box.custom_minimum_size.y = 43
	stack_scroll = ScrollContainer.new()
	stack_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack_scroll.custom_minimum_size.y = 120
	stack_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_child(stack_scroll)
	stack_scroll.add_child(stack_box)
	rail_space = Control.new()
	rail_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(rail_space)
	inspection = Control.new()
	inspection.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspection.z_index = 18
	inspection.hide()
	add_child(inspection)
	inspection_card = Card.new()
	inspection_card.inspection = true
	inspection_card.show_traits = false
	inspection_card.table_angle = false
	inspection_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspection.add_child(inspection_card)
	inspection_traits_panel = Panel.new()
	inspection_traits_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspection_traits_panel.add_theme_stylebox_override("panel", P.box(Color("11171e"), Color("2c3a40"), 8, 0))
	inspection_traits_panel.hide()
	inspection.add_child(inspection_traits_panel)
	inspection_traits = VBoxContainer.new()
	inspection_traits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspection_traits.add_theme_constant_override("separation", 0)
	inspection.add_child(inspection_traits)
	prompt_title = _label("You have priority", 18, P.TEXT)
	prompt_title.hide()
	add_child(prompt_title)
	prompt_body = _label("Select a card to explore the table.", 12, P.MUTED)
	prompt_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_body.custom_minimum_size.y = 38
	prompt_body.add_theme_font_override("font", terminal.font())
	prompt_body.add_theme_color_override("font_color", terminal.MUTED)
	rail.add_child(prompt_body)
	primary = _terminal_button("Pass priority  →", _primary_action, "Advance the scripted demo · Space", true)
	primary.custom_minimum_size.y = 48
	rail.add_child(primary)
	return_button = _terminal_button("Return to hand", _return_selected, "Return an unused play when the adapter permits it")
	return_button.hide()
	rail.add_child(return_button)
	if live:
		cancel_button = _terminal_button("Cancel", _secondary_action)
		rail.add_child(cancel_button)
		var undo := _terminal_button("Undo last action", func(): _intent("undo"), "Request Forge's undo; Forge decides whether it is allowed")
		rail.add_child(undo)
		live_buttons.append(undo)
	var cleanup_button := _terminal_button("Clean up board", _clean_up_board, "Stack identical permanents. Nothing else moves, and cards you move or play afterward stay where you put them.")
	rail.add_child(cleanup_button)
	mana_pool = VBoxContainer.new()
	mana_pool.add_theme_constant_override("separation", LOCAL_MANA_ROW_GAP)
	mana_pool.z_index = 25
	add_child(mana_pool)
	var mana_codes := [1, 2, 4, 8, 16, 0]
	for i in range(6):
		var counter := ManaCounter.new()
		counter.index = i
		counter.pressed.connect(_use_mana.bind(mana_codes[i]))
		mana_pool.add_child(counter)
		mana_buttons.append(counter)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	var note := Control.new()
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	footer.add_child(_label("SPACE  Pass turn    Q  Advance    D  Draw    T  Tap / attack    H  Help", 10, P.MUTED))
	# Picking from your hand (discard, put back): the table dims and stops taking clicks; the hand,
	# a later sibling with a higher z_index, stays bright and usable.
	hand_pick_shade = ColorRect.new()
	hand_pick_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hand_pick_shade.color = Color(0.01, 0.015, 0.02, 0.66)
	hand_pick_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	hand_pick_shade.z_index = 19
	hand_pick_shade.hide()
	add_child(hand_pick_shade)
	hand_root = Control.new()
	hand_root.mouse_filter = Control.MOUSE_FILTER_PASS
	hand_root.z_index = 20
	hand_root.gui_input.connect(_hand_scroll)
	add_child(hand_root)
	_build_hand_pick_panel()
	library_pile = Library.new()
	library_pile.z_index = 22
	library_pile.tooltip_text = "Library / drag a face-down card into your hand"
	library_pile.drag_started.connect(_library_drag_started)
	library_pile.drag_moved.connect(_library_drag_moved)
	library_pile.drag_finished.connect(_library_drag_finished)
	add_child(library_pile)
	library_count = _label("", 13, P.TEXT)
	library_count.z_index = 22
	library_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(library_count)
	library_ghost = Library.new()
	library_ghost.ghost = true
	library_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	library_ghost.z_index = 75
	library_ghost.size = HAND_CARD_SIZE
	library_ghost.hide()
	add_child(library_ghost)
	_apply_table_style()
	step_panels[0].panel.reparent(self)
	step_panels[0].panel.z_index = 25
	hud[0].reparent(self)
	hud[0].z_index = 20
	hand_previous = _button("<", func(): _scroll_hand(-1), "Previous cards / mouse wheel")
	hand_previous.z_index = 21
	add_child(hand_previous)
	hand_next = _button(">", func(): _scroll_hand(1), "Next cards / mouse wheel")
	hand_next.z_index = 21
	add_child(hand_next)
	targeting_overlay = Targets.new()
	targeting_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	targeting_overlay.z_index = 60
	add_child(targeting_overlay)
	raised_card = Card.new()
	raised_card.inspection = true
	raised_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raised_card.z_index = 40
	raised_card.gui_input.connect(_raised_hand_input)
	add_child(raised_card)
	raised_card.hide()
	toast = _label("", 14, P.TEXT)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.z_index = 65
	add_child(toast)
	opening_hand = Opening.new()
	opening_hand.z_index = 80
	add_child(opening_hand)
	opening_hand.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	opening_hand.decision.connect(func(action): _intent(action))
	opening_hand.card_chosen.connect(func(id): _intent("card", {"id": id}))
	opening_hand.inspect_requested.connect(_show_card_detail)
	opening_hand.hand_confirmed.connect(func():
		opening_hand_released = true
		_layout_board())
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.z_index = 100
	modal.hide()
	add_child(modal)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.03, 0.04, 0.84)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_dismiss_modal())
	modal.add_child(shade)
	modal_center = CenterContainer.new()
	modal_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(modal_center)
	decision_board_button = _terminal_button("Return to decision", _toggle_decision_board, "Go back to the decision you were making (Escape).", true)
	decision_board_button.add_theme_font_size_override("font_size", 24)
	decision_board_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	decision_board_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	decision_board_button.clip_text = true
	# See-through over the table so covered cards stay readable; solid while pointed at.
	decision_board_button.mouse_entered.connect(func(): _pulse_decision_board(true))
	decision_board_button.mouse_exited.connect(func(): _pulse_decision_board(false))
	decision_board_button.hide()
	modal.add_child(decision_board_button)
	notify_sound = NotificationSound.new()
	add_child(notify_sound)
	if not verification_mode and not get_window().files_dropped.is_connected(_files_dropped):
		get_window().files_dropped.connect(_files_dropped)
	stack_attention = StackAttention.new()
	stack_attention.stack = stack_box
	add_child(stack_attention)
	stack_attention.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	incoming_effect = IncomingEffect.new()
	add_child(incoming_effect)
	incoming_effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	incoming_effect.blocked = func(): return modal.visible or opening_hand.visible or (live and snapshot.get("prompt", {}).get("inputKind", "") not in ["InputPassPriority", "InputLockUI", ""])
	incoming_effect.inspect_requested.connect(_show_card_detail)
	incoming_effect.card_view = func(id: int) -> Control: return cards.get(id)
	incoming_effect.player_view = func(engine_id: int) -> Control:
		for seat in hud_values:
			if seat < snapshot.get("players", []).size() and int(snapshot.players[seat].get("engineId", seat)) == engine_id: return hud_values[seat].portrait
		return null
	response_target = preload("res://scripts/ui/ResponseTarget.gd").new()
	add_child(response_target)
	response_target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	response_target.answered.connect(func(id: int, value: Variant): _intent("answer", {"id": id, "value": value}))
	response_target.stack_rect = func(id: int) -> Rect2:
		var entry: Control = stack_box.entries.get(id)
		return entry.get_global_rect() if is_instance_valid(entry) and entry.is_visible_in_tree() else Rect2()
	incoming_effect.acknowledged.connect(func(stack_id: int):
		if live: adapter.acknowledge_effect(stack_id))
	interaction_panel = preload("res://scripts/ui/InteractionPanel.gd").new()
	stack_attention.decision = interaction_panel
	add_child(interaction_panel)
	interaction_panel.rail_host = decision_scroll
	interaction_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interaction_panel.action_requested.connect(func(action):
		_primary_action() if action == "ok" else _secondary_action())
	interaction_panel.entity_selected.connect(func(action, id): _intent(action, {"id": id}))
	interaction_panel.zone_view = func(id: int) -> Control:
		if snapshot.get("players", []).is_empty() or not hud_values.has(0): return null
		for zone_name in hud_values[0].zones:
			if snapshot.players[0].get("zones", {}).get(zone_name, []).any(func(card): return int(card.get("id", -1)) == id): return hud_values[0].zones[zone_name]
		return null
	interaction_panel.modes_answered.connect(func(id, picks): _intent("answer", {"id": id, "value": picks}))
	interaction_panel.resolve_requested.connect(func(id):
		if int(incoming_effect.active.get("stackId", -1)) == id: incoming_effect.dismiss()
		else: adapter.acknowledge_effect(id))
	interaction_panel.review_requested.connect(func():
		incoming_effect.review()
		_present_interaction())
	interaction_panel.browse_requested.connect(func():
		target_gallery_requested = true
		target_gallery_on_board = false
		_present_card_selection()
		_present_interaction())
	incoming_effect.response_requested.connect(func(_id): _present_interaction())
	board_choice = preload("res://scripts/ui/BoardChoice.gd").new()
	board_choice.rail_host = decision_scroll
	stack_attention.recipient_decision = board_choice
	board_choice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_choice.answered.connect(func(id, value): _intent("answer", {"id": id, "value": value}))
	add_child(board_choice)
	board_choice.visibility_changed.connect(_present_interaction)


func _present_interaction() -> void:
	if not is_instance_valid(interaction_panel): return
	var popup_showing: bool = incoming_effect.showing() and snapshot.get("prompt", {}).get("inputKind", "") == "InputPassPriority" and not incoming_effect.responding.has(int(incoming_effect.active.get("stackId", -1)))
	var avatars := {}
	for seat in hud_values: avatars[seat] = hud_values[seat].portrait
	interaction_panel.present(snapshot, not live or modal.visible or opening_hand.visible or popup_showing or board_choice.visible or hand_pick_panel.visible, cards, avatars)
	var rail_decision: bool = interaction_panel.uses_stack_rail() or board_choice.visible
	decision_scroll.visible = rail_decision
	rail_space.visible = not rail_decision and stack_box.entries.is_empty()
	var show_stack: bool = not rail_decision or interaction_panel.keeps_stack_visible()
	stack_scroll.visible = show_stack
	stack_header.visible = show_stack
	if live:
		prompt_body.visible = not rail_decision and not StartingPlayerDialog.needs_selection(snapshot)
		primary.visible = not rail_decision
		# A finished or lost game has no Forge cancel; don't leave a blank button.
		cancel_button.visible = not rail_decision and _match_outcome().is_empty()

func _load_table_settings() -> void:
	phase_stops.clear()
	for seat in range(4):
		phase_stops[seat] = {}
		for step in TURN_STEPS:
			phase_stops[seat][step] = step in DEFAULT_STOPS
	if verification_mode:
		return
	var config := ConfigFile.new()
	if config.load("user://table-layout.cfg") == OK:
		opponent_ratio = clampf(float(config.get_value("fields", "opponents", 0.5)), 0.25, 0.75)
		field_ratio = clampf(float(config.get_value("fields", "local", 0.46)), 0.25, 0.75)
		table_minimum_height = clampf(float(config.get_value("fields", "height", MIN_TABLE_HEIGHT)), MIN_TABLE_HEIGHT, 2400)
		if config.get_value("phases", "defaults_version", 0) == 2:
			phase_stops = config.get_value("phases", "stops", phase_stops)
		_read_ui_layout(config)

func _read_ui_layout(config: ConfigFile) -> void:
	for setting in UI_LAYOUT_SETTINGS:
		ui_layout[setting.key] = clampf(float(config.get_value("ui", setting.key, setting.default)), setting.min, setting.max)
	ui_layout.card_back = float(clampi(int(config.get_value("ui", "card_back", 0)), 0, CARD_BACKS.size() - 1))
	ui_layout.notify_sound = float(clampi(int(config.get_value("ui", "notify_sound", 0)), 0, NotificationSound.CHOICES.size() - 1))
	# The earlier On/Off "auto_resolve" setting maps to Only threats.
	var legacy_mode := 2 if float(config.get_value("ui", "auto_resolve", 0.0)) >= 0.5 else 1
	ui_layout.stack_mode = float(clampi(int(config.get_value("ui", "stack_mode", legacy_mode)), 0, STACK_MODES.size() - 1))
	ui_layout.mana_overlay = 1.0 if float(config.get_value("ui", "mana_overlay", 0.0)) >= 0.5 else 0.0
	ui_layout.playable_glow = 1.0 if float(config.get_value("ui", "playable_glow", 1.0)) >= 0.5 else 0.0
	_apply_table_style()

## Pushes pile and card-back preferences to the shared layout and library views.
func _apply_table_style() -> void:
	FieldLayout.pile_step = float(ui_layout.pile_spread)
	FieldLayout.tap_aside = float(ui_layout.pile_tap) >= 0.5
	var overlays_changed: bool = Card.mana_overlay != (float(ui_layout.mana_overlay) >= 0.5) or Card.playable_glow != (float(ui_layout.playable_glow) >= 0.5)
	Card.mana_overlay = float(ui_layout.mana_overlay) >= 0.5
	Card.playable_glow = float(ui_layout.playable_glow) >= 0.5
	if overlays_changed:
		for view in cards.values() + zone_views.values() + hand_copies.values():
			if is_instance_valid(view): view._redraw_layers()
		if not snapshot.is_empty() and snapshot.has("players"):
			for p in snapshot.players:
				if hud_values.has(p.id):
					for zone in hud_values[p.id].zones:
						hud_values[p.id].zones[zone].playable = Card.playable_glow and p.zones[zone].any(func(card): return _playable(card, int(p.id), zone))
						hud_values[p.id].zones[zone].castable_now = Card.playable_glow and p.zones[zone].any(func(card): return _playable(card, int(p.id), zone) and _ready_now(card, zone))
	if adapter != null and "stack_mode" in adapter:
		adapter.stack_mode = int(ui_layout.stack_mode)
		adapter.auto_resolve_all = int(ui_layout.stack_mode) == 2
		if not snapshot.is_empty(): adapter._publish()
	if notify_sound != null: notify_sound.configure(int(ui_layout.notify_sound), float(ui_layout.notify_volume))
	var back := AtlasTexture.new()
	back.atlas = preload("res://assets/forge-sleeves.png")
	back.region = CARD_BACKS[clampi(int(ui_layout.card_back), 0, CARD_BACKS.size() - 1)].region
	back.filter_clip = true
	for pile in [library_pile, library_ghost]:
		if pile != null and "back" in pile:
			pile.back = back
			pile.queue_redraw()

func _save_table_settings() -> void:
	if verification_mode:
		return
	var config := ConfigFile.new()
	for key in ui_layout: config.set_value("ui", key, ui_layout[key])
	config.set_value("fields", "opponents", opponent_ratio)
	config.set_value("fields", "local", field_ratio)
	config.set_value("fields", "height", table_minimum_height)
	config.set_value("phases", "stops", phase_stops)
	config.set_value("phases", "defaults_version", 2)
	config.save("user://table-layout.cfg")

func _resize_fields(pointer: Vector2, horizontal: bool) -> void:
	if pointer == Vector2.INF:
		if horizontal:
			field_ratio = 0.46
			table_minimum_height = MIN_TABLE_HEIGHT
			board.custom_minimum_size.y = table_minimum_height
		else:
			opponent_ratio = 0.5
	else:
		var local := board.get_global_transform().affine_inverse() * pointer
		if horizontal:
			var requested := maxf(_minimum_opponent_height(), local.y - 8)
			table_minimum_height = clampf(requested + 16 + MIN_LOCAL_FIELD_HEIGHT, MIN_TABLE_HEIGHT, 2400)
			board.custom_minimum_size.y = table_minimum_height
			field_ratio = requested / (maxf(board.size.y, board.custom_minimum_size.y) - 16)
		else:
			var minimum := minf(352, (board.size.x - 16) * 0.4)
			opponent_ratio = clampf(local.x - 8, minimum, board.size.x - 16 - minimum) / (board.size.x - 16)
	_layout_board()

func _set_phase_stop(id: int, step: String, enabled: bool) -> void:
	if live and (not snapshot.get("connectionReady", false) or not snapshot.has("phaseStops")):
		_update_turn_steps()
		return
	if not phase_stops.has(id):
		phase_stops[id] = {}
	phase_stops[id][step] = enabled
	_update_turn_steps()
	if live:
		_intent("phase_stop", {"id": id, "phase": Live.PHASES.find_key(step), "enabled": enabled})
		return
	_intent("phase_stops", {"stops": phase_stops})
	_save_table_settings()

func _make_player_area(id: int) -> void:
	var area := Panel.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(area)
	player_areas[id] = area
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var spacing := StyleBoxEmpty.new()
	spacing.set_content_margin_all(0 if id == 0 else 8)
	panel.add_theme_stylebox_override("panel", spacing)
	board.add_child(panel)
	panel.z_index = 10
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	if id == 0: column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(column)
	var grid := GridContainer.new()
	grid.columns = 1 if id == 0 else 12
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", LOCAL_CONTROL_ROW_GAP if id == 0 else 4)
	if id == 0: grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(grid)
	phase_labels[id] = {}
	for i in range(TURN_STEPS.size()):
		var step: String = TURN_STEPS[i]
		var button := Button.new()
		button.text = STEP_NAMES[i]
		button.toggle_mode = true
		button.disabled = live
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if id == 0: button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(48, 20) if id == 0 else Vector2(22, 24)
		button.add_theme_font_size_override("font_size", 14 if id == 0 else 11)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_connect_phase_button(button, id, step)
		grid.add_child(button)
		phase_labels[id][step] = button
	step_panels[id] = {"panel": panel}

func _connect_phase_button(button: Button, id: int, step: String) -> void:
	button.toggled.connect(func(enabled): _set_phase_stop(id, step, enabled))

func _update_turn_steps() -> void:
	if snapshot.is_empty():
		return
	for id in phase_labels:
		if id >= snapshot.players.size(): continue
		var active: bool = snapshot.game.activePlayer == id
		var choosing: bool = targeting and id != 0
		var field_appearance := [active, choosing]
		if player_areas[id].get_meta("appearance", []) != field_appearance:
			var field_style := P.box(Color(0.07, 0.065, 0.035, 0.38) if choosing else Color(0.025, 0.03, 0.04, 0.32), Color.WHITE if active else Color("64676d"), 8, 0)
			if active:
				field_style.set_border_width_all(2)
			player_areas[id].add_theme_stylebox_override("panel", field_style)
			player_areas[id].set_meta("appearance", field_appearance)
		for step in phase_labels[id]:
			var current: bool = active and step == snapshot.game.phase
			var enabled: bool = phase_stops.get(id, {}).get(step, step in DEFAULT_STOPS)
			var button: Button = phase_labels[id][step]
			button.disabled = live and (not snapshot.get("connectionReady", false) or not snapshot.has("phaseStops"))
			button.set_pressed_no_signal(enabled)
			button.tooltip_text = step + (" / Stop ON. Click to auto-pass this step." if enabled else " / Stop OFF. Click to stop at this step.")
			var appearance := [current, enabled]
			if button.get_meta("appearance", []) == appearance:
				continue
			button.set_meta("appearance", appearance)
			var fill := Color("7651a8") if current else Color("146d76") if enabled else Color("132c30")
			var border := Color("bd98ed") if current else Color("40a4ad") if enabled else Color("315057")
			for style in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
				button.add_theme_stylebox_override(style, P.box(fill.lightened(0.12) if style.begins_with("hover") else fill, border, 3, 2))
			for color_name in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_disabled_color"]:
				button.add_theme_color_override(color_name, Color.WHITE if current or enabled else P.MUTED)

func _make_row(key: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	board.add_child(scroll)
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(inner)
	rows[key] = {"scroll": scroll, "inner": inner}

func _make_hud(id: int) -> void:
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	board.add_child(panel)
	var portrait := Avatar.new()
	portrait.position = Vector2(0, 24)
	portrait.size = Vector2(136, 62)
	portrait.activated.connect(_choose_player.bind(id))
	panel.add_child(portrait)
	var text := VBoxContainer.new()
	text.position = Vector2(0, 0)
	text.size = Vector2(136, 22)
	text.add_theme_constant_override("separation", 3)
	panel.add_child(text)
	var name_label := _label("", 15)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = 130
	var terminal_font := SystemFont.new()
	terminal_font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono"])
	name_label.add_theme_font_override("font", terminal_font)
	name_label.add_theme_color_override("font_color", Color("d8d3bd"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(name_label)
	var info := _label("", 12, P.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.add_child(info)
	var zones := HBoxContainer.new()
	zones.z_index = 12
	zones.add_theme_constant_override("separation", 5)
	zones.mouse_filter = Control.MOUSE_FILTER_PASS
	board.add_child(zones)
	var zone_buttons: Dictionary = {}
	for zone in ["Command", "Graveyard", "Exile"]:
		var button := preload("res://scripts/ui/ZoneBubble.gd").new()
		button.kind = zone
		button.pressed.connect(_show_zone.bind(id, zone))
		zones.add_child(button)
		zone_buttons[zone] = button
	hud[id] = panel
	hud_values[id] = {"portrait": portrait, "name": name_label, "info": info, "zones": zone_buttons, "zone_tray": zones}

func _apply_state(value: Dictionary) -> void:
	if client_diagnostics != null: client_diagnostics.capture(value, self)
	snapshot = value
	if layout_paused: return
	# Reconnecting to an established game needs no new opening-hand ceremony.
	if live and (snapshot.get("openingHandComplete", false) or (not opening_hand.active and int(snapshot.game.get("turn", 0)) > 0 and not str(snapshot.game.get("phase", "")).is_empty() and not snapshot.game.get("mulligan", false) and snapshot.prompt.get("inputKind", "") not in ["InputConfirmMulligan", "InputLondonMulligan"])):
		opening_hand_released = true
	for id in range(snapshot.players.size()):
		if not player_areas.has(id):
			_make_player_area(id)
			_make_row("enemy" + str(id))
			_make_row("lands" + str(id))
			_make_hud(id)
			board.move_child(step_panels[id].panel, -1)
	if token_artwork != null:
		token_artwork.match_active = not is_instance_valid(app_host) or not app_host.parked
		token_artwork.observe(snapshot)
	_close_accepted_commander_browser()
	_announce_returned_lands()
	incoming_effect.present(snapshot)
	stack_attention.present(snapshot)
	# Sound once when the stack starts waiting on this player, not on every snapshot.
	if stack_attention.attention and not stack_waiting and notify_sound != null: notify_sound.play_cue()
	stack_waiting = stack_attention.attention
	if live and snapshot.get("connectionReady", false) and snapshot.has("phaseStops"):
		phase_stops = snapshot.phaseStops.duplicate(true)
	turn_label.text = "Turn " + str(snapshot.game.turn)
	phase_title.text = snapshot.game.phase
	_update_turn_steps()
	for p in snapshot.players:
		var values: Dictionary = hud_values[p.id]
		values.portrait.set_player(p, p.id == snapshot.game.activePlayer)
		values.name.text = p.name
		values.name.tooltip_text = p.name
		values.info.text = ""
		values.info.hide()
		for zone in values.zones:
			values.zones[zone].playable = Card.playable_glow and p.zones[zone].any(func(card): return _playable(card, int(p.id), zone))
			values.zones[zone].castable_now = Card.playable_glow and p.zones[zone].any(func(card): return _playable(card, int(p.id), zone) and _ready_now(card, zone))
			values.zones[zone].text = str(p.zones[zone].size())
			values.zones[zone].tooltip_text = zone + " / " + str(p.zones[zone].size()) + " cards." + (" Something here can be cast now." if values.zones[zone].playable else "") + " Click to browse."
	library_count.text = str(snapshot.players[0].libraryCount) + " Library"
	library_pile.show()
	library_count.show()
	library_pile.enabled = snapshot.get("availableActions", {}).get("draw", false)
	library_pile.draw_cue = snapshot.get("drawHint", false) or not snapshot.get("pendingDraws", []).is_empty()
	library_pile.modulate.a = 1.0 if library_pile.enabled else 0.5
	for i in range(mana_buttons.size()):
		mana_buttons[i].set_amount(int(snapshot.players[0].get("mana", {}).get(ManaCounter.KEYS[i], 0)), live and snapshot.get("connectionReady", false))
	var shown_stack: Array = snapshot.stack.filter(func(item): return item.get("sourceId", -1) != snapshot.get("pendingCastId", -2) and not (Live.is_automatic_stack(snapshot) and int(item.id) == int(snapshot.autoPassStackId)))
	stack_box.present(shown_stack)
	stack_header.text = "STACK / ACTIVITY   [%02d]" % shown_stack.size()
	if not selected.is_empty():
		var found := false
		for player in snapshot.players:
			for zone_key in player.zones:
				for c in player.zones[zone_key]:
					if c.id == selected.id:
						selected = c.duplicate(true)
						selected.owner = player.id
						selected.zone = zone_key
						found = true
		if not found:
			for item in snapshot.stack:
				if item.sourceId == selected.id:
					selected = item.get("card", selected).duplicate(true)
					selected.owner = 0
					selected.zone = "Stack"
					found = true
		if not found:
			selected = {}
	if targeting and (not _can_attack() or (live and (not snapshot.get("connectionReady", false) or snapshot.prompt.get("inputKind", "") != "InputAttack" or not snapshot.asks.is_empty()))):
		targeting = false
	_layout_board()
	_update_actions()
	if inspection_card.data.is_empty() and snapshot.players[0].zones.Battlefield.size() > 1:
		_inspect(snapshot.players[0].zones.Battlefield[1])
	if not snapshot.asks.is_empty():
		var ask: Dictionary = snapshot.asks[0]
		var mode_card: Control = cards.get(interaction_panel.mode_source(ask)) if live else null
		var answering: bool = live and response_target.accepts(ask)
		response_target.present(ask if answering else {}, snapshot.get("connectionReady", false))
		if answering:
			if modal.visible: _close_modal()
			board_choice.hide()
			interaction_panel.show_modes({})
		elif is_instance_valid(mode_card) and mode_card.is_visible_in_tree():
			# Mode choices hang off the card itself, not a popup.
			if modal.visible: _close_modal()
			board_choice.hide()
			interaction_panel.show_modes(ask)
		elif _board_ask(ask):
			interaction_panel.show_modes({})
			if modal.visible: _close_modal()
			var avatars := {}
			for seat in hud_values:
				if seat < snapshot.players.size(): avatars[int(snapshot.players[seat].get("engineId", seat))] = hud_values[seat].portrait
			board_choice.present(ask, cards, snapshot.get("connectionReady", false), avatars)
		else:
			interaction_panel.show_modes({})
			board_choice.hide()
			if ask.id != open_ask or not modal.visible or not is_instance_valid(modal_panel): _open_decision(ask)
	else:
		response_target.present({})
		interaction_panel.show_modes({})
		board_choice.hide()
		if open_ask >= 0: _close_modal()
	if live:
		_present_card_selection()
	if live:
		_update_live_actions()
		opening_hand.present(snapshot)
	if is_instance_valid(toast):
		toast.position = Vector2(30, size.y * 0.44)
		toast.size.x = board.size.x
	_refresh_zone_browser()
	_present_interaction()
	_sync_transition_preview()

func _row(key: String, at: Vector2, dimensions: Vector2, values: Array, spacing: float = 14, owner: int = 0, zone: String = "Battlefield", centered: bool = false) -> void:
	var row: Dictionary = rows[key]
	row.scroll.position = at
	row.inner.custom_minimum_size = dimensions
	row.scroll.size = dimensions
	var card_size := TABLE_CARD_SIZE
	var pack_values: Array = values.duplicate(true)
	for card in pack_values:
		if zone != "Battlefield":
			split_pile_cards.erase(card.id)
			local_pile_members.erase(card.id)
		card.separate = (owner == 0 and not local_pile_members.has(card.id)) or split_pile_cards.has(card.id) or (dragged_source != null and cards.get(card.id) == dragged_source) or snapshot.get("combat", []).any(func(entry): return int(entry.attacker) == int(card.id) or entry.get("blockers", []).has(card.id)) or values.any(func(other): return int(other.get("attachedTo", -1)) == int(card.id))
	if zone == "Battlefield":
		for group in FieldLayout.groups(pack_values, true):
			if group.cards.size() < 2 or group.cards.any(func(card): return pending_returns.has(card.id) or (dragged_source != null and cards.get(card.id) == dragged_source)): continue
			for card in group.cards:
				manual_positions.erase(card.id)
				play_positions.erase(card.id)
	var pile_sizes: Dictionary = {}
	var anchored_counts: Dictionary = {}
	var anchored_order: Array = []
	if zone == "Battlefield":
		for group in FieldLayout.groups(pack_values, true):
			for card in group.cards: pile_sizes[card.id] = group.cards.size()
		if owner == 0: _place_anchored_piles(pack_values, card_size, anchored_counts, anchored_order)
	var automatic := values.filter(func(card): return not manual_positions.has(card.id) and not play_positions.has(card.id) and not pending_returns.has(card.id) and not pile_drag_ids.has(card.id) and not (dragged_source != null and cards.get(card.id) == dragged_source) and not (card.has("attachedTo") and card.get("attachmentKind", "card") == "card"))
	if owner != 0:
		card_size = FieldLayout.fit_card_size(automatic, dimensions - Vector2(16, 16), TABLE_CARD_SIZE, spacing)
	pack_values = pack_values.filter(func(card): return automatic.any(func(other): return other.id == card.id))
	var packed: Dictionary = FieldLayout.arrange(pack_values, dimensions - Vector2(16, 16), card_size, spacing, zone == "Battlefield")
	var hand_pick := zone == "Hand" and _hand_pick_active()
	var hand_pick_discard := hand_pick and _hand_pick_is_discard()
	var hand_pick_offered := {}
	if hand_pick:
		for offered in snapshot.prompt.get("cards", []): hand_pick_offered[int(offered.id)] = true
	for i in range(values.size()):
		var c: Dictionary = values[i].duplicate(true)
		c.owner = owner
		c.zone = zone
		c.playable = _playable(c, owner, zone)
		c.ready = c.playable and _ready_now(c, zone)
		if snapshot.prompt.get("inputKind", "") == "InputBlock" and snapshot.prompt.get("chosen", []).has("card:" + str(c.id)):
			c.weakSelection = maxi(1, int(c.get("weakSelection", 0)))
		if hand_pick and zone == "Hand" and owner == 0:
			# Forge's own chosen list marks the pick; cards it cannot take are shaded.
			if snapshot.prompt.get("chosen", []).has("card:" + str(c.id)): c.pickMark = 2 if hand_pick_discard else 1
			elif not hand_pick_offered.has(int(c.id)): c.pickBlocked = true
		c.stackCount = int(anchored_counts.get(c.id, packed.counts.get(c.id, 1)))
		c.pileSize = int(pile_sizes.get(c.id, 1))
		seen[c.id] = true
		var fresh := not cards.has(c.id)
		var view: Control
		if fresh:
			view = Card.new()
			view.hovered.connect(_card_hovered.bind(view))
			view.unhovered.connect(_card_unhovered.bind(view))
			view.picked.connect(_pick)
			view.inspect_requested.connect(_card_right_clicked)
			view.drag_started.connect(_start_card_drag)
			view.drag_moved.connect(_move_card_drag)
			view.drag_finished.connect(_finish_card_drag)
			row.inner.add_child(view)
			cards[c.id] = view
		else:
			view = cards[c.id]
			if view.data.get("zone", zone) != zone:
				manual_positions.erase(c.id)
		if zone == "Battlefield" and pending_returns.has(c.id):
			# Keep the local return preview in the hand until Forge confirms or rejects it.
			view.update_card(c)
			continue
		var mode_changed: bool = view.hand_mode != (zone == "Hand")
		view.hand_mode = zone == "Hand"
		view.table_angle = zone != "Hand"
		if mode_changed:
			view.base_rotation = 0
			view.resting_z = 0
			view._arrange()
		if view == dragged_source and not pile_drag_ids.is_empty(): c.stackCount = pile_drag_ids.size()
		view.update_card(c)
		view.set_selected(not selected.is_empty() and selected.id == c.id)
		if zone == "Battlefield" and c.has("attachedTo") and c.get("attachmentKind", "card") == "card":
			view.show()
			continue
		if zone == "Hand":
			manual_positions.erase(c.id)
			if play_positions.has(c.id):
				_place_pending_play(view)
				continue
			if view != dragged_source and view.get_parent() != hand_root:
				view.reparent(hand_root)
			if pending_hand_slot >= 0 and pending_hand_origin.is_finite() and not hand_order.has(c.id):
				# Reveal at the held card's drop position, then settle into the fan.
				view.size = HAND_CARD_SIZE
				view.pivot_offset = HAND_CARD_SIZE * 0.5
				view.rotation = 0
				view.scale = Vector2.ONE
				view.global_position = pending_hand_origin - HAND_CARD_SIZE * 0.5
				view.drop_pointer = get_global_mouse_position()
				if library_draw_pending:
					library_draw_pending = false
					library_ghost.hide()
					hand_gap_index = -1
					view.reveal_from_library()
			continue
		view.show()
		if pile_drag_ids.has(c.id) and view != dragged_source:
			view.hide()
			continue
		if zone == "Battlefield" and play_positions.has(c.id):
			manual_positions[c.id] = play_positions[c.id].position
			if view != dragged_source:
				_place_pending_play(view)
			play_positions.erase(c.id)
		if view != dragged_source:
			if manual_positions.has(c.id):
				if view.get_parent() != free_cards:
					view.reparent(free_cards)
				var saved: Vector2 = manual_positions[c.id]
				var center := Vector2(saved.x * board.size.x, saved.y)
				center = board.get_global_transform().affine_inverse() * _bounded_card_center(view, board.get_global_transform() * center)
				manual_positions[c.id] = Vector2(center.x / board.size.x, center.y)
				view.settle(center - card_size * 0.5, card_size, fresh)
			else:
				if view.get_parent() != row.inner:
					view.reparent(row.inner)
				view.settle(packed.positions.get(c.id, Vector2.ZERO) + Vector2(8, 8), card_size, fresh)
	for id in packed.order:
		if cards.has(id) and cards[id].get_parent() == row.inner:
			row.inner.move_child(cards[id], -1)
	for id in anchored_order:
		if cards.has(id) and cards[id].get_parent() == free_cards:
			free_cards.move_child(cards[id], -1)

static func _pile_anchor_key(card: Dictionary) -> String:
	var settled: Dictionary = card.duplicate()
	settled.sick = false
	settled.damage = 0
	settled.weakSelection = 0
	return FieldLayout.stack_key(settled)

## A moved pile keeps its spot; members that differ in round state fan out beside it.
func _place_anchored_piles(values: Array, card_size: Vector2, counts: Dictionary, order: Array) -> void:
	if pile_anchors.is_empty(): return
	var cursors: Dictionary = {}
	for group in FieldLayout.groups(values, true):
		var first: Dictionary = group.cards[0]
		if first.get("separate", false): continue
		if group.cards.any(func(card): return pile_drag_ids.has(card.id) or pending_returns.has(card.id)): continue
		var key := _pile_anchor_key(first)
		if not pile_anchors.has(key): continue
		var offset: float = FieldLayout.pile_step * card_size.x / 200.0
		var anchor: Vector2 = pile_anchors[key]
		var center_x: float = anchor.x * board.size.x + float(cursors.get(key, 0.0))
		for i in range(group.cards.size()):
			var card: Dictionary = group.cards[i]
			var tap_offset: Vector2 = FieldLayout.pile_tap_offset(card, group.cards.size(), card_size)
			manual_positions[card.id] = Vector2((center_x + offset * i + tap_offset.x) / board.size.x, anchor.y + tap_offset.y)
			play_positions.erase(card.id)
			order.append(card.id)
		if group.cards.size() > 1: counts[group.cards.back().id] = group.cards.size()
		cursors[key] = float(cursors.get(key, 0.0)) + card_size.y + offset * (group.cards.size() - 1) + 14.0

func _forget_empty_pile_anchors(battlefield: Array) -> void:
	if not pile_drag_ids.is_empty(): return
	for key in pile_anchors.keys():
		if not battlefield.any(func(card): return local_pile_members.has(card.id) and not split_pile_cards.has(card.id) and _pile_anchor_key(card) == key):
			pile_anchors.erase(key)

func _layout_attachments() -> void:
	var groups := {}
	for id in cards:
		var data: Dictionary = cards[id].data
		if data.get("zone", "") != "Battlefield" or not data.has("attachedTo") or data.get("attachmentKind", "card") != "card": continue
		var host := int(data.attachedTo)
		if not cards.has(host) or cards[host].data.get("zone", "") != "Battlefield": continue
		if not groups.has(host): groups[host] = []
		groups[host].append(id)
	for host_id in groups:
		var host: Control = cards[host_id]
		var global_target: Vector2 = host.global_position if host == dragged_source else host.get_parent().get_global_transform() * host.resting_position
		if host != dragged_source:
			if host.get_parent() != free_cards: host.reparent(free_cards)
			host.settle(free_cards.get_global_transform().affine_inverse() * global_target, host.size)
			host.resting_z = groups[host_id].size() + 1
			host.z_index = host.resting_z
		for index in range(groups[host_id].size()):
			var attachment: Control = cards[groups[host_id][index]]
			if attachment == dragged_source: continue
			if attachment.get_parent() != free_cards: attachment.reparent(free_cards)
			var offset: Vector2 = Vector2(-28, -24) * (groups[host_id].size() - index) * (host.size.x / TABLE_CARD_SIZE.x)
			attachment.resting_z = index
			attachment.z_index = index
			attachment.settle(free_cards.get_global_transform().affine_inverse() * (global_target + offset), host.size)

func _reflow_manual_cards() -> void:
	var current: Dictionary = {}
	for owner in player_areas:
		current[owner] = Rect2(player_areas[owner].position, player_areas[owner].size)
	if not previous_fields.is_empty():
		var old_width: float = previous_fields[0].end.x
		var positioned: Array = manual_positions.keys()
		for id in play_positions:
			if not positioned.has(id): positioned.append(id)
		for id in positioned:
			if not cards.has(id) or cards[id] == dragged_source:
				continue
			var view: Control = cards[id]
			var owner: int = view.data.get("owner", 0)
			if not previous_fields.has(owner) or not current.has(owner) or previous_fields[owner] == current[owner]:
				continue
			var before: Rect2 = previous_fields[owner]
			var after: Rect2 = current[owner]
			var saved: Vector2 = manual_positions[id] if manual_positions.has(id) else play_positions[id].position
			var old_center := Vector2(saved.x * old_width, saved.y)
			var fraction := (old_center - before.position) / before.size
			var center := after.position + fraction * after.size
			var extent := Vector2(TABLE_CARD_SIZE.y, TABLE_CARD_SIZE.x) * 0.5 if view.data.get("tapped", false) else TABLE_CARD_SIZE * 0.5
			center = center.clamp(after.position + extent + Vector2(8, 8), after.end - extent - Vector2(8, 8))
			var adjusted := Vector2(center.x / board.size.x, center.y)
			if manual_positions.has(id): manual_positions[id] = adjusted
			if play_positions.has(id):
				play_positions[id].position = adjusted
		if previous_fields.has(0) and current.has(0) and previous_fields[0] != current[0]:
			for key in pile_anchors:
				var fraction: Vector2 = (Vector2(pile_anchors[key].x * old_width, pile_anchors[key].y) - previous_fields[0].position) / previous_fields[0].size
				var center: Vector2 = current[0].position + fraction * current[0].size
				pile_anchors[key] = Vector2(center.x / board.size.x, center.y)
	previous_fields = current

func _minimum_opponent_height() -> float:
	return minf(MIN_OPPONENT_FIELD_HEIGHT, maxf(300, board_scroller.size.y - 500))

func _opponent_region(id: int, width: float, left_width: float) -> Vector2:
	var count: int = snapshot.players.size() - 1
	if count == 2: return Vector2(0 if id == 1 else left_width + 16, left_width if id == 1 else width - 16 - left_width)
	var span := (width - 16 * (count - 1)) / count
	return Vector2((id - 1) * (span + 16), span)

func _layout_board() -> void:
	if layout_paused: return
	if board == null or snapshot.is_empty() or board.size.x < 100:
		return
	var w: float = board.size.x
	var h: float = maxf(board.size.y, table_minimum_height)
	free_cards.size = board.size
	free_cards.global_position = board.global_position
	var available_w: float = w - 16
	var minimum_w: float = minf(352, available_w * 0.4)
	var left_width := clampf(available_w * opponent_ratio, minimum_w, available_w - minimum_w)
	var top_height := clampf((h - 16) * field_ratio, _minimum_opponent_height(), h - 16 - MIN_LOCAL_FIELD_HEIGHT)
	if is_equal_approx(field_ratio, 0.46) and is_equal_approx(table_minimum_height, MIN_TABLE_HEIGHT):
		top_height = minf(top_height, maxf(300, board_scroller.size.y - 500))
	var local_top := top_height + 16
	for id in player_areas:
		var active: bool = id < snapshot.players.size()
		player_areas[id].visible = active
		hud[id].visible = active
		hud_values[id].zone_tray.visible = active
		step_panels[id].panel.visible = active
		if id > 0 and not active:
			rows["enemy" + str(id)].scroll.hide()
			rows["lands" + str(id)].scroll.hide()
	for id in range(1, snapshot.players.size()):
		var region := _opponent_region(id, w, left_width)
		var left: float = region.x
		var width: float = region.y
		player_areas[id].position = Vector2(left, 0)
		player_areas[id].size = Vector2(width, top_height)
		hud[id].position = Vector2(left + 12, 8)
		hud[id].size = Vector2(136, 86)
		var tray_scale := minf(1.0, maxf(0.65, (width - 164) / 166.0))
		hud_values[id].zone_tray.scale = Vector2.ONE * tray_scale
		hud_values[id].zone_tray.position = Vector2(left + width - 12 - 166 * tray_scale, 12)
		step_panels[id].panel.position = Vector2(left + 12, top_height - 48)
		step_panels[id].panel.size = Vector2(width - 24, 36)
	player_areas[0].position = Vector2(LOCAL_CONTROL_LANE_WIDTH, local_top)
	player_areas[0].size = Vector2(w - LOCAL_CONTROL_LANE_WIDTH, h - local_top)
	hud_values[0].zone_tray.position = Vector2(w - 178, local_top + 12)
	_reflow_manual_cards()
	opponent_divider.position = Vector2(left_width, 0)
	opponent_divider.size = Vector2(16, top_height)
	opponent_divider.visible = snapshot.players.size() == 3
	local_divider.position = Vector2(0, top_height)
	local_divider.size = Vector2(w, 16)
	seen.clear()
	var row_height: float = TABLE_CARD_SIZE.y + 48
	for id in range(1, snapshot.players.size()):
		var p: Dictionary = snapshot.players[id]
		var region := _opponent_region(id, w, left_width)
		var left: float = region.x
		var width: float = region.y
		var creatures: Array = p.zones.Battlefield.filter(func(c): return not c.get("typeLine", "").contains("Land"))
		var lands: Array = p.zones.Battlefield.filter(func(c): return c.get("typeLine", "").contains("Land"))
		rows["lands" + str(id)].scroll.hide()
		_row("enemy" + str(id), Vector2(left + 8, 98), Vector2(width - 16, top_height - 142), creatures + lands, OPPONENT_CARD_GAP, id)
	var you: Dictionary = snapshot.players[0]
	var creatures: Array = you.zones.Battlefield.filter(func(c): return not c.get("typeLine", "").contains("Land"))
	var lands: Array = you.zones.Battlefield.filter(func(c): return c.get("typeLine", "").contains("Land"))
	var local_height := h - local_top - 72
	var playable_width := w - LOCAL_CONTROL_LANE_WIDTH
	_row("your_lands", Vector2(LOCAL_CONTROL_LANE_WIDTH + 8, local_top + 4), Vector2(playable_width * 0.46 - 16, local_height), lands, 12)
	_row("your_creatures", Vector2(LOCAL_CONTROL_LANE_WIDTH + playable_width * 0.46, local_top + 84), Vector2(playable_width * 0.54 - 8, local_height - 80), creatures, 14)
	_forget_empty_pile_anchors(lands + creatures)
	hud[0].position = Vector2(board_scroller.global_position.x + board_scroller.size.x - 228, size.y - 158)
	hud[0].size = Vector2(216, 100)
	_layout_mana_pool()
	_row("hand", Vector2.ZERO, Vector2(100, row_height), [] if _opening_hand_gated() else you.zones.Hand, 10, 0, "Hand", true)
	rows.hand.scroll.hide()
	_layout_hand()
	_layout_attachments()
	if library_draw_pending and snapshot.get("connectionReady", false):
		_cancel_library_draw_preview()
	for id in pending_returns.keys():
		if you.zones.Hand.any(func(card): return card.id == id):
			pending_returns.erase(id)
	for id in cards.keys():
		if not seen.has(id):
			var retiring: Control = cards[id]
			if pending_returns.has(id):
				continue # Keep a cast's rollback preview in the hand through every restore.
			var own_cast: bool = live and retiring.data.get("owner", -1) == 0 and retiring.data.get("zone", "") == "Hand" and (snapshot.get("pendingCastId", -1) == id or snapshot.stack.any(func(item): return item.sourceId == id))
			if own_cast and not play_positions.has(id):
				var center: Vector2 = board.get_global_transform().affine_inverse() * _bounded_card_center(retiring, retiring.get_global_rect().get_center())
				play_positions[id] = {"position": Vector2(center.x / board.size.x, center.y), "age": 0.0}
			# Presentation only: while Forge is still mid-cast (payment, targets, a cost/mode
			# choice), the card sits provisionally in its Stack zone without a stack item yet.
			var cast_in_progress: bool = live and (not snapshot.get("connectionReady", false) or not snapshot.get("asks", []).is_empty() or snapshot.prompt.get("inputKind", "") != "InputPassPriority")
			if play_positions.has(id) and (cast_in_progress or snapshot.stack.any(func(item): return item.sourceId == id)):
				retiring.data.zone = "Stack"
				retiring.data.pendingCast = true
				retiring.data.availableActions = snapshot.get("takebackCast", {}).get("availableActions", {}) if int(snapshot.get("takebackCast", {}).get("id", -1)) == int(id) else {}
				if retiring != dragged_source:
					_place_pending_play(retiring)
				continue
			play_positions.erase(id)
			cards.erase(id)
			manual_positions.erase(id)
			split_pile_cards.erase(id)
			local_pile_members.erase(id)
			if snapshot.stack.any(func(item): return item.sourceId == id):
				_animate_to_stack(retiring)
			else:
				retiring.queue_free()
	_update_lines()
	_layout_inspection()

func _ordered_hand() -> Array:
	if snapshot.is_empty():
		return []
	var current: Dictionary = {}
	for value in snapshot.players[0].zones.Hand:
		current[value.id] = value
	for id in pending_returns:
		if cards.has(id):
			current[id] = cards[id].data
	hand_order = hand_order.filter(func(id): return current.has(id))
	for value in snapshot.players[0].zones.Hand:
		if not hand_order.has(value.id):
			if pending_hand_slot >= 0:
				hand_order.insert(clampi(pending_hand_slot, 0, hand_order.size()), value.id)
				hand_focus_id = value.id
				pending_hand_slot = -1
				pending_hand_origin = Vector2.INF
			else:
				hand_order.append(value.id)
	var values: Array = []
	for id in hand_order:
		values.append(current[id])
	return values

func _hand_layout_values() -> Array:
	if _opening_hand_gated(): return []
	var values := _ordered_hand()
	values = values.filter(func(value): return not play_positions.has(value.id))
	if is_instance_valid(dragged_source) and dragged_source.data.zone == "Hand":
		values = values.filter(func(value): return value.id != dragged_source.data.id)
	return values

func _hand_insertion_index(pointer: Vector2) -> int:
	var values := _hand_layout_values()
	var count := mini(values.size() - hand_offset, clampi(int(hand_fan_width / 48), 3, 8))
	count = maxi(0, count)
	var spread := minf(100, (hand_fan_width - HAND_CARD_SIZE.x - 8) / maxf(1, count - 1))
	var total := HAND_CARD_SIZE.x + spread * maxf(0, count - 1)
	var first_center := hand_root.global_position.x + (hand_fan_width - total) * 0.5 + HAND_CARD_SIZE.x * 0.5
	var slot := clampi(int(floor((pointer.x - first_center) / maxf(1, spread))) + 1, 0, count)
	return clampi(hand_offset + slot, 0, values.size())

func _update_hand_gap(pointer: Vector2) -> void:
	if library_draw_pending:
		return
	var eligible_drag: bool = library_pile.dragging or (is_instance_valid(dragged_source) and (dragged_source.data.zone == "Hand" or dragged_source.data.get("availableActions", {}).get("returnToHand", false)))
	var index := -1
	if eligible_drag and _hand_drop_area().has_point(pointer):
		index = _hand_insertion_index(pointer)
	if index != hand_gap_index:
		hand_gap_index = index
		_layout_hand()

func _opening_hand_gated() -> bool:
	return live and not opening_hand_released

func _layout_mana_pool() -> void:
	if mana_pool == null or not player_areas.has(0): return
	var field: Rect2 = player_areas[0].get_global_rect().intersection(board_scroller.get_global_rect())
	mana_pool.visible = field.size.y > 48
	var phases: PanelContainer = step_panels[0].panel
	phases.visible = mana_pool.visible
	var phase_height: float = phases.get_combined_minimum_size().y
	var mana_height: float = mana_pool.get_combined_minimum_size().y
	var top_gap := LOCAL_CONTROL_TOP_GAP
	var group_gap := LOCAL_CONTROL_GROUP_GAP
	var available_height := maxf(1, field.size.y - top_gap - LOCAL_CONTROL_GAP - group_gap)
	var factor := clampf(available_height / (mana_height + phase_height), 0.01, 0.9)
	# Both groups share one width and are centered horizontally in the lane,
	# with a generous gap between them and below the top edge.
	var width := maxf((LOCAL_CONTROL_LANE_WIDTH - LOCAL_CONTROL_GAP * 2) / factor, maxf(mana_pool.get_combined_minimum_size().x, phases.get_combined_minimum_size().x))
	mana_pool.scale = Vector2.ONE * factor
	mana_pool.size = Vector2(width, mana_height)
	# Center between the window's left edge and the battlefield frame, so the
	# space on both sides of the controls is equal (the lane includes the outer margin).
	var lane_left := get_global_rect().position.x
	var left := lane_left + (field.position.x - lane_left - width * factor) * 0.5
	mana_pool.position = Vector2(left, field.position.y + top_gap)
	phases.scale = Vector2.ONE * factor
	phases.size = Vector2(width, phase_height)
	phases.position = Vector2(left, mana_pool.position.y + mana_height * factor + group_gap)

func _layout_hand(instant_id: int = -1) -> void:
	if hand_root == null or snapshot.is_empty():
		return
	var width := maxf(180, board_scroller.size.x - 608)
	hand_root.position = Vector2(board_scroller.global_position.x + 304, size.y - 190 - ui_layout.hand_show)
	hand_root.size = Vector2(width, HAND_CARD_SIZE.y + 16)
	library_pile.size = HAND_CARD_SIZE
	var hp_center: float = hud_values[0].portrait.get_global_rect().get_center().x
	var library_center := lerpf(size.x * 0.5, hp_center, 0.5)
	# Keep the larger deck beside the HP badge, including at the minimum width.
	library_center = minf(library_center, hud_values[0].portrait.get_global_rect().position.x - library_pile.size.x * 0.5 - 20)
	hand_root.position.x = minf(hand_root.position.x, library_center - library_pile.size.x * 0.5 - HAND_CARD_SIZE.x - 32)
	var fan_width := clampf(library_center - library_pile.size.x * 0.5 - hand_root.position.x - 50, HAND_CARD_SIZE.x + 8, maxf(HAND_CARD_SIZE.x + 8, width - 40))
	hand_fan_width = fan_width
	hand_root.size.x = fan_width + 24
	# The player's own offsets apply last, so the hand keeps its width and stays on the table.
	var table_right: float = board_scroller.global_position.x + board_scroller.size.x
	hand_root.position.x = clampf(hand_root.position.x + ui_layout.hand_x, 36.0, maxf(36.0, table_right - hand_root.size.x - 28))
	library_center = clampf(library_center + ui_layout.library_x, library_pile.size.x * 0.5 + 8, maxf(library_pile.size.x * 0.5 + 8, table_right - library_pile.size.x * 0.5))
	var values: Array = _hand_layout_values()
	hand_root.visible = not _opening_hand_gated()
	var hand_count := int(ui_layout.hand_count)
	var capacity := clampi(int(fan_width / (48.0 if hand_count <= 8 else 32.0)), 3, hand_count)
	if hand_focus_id >= 0:
		var focus_index := hand_order.find(hand_focus_id)
		if focus_index < hand_offset:
			hand_offset = focus_index
		elif focus_index >= hand_offset + capacity:
			hand_offset = focus_index - capacity + 1
		hand_focus_id = -1
	var held_slots := 1 if is_instance_valid(dragged_source) and dragged_source.data.zone == "Hand" else 0
	hand_offset = clampi(hand_offset, 0, maxi(0, values.size() + held_slots - capacity))
	if hand_gap_index >= 0:
		# The held card occupies one of the visible slots, including in a full hand.
		hand_offset = clampi(hand_offset, maxi(0, hand_gap_index - capacity + 1), hand_gap_index)
	var visible_count := mini(maxi(0, values.size() - hand_offset), capacity)
	var gap_visible: bool = hand_gap_index >= hand_offset and hand_gap_index <= hand_offset + visible_count
	if gap_visible:
		visible_count = mini(visible_count, capacity - 1)
	var slots := visible_count + (1 if gap_visible else 0)
	var spread := minf(100.0 * float(ui_layout.hand_spread), (fan_width - HAND_CARD_SIZE.x - 8) / maxf(1, slots - 1))
	var total := HAND_CARD_SIZE.x + spread * maxf(0, slots - 1)
	for i in range(values.size()):
		var view: Control = cards[values[i].id]
		view.size = HAND_CARD_SIZE
		var visible_slot: bool = i >= hand_offset and i < hand_offset + visible_count
		if view == dragged_source:
			continue
		if not visible_slot and view.hover_active:
			view._on_exit()
		view.visible = visible_slot
		if not visible_slot:
			continue
		var slot: float = i - hand_offset
		if gap_visible and i >= hand_gap_index:
			slot += 1
		var t: float = 0 if slots <= 1 else (slot / (slots - 1) - 0.5) * 2
		view.base_rotation = deg_to_rad(t * float(ui_layout.hand_angle))
		view.resting_z = i - hand_offset
		view.z_index = view.resting_z * 2
		view._arrange()
		view.settle(Vector2((fan_width - total) * 0.5 + slot * spread, absf(t) * 1.5 * float(ui_layout.hand_angle)), HAND_CARD_SIZE, false, view.data.id == instant_id)
	hand_previous.visible = hand_offset > 0
	hand_next.visible = hand_offset + visible_count < values.size()
	hand_previous.position = hand_root.position + Vector2(-28, 22)
	hand_next.position = hand_root.position + Vector2(fan_width + 20, 22)
	hand_previous.size = Vector2(26, 36)
	hand_next.size = Vector2(26, 36)
	library_pile.position = Vector2(library_center - library_pile.size.x * 0.5, size.y - library_pile.size.y * ui_layout.library_show)
	_place_local_hud(table_right)
	library_count.position = library_pile.position + Vector2(0, -30)
	library_count.size = Vector2(library_pile.size.x, 24)
	_order_hand_input()

## Your health/portrait panel: bottom-right of the table by default, moved by Table settings,
## always kept on the table and above the library.
func _place_local_hud(table_right: float) -> void:
	var table_left: float = board_scroller.global_position.x
	var default_x: float = table_right - 228
	hud[0].position.x = clampf(default_x + float(ui_layout.hud_x), table_left + 8, maxf(table_left + 8, default_x))
	var lowest: float = size.y - 158
	var highest: float = minf(board_scroller.global_position.y + 8, lowest)
	hud[0].position.y = clampf(lowest - float(ui_layout.hud_y), highest, lowest)
	if library_pile.get_global_rect().intersects(hud_values[0].portrait.get_global_rect()):
		hud[0].position.y = maxf(highest, library_pile.position.y - hud_values[0].portrait.size.y - 12)

func _library_drag_started(pointer: Vector2) -> void:
	if targeting or modal.visible or library_draw_pending or not library_pile.enabled:
		library_pile.cancel_drag()
		return
	library_ghost.pivot_offset = library_ghost.size * 0.5
	library_ghost.scale = Vector2.ONE
	library_ghost.show()
	_library_drag_moved(pointer)

func _library_drag_moved(pointer: Vector2) -> void:
	library_ghost.position = pointer - library_ghost.size * 0.5
	_update_hand_gap(pointer)

func _library_drag_finished(pointer: Vector2, cancelled: bool) -> void:
	var slot := hand_gap_index if hand_gap_index >= 0 else _hand_insertion_index(pointer)
	if cancelled or targeting or modal.visible or not library_pile.enabled:
		_cancel_library_draw_preview()
		return
	if Rect2(Vector2.ZERO, size).has_point(pointer) and hand_root.get_global_rect().grow(16).has_point(pointer):
		# Keep the held back and insertion gap until the authoritative card arrives.
		library_draw_pending = true
		hand_gap_index = slot
		pending_hand_slot = slot
		pending_hand_origin = pointer
		_intent("draw")
		# The mock responds synchronously. A live adapter must clear a rejected
		# insertion request when it acknowledges the corresponding intent.
		if snapshot.get("mode", "") == "mock":
			pending_hand_slot = -1
			pending_hand_origin = Vector2.INF
	else:
		_cancel_library_draw_preview()

func _cancel_library_draw_preview() -> void:
	library_draw_pending = false
	library_ghost.hide()
	hand_gap_index = -1
	pending_hand_slot = -1
	pending_hand_origin = Vector2.INF
	_layout_hand()

func _scroll_hand(direction: int) -> void:
	if _modal_covers_table() or dragged_source != null:
		return
	hand_offset += direction
	_layout_hand()

func _hand_scroll(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT]:
			_scroll_hand(1)
			hand_root.accept_event()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT]:
			_scroll_hand(-1)
			hand_root.accept_event()

func _update_hand_hover() -> void:
	if synthetic_hover or hand_root == null or snapshot.is_empty():
		return
	var candidate: Control
	var pointer := get_global_mouse_position()
	if not _modal_covers_table() and not opening_hand.visible and dragged_source == null and not library_pile.dragging and not library_draw_pending and not targeting:
		var values: Array = _ordered_hand()
		for i in range(values.size() - 1, -1, -1):
			if not cards.has(values[i].id):
				continue
			var view: Control = cards[values[i].id]
			var point: Vector2 = view.get_global_transform().affine_inverse() * pointer
			if view.hand_mode and view.visible and Rect2(Vector2.ZERO, view.size).has_point(point):
				candidate = view
				break
		if candidate == null and is_instance_valid(hovered_source) and hovered_source.hand_mode and hand_copies.has(hovered_source.data.id) and hand_copies[hovered_source.data.id].visible and hand_copies[hovered_source.data.id].get_global_rect().has_point(pointer):
			candidate = hovered_source
	for value in snapshot.players[0].zones.Hand:
		if cards.has(value.id) and cards[value.id].hover_active and cards[value.id] != candidate:
			cards[value.id]._on_exit()
	if candidate != null and not candidate.hover_active:
		candidate._on_enter()

func _animate_to_stack(view: Control) -> void:
	if view.hover_active:
		view._on_exit()
	view.visual.show()
	if view.animation != null:
		view.animation.kill()
	view.reparent(self)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.z_index = 50
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "position", stack_box.get_global_rect().get_center() - view.size * 0.2, 0.3)
	tween.tween_property(view, "scale", Vector2.ONE, 0.3)
	tween.tween_property(view, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(view.queue_free)

func _layout_inspection() -> void:
	if inspection_card == null or board_scroller == null or hand_root == null:
		return
	var height := minf(clampf(size.y * 0.42, 360, 440) * 1.25, size.y - 48)
	# Trait names list under the card; the card shrinks to leave room for them.
	var trait_rows := inspection_traits.get_child_count() * 24.0
	var trait_height := 0.0 if trait_rows == 0.0 else trait_rows + 24.0
	var card_height := height - trait_height
	var width := card_height * 144.0 / 202
	var left_edge := 24.0
	if is_instance_valid(mana_pool):
		left_edge = maxf(left_edge, (get_global_transform().affine_inverse() * mana_pool.get_global_rect().end).x + 16)
	if is_instance_valid(incoming_effect):
		incoming_effect.hover_left_inset = left_edge
		# Small effect cards sit in the middle of the table, never over the rail.
		if is_instance_valid(board_scroller):
			var table: Rect2 = get_global_transform().affine_inverse() * board_scroller.get_global_rect()
			response_target.table_rect = table
			if incoming_effect.table_rect != table:
				incoming_effect.table_rect = table
				incoming_effect._layout()
	var source_on_right := false
	if is_instance_valid(hovered_source):
		var center: Vector2 = get_global_transform().affine_inverse() * (hovered_source.get_global_transform() * (hovered_source.size * 0.5))
		source_on_right = center.x >= size.x * 0.5
	inspection.position = Vector2(minf(left_edge, size.x - width - 24) if source_on_right else size.x - width - 24, (size.y - height) * 0.5)
	inspection.size = Vector2(width, height)
	inspection_card.position = Vector2.ZERO
	inspection_card.size = Vector2(width, card_height)
	# Backed panel: the list sits over the board and must stay readable there.
	inspection_traits_panel.visible = trait_rows > 0.0
	inspection_traits_panel.position = Vector2(0, card_height + 14.0)
	inspection_traits_panel.size = Vector2(width, trait_rows + 10.0)
	inspection_traits.position = Vector2(10, card_height + 19.0)
	inspection_traits.size = Vector2(width - 20, trait_rows)

func _inspect(data: Dictionary) -> void:
	if data.get("hidden", false):
		return
	inspection_card.update_card(data)
	_fill_inspection_traits(data)
	_layout_inspection()

func _fill_inspection_traits(data: Dictionary) -> void:
	for child in inspection_traits.get_children():
		inspection_traits.remove_child(child)
		child.queue_free()
	if data.get("zone", "") != "Battlefield": return
	for key in TraitFace.trait_keys(data.get("keywords", [])):
		var color: Color = TraitIcons.color_for(key, TraitFace.TRAIT_COLORS[TraitFace.TRAITS[key][1]])
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.custom_minimum_size.y = 24
		row.add_theme_constant_override("separation", 8)
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(22, 22)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.draw.connect(func():
			if not TraitIcons.draw_icon(icon, key, Rect2(Vector2.ZERO, icon.size), color):
				icon.draw_string(get_theme_default_font(), Vector2(0, 16), TraitFace.trait_icon(key), HORIZONTAL_ALIGNMENT_CENTER, icon.size.x, 12, color))
		row.add_child(icon)
		var label := Label.new()
		label.text = TraitFace.TRAITS[key][0]
		label.add_theme_color_override("font_color", color)
		label.add_theme_font_size_override("font_size", 15)
		row.add_child(label)
		inspection_traits.add_child(row)

func _card_hovered(data: Dictionary, source: Control) -> void:
	if is_instance_valid(hovered_source) and hovered_source != source and hovered_source.hover_active and hovered_source.holds_tap_hover():
		source._on_exit()
		return
	# Keep the popped hand card above board controls while the pointer is on its face.
	if not source.hand_mode and is_instance_valid(hovered_source) and hovered_source.hand_mode and hovered_source.hover_active and hand_copies.has(hovered_source.data.id) and hand_copies[hovered_source.data.id].visible and hand_copies[hovered_source.data.id].get_global_rect().has_point(get_global_mouse_position()):
		source._on_exit()
		return
	hovered_source = source
	_inspect(data)
	_sync_raised_card()

func _card_unhovered(source: Control) -> void:
	if hovered_source == source:
		hovered_source = null
		raised_card.hide()

func _process(_delta: float) -> void:
	adapter.poll(_delta)
	if layout_paused: return
	if live and is_instance_valid(interaction_panel):
		var popup_showing: bool = incoming_effect.showing() and snapshot.get("prompt", {}).get("inputKind", "") == "InputPassPriority" and not incoming_effect.responding.has(int(incoming_effect.active.get("stackId", -1)))
		if interaction_panel.suspended != (modal.visible or opening_hand.visible or popup_showing or hand_pick_panel.visible): _present_interaction()
	_layout_zone_browser()
	_layout_mana_pool()
	if is_instance_valid(decision_board_button) and decision_board_button.visible: _place_decision_board_button()
	for id in play_positions.keys():
		play_positions[id].age += _delta
		# A cost/mode popup keeps Forge at priority with the card still in hand; keep it on the board until answered.
		if live and play_positions[id].age > 0.6 and snapshot.get("connectionReady", false) and snapshot.get("asks", []).is_empty() and snapshot.prompt.get("inputKind", "") == "InputPassPriority" and snapshot.players[0].zones.Hand.any(func(card): return card.id == id):
			play_positions.erase(id)
			_layout_board()
	for id in pending_returns.keys():
		pending_returns[id] += _delta
		if pending_returns[id] > 12.0 and snapshot.get("connectionReady", false) and snapshot.players[0].zones.Battlefield.any(func(card): return card.id == id):
			pending_returns.erase(id)
			_layout_board()
	_update_hand_hover()

func _sync_hand_copies() -> void:
	if hand_root == null:
		return
	for id in hand_copies.keys():
		if not cards.has(id) or not cards[id].hand_mode:
			hand_copies[id].queue_free()
			hand_copies.erase(id)
	for view in cards.values():
		if not view.hand_mode:
			view.trait_layer.show() # A card that left the hand while lifted draws its table traits again.
			continue
		var lifted: bool = view.visible and not view.drag_active and not _modal_covers_table() and (view.hover_active or view.hand_hover_amount > 0.001)
		if not hand_copies.has(view.data.id):
			var copy := Card.new()
			copy.inspection = true
			copy.hand_copy = true
			copy.table_angle = false
			copy.gui_input.connect(_hand_copy_input.bind(view))
			hand_root.add_child(copy)
			# Share the source face: a hidden copy can consume UPDATE_ONCE before
			# its face draws, leaving a blank texture when it is first lifted.
			copy.visual.texture = view.surface.get_texture()
			hand_copies[view.data.id] = copy
		hand_copies[view.data.id].update_card(view.data)
		hand_copies[view.data.id].surface.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if not lifted:
			view.visual.show()
			view.trait_layer.show()
			if hand_copies.has(view.data.id):
				hand_copies[view.data.id].hide()
			continue
		var visual: Control = hand_copies[view.data.id]
		visual.reveal_progress = view.reveal_progress
		visual.update_card(view.data)
		visual.set_selected(view.selected)
		visual.size = view.size
		visual._arrange()
		visual.pivot_offset = Vector2.ZERO
		var amount: float = view.hand_hover_amount
		var factor := 1.0
		var pose: Transform2D = view.get_global_transform()
		var angle := pose.get_rotation()
		var center: Vector2 = pose * (view.size * 0.5) - Vector2(0, 22 * amount)
		visual.rotation = angle
		visual.scale = Vector2.ONE * factor
		visual.global_position = center - (visual.size * factor * 0.5).rotated(angle)
		visual.modulate = view.modulate
		visual.z_index = view.resting_z * 2 + 1
		visual.mouse_filter = Control.MOUSE_FILTER_STOP if view.hover_active else Control.MOUSE_FILTER_IGNORE
		visual.show()
		view.visual.hide()
		view.trait_layer.hide() # Pips and the playable glow travel with the lifted copy.
	_order_hand_input()

func _order_hand_input() -> void:
	# Godot hit-tests sibling order, not z_index. Interleave each original and
	# its lifted copy in fan order so a card drawn/reordered to the left cannot
	# steal the press from a card visibly in front of it.
	var ordered: Array[Node] = []
	for card in _ordered_hand():
		if cards.has(card.id) and cards[card.id].get_parent() == hand_root:
			ordered.append(cards[card.id])
		if hand_copies.has(card.id) and hand_copies[card.id].get_parent() == hand_root:
			ordered.append(hand_copies[card.id])
	if hand_root.get_children() == ordered: return
	for node in ordered:
		hand_root.move_child(node, -1)

func _hand_copy_input(event: InputEvent, source: Control) -> void:
	if is_instance_valid(source) and source.hand_mode and source.hover_active:
		source._gui_input(event)

func _pause_layout_loop(scroll: ScrollContainer) -> void:
	layout_paused = true
	_cancel_pointer_gesture()
	if client_diagnostics != null: client_diagnostics.record_layout_recovery(scroll, self)
	# Presentation processing stops; Main continues polling the same adapter.
	for child in get_children():
		if child == layout_guard or child == layout_recovery: continue
		layout_process_modes[child] = child.process_mode
		child.process_mode = Node.PROCESS_MODE_DISABLED
	if not is_instance_valid(layout_recovery):
		layout_recovery = Control.new()
		layout_recovery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout_recovery.mouse_filter = Control.MOUSE_FILTER_STOP
		layout_recovery.z_index = 1000
		add_child(layout_recovery)
		var shade := ColorRect.new()
		shade.color = Color(0.01, 0.02, 0.03, 0.88)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout_recovery.add_child(shade)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout_recovery.add_child(center)
		var panel := PanelContainer.new()
		P.style_popup(panel, 18)
		center.add_child(panel)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 16)
		panel.add_child(column)
		var message := _label("The display was paused to prevent a layout crash.\nYour match is still running. Retry the display to continue.", 18, P.TEXT)
		message.custom_minimum_size.x = 460
		column.add_child(message)
		layout_retry_button = _button("Retry display", _retry_layout)
		layout_retry_button.focus_mode = Control.FOCUS_ALL
		P.style_popup_button(layout_retry_button, true)
		column.add_child(layout_retry_button)
		if is_instance_valid(app_host):
			column.add_child(_button("Return to main menu", app_host.request_leave_game))
	layout_recovery.show()
	layout_retry_button.grab_focus()

func _retry_layout() -> void:
	layout_recovery.hide()
	for child in layout_process_modes:
		if is_instance_valid(child): child.process_mode = layout_process_modes[child]
	layout_process_modes.clear()
	layout_guard.retry()
	layout_paused = false
	_apply_state(snapshot)

func _prepare_render() -> void:
	if layout_paused: return
	var target := get_viewport()
	if target is SubViewport:
		if target.render_target_update_mode == SubViewport.UPDATE_DISABLED: return
	elif not is_visible_in_tree(): return
	# Sample animated card transforms once, immediately before drawing.
	_sync_raised_card()
	_update_lines()
	_sync_transition_preview()

func _sync_raised_card() -> void:
	_sync_hand_copies()
	if inspection != null:
		inspection.visible = is_instance_valid(hovered_source) and not hovered_source.data.get("hidden", false) and hovered_source.hover_active and not _modal_covers_table() and not opening_hand.visible and dragged_source == null and not library_pile.dragging and not library_draw_pending
		if inspection.visible:
			_layout_inspection()
	if raised_card == null:
		return
	if not is_instance_valid(hovered_source) or not hovered_source.hover_active or hovered_source.hand_mode or hovered_source.zone_browser or _modal_covers_table() or opening_hand.visible or library_draw_pending:
		raised_card.hide()
		# A hovered table card hides its own face behind the raised copy; never leave it blank.
		if is_instance_valid(hovered_source) and not hovered_source.hand_mode:
			hovered_source.visual.show()
		return
	hovered_source.visual.hide()
	# Mirror the animated card transform in the root overlay, outside every ScrollContainer.
	# The original node continues to receive clicks, scrolling and mouse exit events.
	var geometry_changed: bool = raised_card.size != hovered_source.size or raised_card.table_angle != hovered_source.table_angle
	raised_card.table_angle = hovered_source.table_angle
	if raised_card.data != hovered_source.data:
		raised_card.update_card(hovered_source.data)
	if raised_card.selected != hovered_source.selected:
		raised_card.set_selected(hovered_source.selected)
	raised_card.size = hovered_source.size
	if geometry_changed:
		raised_card._arrange()
	raised_card.pivot_offset = Vector2.ZERO
	var pose := hovered_source.get_global_transform()
	raised_card.rotation = pose.get_rotation()
	raised_card.scale = pose.get_scale()
	raised_card.global_position = pose.origin
	raised_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raised_card.modulate = hovered_source.modulate
	raised_card.show()

func _raised_hand_input(event: InputEvent) -> void:
	if is_instance_valid(hovered_source) and hovered_source.hand_mode:
		hovered_source._gui_input(event)

func _pick(data: Dictionary, double_click: bool) -> void:
	if is_instance_valid(board_choice) and board_choice.visible:
		board_choice.select_entity("card", int(data.id))
		return
	if live:
		if _attack_step() and snapshot.prompt.get("inputKind", "") == "InputAttack" and data.get("owner", -1) == 0 and data.get("zone", "") == "Battlefield" and data.get("typeLine", "").contains("Creature"):
			if targeting and selected.get("id", -1) == data.id:
				_cancel_attack_target()
				return
			_select_card(data)
			_begin_targeting()
			return
		if targeting:
			return
		_select_card(data)
		if data.get("zone", "") == "Stack":
			return # Pending casts can be inspected/moved, but cannot activate abilities.
		if data.get("tapped", false) and data.get("availableActions", {}).get("undoTap", false) and snapshot.prompt.get("inputKind", "") == "InputPassPriority":
			_intent("undo_tap", {"id": data.id})
			return
		_intent("card", {"id": data.id})
		return
	if targeting:
		return
	_select_card(data)
	if data.owner == 0:
		if data.zone == "Battlefield":
			_tap()
		elif data.zone == "Hand" and double_click:
			_primary_action()

func _select_card(data: Dictionary) -> void:
	selected = data.duplicate(true)
	for id in cards:
		cards[id].set_selected(id == data.id)
	_inspect(data)
	_update_actions()

func _start_card_drag(view: Control, pointer: Vector2) -> void:
	if targeting or modal.visible:
		view._finish_press(true)
		return
	_select_card(view.data)
	dragged_source = view
	pile_drag_ids.clear()
	if view.pile_gesture:
		var key: String = FieldLayout.stack_key(view.data)
		for id in cards:
			if int(cards[id].data.get("pileSize", 1)) > 1 and cards[id].data.get("owner", -1) == 0 and FieldLayout.stack_key(cards[id].data) == key: pile_drag_ids.append(id)
	view.visual.show()
	drag_origin_parent = view.get_parent()
	drag_origin = view.resting_position
	var center: Vector2 = view.get_global_transform() * (view.size * 0.5)
	if view.hand_mode:
		center.y -= 22 * view.hand_hover_amount
	drag_offset = pointer - center
	view.reparent(self)
	view.pivot_offset = view.size * 0.5
	view.scale = Vector2.ONE
	view.rotation_degrees = 90 if view.data.get("tapped", false) else 0
	view.z_index = 70
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if view.data.zone == "Battlefield": _layout_board()
	_move_card_drag(view, pointer)

func _move_card_drag(view: Control, pointer: Vector2) -> void:
	if dragged_source != view:
		return
	# Keep the same dimensions throughout hand-to-board and board-to-hand drags.
	view.size = HAND_CARD_SIZE
	view._arrange()
	view.pivot_offset = view.size * 0.5
	# Hand gestures can reach the fan; permanents remain inside their controller's field.
	var area := Rect2(Vector2(8, 80), size - Vector2(16, 88))
	var extent: Vector2 = Vector2(view.size.y, view.size.x) * 0.5 if view.data.get("tapped", false) else view.size * 0.5
	var returning: bool = pile_drag_ids.is_empty() and _hand_drop_area().has_point(pointer) and view.data.get("availableActions", {}).get("returnToHand", false)
	if view.data.zone != "Hand" and not view.zone_browser and not returning:
		area = player_areas[view.data.get("owner", 0)].get_global_rect().grow(-8)
	elif _hand_drop_area().has_point(pointer):
		area.size.y = maxf(area.size.y, size.y + extent.y - area.position.y)
	var center := pointer - drag_offset
	center.x = clampf(center.x, area.position.x + extent.x, area.end.x - extent.x)
	center.y = clampf(center.y, area.position.y + extent.y, area.end.y - extent.y)
	view.position = center - view.size * 0.5
	if live and str(view.data.get("typeLine", "")).contains("Equipment"):
		var recipient := _equipment_drop_target(view, pointer)
		for id in cards: cards[id].set_selected(int(id) == recipient or int(id) == int(view.data.id))
	_update_hand_gap(pointer)
	_layout_attachments()
	_update_lines()

func _finish_card_drag(view: Control, cancelled: bool) -> void:
	if dragged_source != view:
		return
	var insertion := hand_gap_index
	hand_gap_index = -1
	dragged_source = null
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.z_index = 0
	view.drop_pointer = get_global_mouse_position()
	var dropped_on_hand: bool = _hand_drop_area().has_point(view.last_pointer)
	var equip_recipient := _equipment_drop_target(view, view.last_pointer) if not cancelled else -1
	for id in cards: cards[id].set_selected(int(id) == int(selected.get("id", -1)))
	if not pile_drag_ids.is_empty():
		_finish_pile_drag(view, cancelled or dropped_on_hand)
		return
	if equip_recipient >= 0:
		view.reparent(drag_origin_parent)
		view.settle_target.clear()
		view.settle(drag_origin, TABLE_CARD_SIZE)
		_intent("equip", {"id": view.data.id, "target": equip_recipient})
		_layout_hand()
		return
	if view.zone_browser:
		if not cancelled and not dropped_on_hand and _is_hand_play_drop(view.last_pointer) and live:
			zone_views.erase(view.data.id)
			view.zone_browser = false
			cards[view.data.id] = view
			var center: Vector2 = board.get_global_transform().affine_inverse() * (view.get_global_transform() * (view.size * 0.5))
			play_positions[view.data.id] = {"position": Vector2(center.x / board.size.x, center.y), "age": 0.0}
			_place_pending_play(view)
			_intent("card", {"id": view.data.id})
		else:
			view.reparent(drag_origin_parent)
			view.settle(drag_origin, TABLE_CARD_SIZE)
		_refresh_zone_browser()
	elif view.data.zone == "Hand":
		var play_drop := not cancelled and not dropped_on_hand and _is_hand_play_drop(view.last_pointer)
		if not cancelled and dropped_on_hand and insertion >= 0:
			hand_order.erase(view.data.id)
			hand_order.insert(clampi(insertion, 0, hand_order.size()), view.data.id)
			hand_focus_id = view.data.id
		view.hand_hover_amount = 0
		if play_drop:
			var center: Vector2 = board.get_global_transform().affine_inverse() * (view.get_global_transform() * (view.size * 0.5))
			play_positions[view.data.id] = {"position": Vector2(center.x / board.size.x, center.y), "age": 0.0}
			_place_pending_play(view)
			# Pin presentation here while Forge decides the real zone transition.
			_intent("card" if live else "play", {"id": view.data.id})
		else:
			view.reparent(hand_root)
			_layout_hand(view.data.id if not cancelled else -1)
	elif not cancelled and dropped_on_hand:
		if view.data.get("availableActions", {}).get("returnToHand", false):
			var released_center: Vector2 = view.get_global_transform() * (view.size * 0.5)
			var released_angle: float = view.get_global_transform().get_rotation()
			pending_returns[view.data.id] = 0.0
			play_positions.erase(view.data.id)
			manual_positions.erase(view.data.id)
			hand_order.erase(view.data.id)
			hand_order.insert(clampi(insertion, 0, hand_order.size()), view.data.id)
			hand_focus_id = view.data.id
			view.reparent(hand_root)
			view.hand_mode = true
			view.hover_active = false
			view.hand_hover_amount = 0
			view._arrange()
			# Changing from a center pivot to the hand's bottom pivot must not jump.
			view.rotation = released_angle
			view.position = hand_root.get_global_transform().affine_inverse() * released_center - view.pivot_offset - (view.size * 0.5 - view.pivot_offset).rotated(released_angle)
			_layout_hand()
			_intent("return_to_hand", {"id": view.data.id})
		else:
			view.reparent(drag_origin_parent)
			view.settle(drag_origin, TABLE_CARD_SIZE)
			_notify("This card cannot return to hand.")
	elif cancelled:
		view.reparent(drag_origin_parent)
		view.settle(drag_origin, TABLE_CARD_SIZE)
	elif _stack_drop_target(view, view.last_pointer) >= 0:
		# Dropping a permanent onto an identical one joins it to that pile, where that card sits.
		_anchor_pile_at(_stack_drop_target(view, view.last_pointer))
		for id in [int(view.data.id), _stack_drop_target(view, view.last_pointer)]:
			local_pile_members[id] = true
			split_pile_cards.erase(id)
			manual_positions.erase(id)
			play_positions.erase(id)
		view.reparent(drag_origin_parent)
		view.settle(drag_origin, TABLE_CARD_SIZE)
	else:
		var center: Vector2 = board.get_global_transform().affine_inverse() * _bounded_card_center(view, view.position + view.size * 0.5)
		manual_positions[view.data.id] = Vector2(center.x / board.size.x, center.y)
		if view.data.zone == "Battlefield": split_pile_cards[view.data.id] = true
		if view.data.zone == "Stack" and play_positions.has(view.data.id):
			play_positions[view.data.id].position = manual_positions[view.data.id]
		view.reparent(free_cards)
		view.hover_active = false
		view.settle(center - view.size * 0.5, TABLE_CARD_SIZE, false, true)
	_layout_board()
	_layout_hand()
	_update_lines()

func _finish_pile_drag(view: Control, cancelled: bool) -> void:
	var members: Array = pile_drag_ids
	pile_drag_ids = []
	var released: Vector2 = view.global_position
	if cancelled:
		view.reparent(drag_origin_parent)
		view.settle(drag_origin, TABLE_CARD_SIZE)
	else:
		var target := _stack_drop_target(view, view.last_pointer)
		if target >= 0 and not members.has(target):
			_anchor_pile_at(target)
			local_pile_members[target] = true
			split_pile_cards.erase(target)
			manual_positions.erase(target)
		var center: Vector2 = board.get_global_transform().affine_inverse() * _bounded_card_center(view, view.position + view.size * 0.5)
		pile_anchors[_pile_anchor_key(view.data)] = Vector2(center.x / board.size.x, center.y)
		view.hover_active = false
	for id in members:
		if not cards.has(id): continue
		cards[id].show()
		if not cancelled:
			# The whole pile fans out from the drop instead of flying in from its old spot.
			if cards[id].get_parent() != free_cards: cards[id].reparent(free_cards)
			cards[id].global_position = released
	_layout_board()
	_layout_hand()
	_update_lines()

func _clean_up_board() -> void:
	if snapshot.is_empty() or dragged_source != null: return
	pile_anchors.clear()
	# Only stack identical permanents; every other card keeps its placement.
	var counts: Dictionary = {}
	for card in snapshot.players[0].zones.Battlefield:
		var key: String = FieldLayout.stack_key(card)
		if not key.is_empty(): counts[key] = int(counts.get(key, 0)) + 1
	for card in snapshot.players[0].zones.Battlefield:
		var key: String = FieldLayout.stack_key(card)
		if key.is_empty() or int(counts[key]) < 2: continue
		# A new pile forms where its first card already is instead of jumping into the rows.
		if not pile_anchors.has(_pile_anchor_key(card)): _anchor_pile_at(int(card.id))
		local_pile_members[card.id] = true
		split_pile_cards.erase(card.id)
		manual_positions.erase(card.id)
		play_positions.erase(card.id)
	_layout_board()

## Keep a forming pile at the current on-table spot of one of its cards.
func _anchor_pile_at(id: int) -> void:
	if id < 0 or not cards.has(id) or not is_instance_valid(cards[id]): return
	var view: Control = cards[id]
	var key := _pile_anchor_key(view.data)
	if key.is_empty(): return
	if manual_positions.has(id):
		pile_anchors[key] = manual_positions[id] # Its saved spot, even mid-animation.
		return
	var center: Vector2 = board.get_global_transform().affine_inverse() * (view.get_global_transform() * (view.size * 0.5))
	pile_anchors[key] = Vector2(center.x / board.size.x, center.y)

## The identical controlled permanent under the pointer, or -1.
func _stack_drop_target(view: Control, pointer: Vector2) -> int:
	if view.data.get("zone", "") != "Battlefield" or view.data.get("owner", -1) != 0: return -1
	var key: String = FieldLayout.stack_key(view.data)
	if key.is_empty(): return -1
	var target := -1
	var highest := -1000
	for id in cards:
		var candidate: Control = cards[id]
		if candidate == view or candidate.data.get("zone", "") != "Battlefield" or candidate.data.get("owner", -1) != 0: continue
		if FieldLayout.stack_key(candidate.data) != key: continue
		var local: Vector2 = candidate.get_global_transform().affine_inverse() * pointer
		if Rect2(Vector2.ZERO, candidate.size).has_point(local) and candidate.z_index >= highest:
			target = int(id)
			highest = candidate.z_index
	return target

func _equipment_drop_target(view: Control, pointer: Vector2) -> int:
	if not live or view.data.get("zone", "") != "Battlefield" or view.data.get("owner", -1) != 0 or not str(view.data.get("typeLine", "")).contains("Equipment"): return -1
	if snapshot.prompt.get("inputKind", "") != "InputPassPriority": return -1
	var target := -1
	var highest := -1000
	for id in cards:
		var candidate: Control = cards[id]
		if candidate == view or candidate.data.get("zone", "") != "Battlefield" or candidate.data.get("owner", -1) != 0 or not str(candidate.data.get("typeLine", "")).contains("Creature"): continue
		var local: Vector2 = candidate.get_global_transform().affine_inverse() * pointer
		if Rect2(Vector2.ZERO, candidate.size).has_point(local) and candidate.z_index >= highest:
			target = int(id)
			highest = candidate.z_index
	return target

func _bounded_card_center(view: Control, center: Vector2) -> Vector2:
	var area: Rect2 = player_areas[view.data.get("owner", 0)].get_global_rect().grow(-8)
	var extent := Vector2(view.size.y, view.size.x) * 0.5 if view.data.get("tapped", false) else view.size * 0.5
	return center.clamp(area.position + extent, area.end - extent)

func _hand_drop_area() -> Rect2:
	return Rect2(hand_root.global_position - Vector2(0, 24), Vector2(hand_root.size.x, hand_root.size.y + 24)).intersection(Rect2(Vector2.ZERO, size))

func _is_hand_play_drop(pointer: Vector2) -> bool:
	var visible_field: Rect2 = player_areas[0].get_global_rect().intersection(board_scroller.get_global_rect())
	return visible_field.has_point(pointer) and not hud[0].get_global_rect().has_point(pointer) and not hud_values[0].zone_tray.get_global_rect().has_point(pointer) and not step_panels[0].panel.get_global_rect().has_point(pointer)

func _place_pending_play(view: Control) -> void:
	var saved: Vector2 = play_positions[view.data.id].position
	if view.animation != null:
		view.animation.kill()
	if view.get_parent() != free_cards:
		view.reparent(free_cards)
	view.hand_mode = false
	view.table_angle = true
	view.hover_active = false
	view.hand_hover_amount = 0
	view.size = TABLE_CARD_SIZE
	view.rotation_degrees = 90 if view.data.get("tapped", false) else 0
	view.scale = Vector2.ONE
	view._arrange()
	var center: Vector2 = board.get_global_transform() * Vector2(saved.x * board.size.x, saved.y)
	center = _bounded_card_center(view, center)
	var local_center: Vector2 = board.get_global_transform().affine_inverse() * center
	play_positions[view.data.id].position = Vector2(local_center.x / board.size.x, local_center.y)
	view.position = local_center - TABLE_CARD_SIZE * 0.5
	view.settle(view.position, TABLE_CARD_SIZE, false, true)
	view.visual.show()
	view.show()

func _cancel_pointer_gesture() -> void:
	for view in zone_views.values():
		if view.press_pending:
			view._finish_press(true)
	for view in cards.values():
		if view.press_pending:
			view._finish_press(true)
	if library_pile != null:
		library_pile.cancel_drag()
	if opponent_divider != null:
		opponent_divider.cancel_drag()
		local_divider.cancel_drag()

func _update_actions() -> void:
	if live:
		_update_live_actions()
		return
	var local: bool = not selected.is_empty() and selected.get("owner", 0) == 0
	var in_hand: bool = local and selected.get("zone", "") == "Hand"
	var permanent: bool = local and selected.get("zone", "Battlefield") == "Battlefield"
	primary.text = "Play selected  →" if in_hand else ("Resolve demo spell  →" if not snapshot.get("stack", []).is_empty() else "Pass priority  →")
	primary.disabled = targeting
	return_button.visible = selected.get("availableActions", {}).get("returnToHand", false)
	return_button.disabled = targeting
	_update_turn_steps()
	prompt_title.text = "Choose a player" if targeting else (selected.get("name", "You have priority"))
	if targeting:
		prompt_body.text = "Click an opponent's player badge or life total. Escape cancels."
	elif in_hand:
		prompt_body.text = "Play this placeholder card. Costs and legality are not simulated."
	elif permanent:
		prompt_body.text = "Click an untapped creature to choose its defender. Hold and drag to move." if _attack_step() else "Click to tap or untap. Hold and drag to move the card."
	else:
		prompt_body.text = "Hover to inspect. Select a card, or advance the scripted turn."

func _select_stack_card(value: Dictionary) -> void:
	if live:
		_intent("stack", {"id": value.id})
		return
	var context := value.duplicate(true)
	context.owner = 0
	context.zone = "Stack"
	_select_card(context)

func _return_selected() -> void:
	if targeting or not selected.get("availableActions", {}).get("returnToHand", false):
		return
	hand_offset = 100000
	_intent("return_to_hand", {"id": selected.id})
	_notify("Unused play returned to hand / mock")

func _primary_action() -> void:
	if live and modal.visible:
		return
	if not _match_outcome().is_empty():
		if is_instance_valid(app_host) and app_host.has_method("request_end_game"): app_host.request_end_game()
		return
	if opening_hand.visible:
		opening_hand.submit("ok")
		return
	if targeting:
		return
	if live:
		_intent("ok")
		return
	if not selected.is_empty() and selected.get("owner", 0) == 0 and selected.get("zone", "") == "Hand":
		_intent("play", {"id": selected.id})
		_notify("Card played · mock interaction")
	else:
		_intent("advance")
		_notify(snapshot.game.phase + " · mock interaction")

func _attack_step() -> bool:
	return snapshot.game.activePlayer == 0 and snapshot.game.phase == "Declare attackers"

func _can_attack() -> bool:
	return _attack_step() and selected.get("owner", -1) == 0 and selected.get("zone", "") == "Battlefield" and selected.get("typeLine", "").contains("Creature") and not selected.get("tapped", false) and not selected.get("sick", false)

func _tap(use_hover: bool = false) -> void:
	# Keyboard actions follow the card under the pointer, never the last click.
	if use_hover:
		if not is_instance_valid(hovered_source) or not hovered_source.hover_active: return
		var hovered: Dictionary = hovered_source.data
		if hovered.get("hidden", false) or hovered.get("zone", "") != "Battlefield" or int(hovered.get("owner", -1)) != 0: return
		selected = hovered.duplicate(true)
	if live:
		if _attack_step() and snapshot.prompt.get("inputKind", "") == "InputAttack":
			_begin_targeting()
			return
		if not selected.is_empty():
			_pick(selected, false)
		return
	if targeting:
		return
	if not selected.is_empty() and selected.get("owner", -1) == 0 and selected.get("zone", "") == "Battlefield":
		if _attack_step() and selected.get("typeLine", "").contains("Creature"):
			_begin_targeting()
		else:
			_intent("tap", {"id": selected.id})

func _begin_targeting() -> void:
	if live and (not snapshot.get("connectionReady", false) or snapshot.prompt.get("inputKind", "") != "InputAttack" or not snapshot.asks.is_empty()):
		return
	if not _can_attack():
		if not selected.is_empty(): _reject_card_action(int(selected.id))
		_notify("This creature has summoning sickness and cannot attack yet." if selected.get("sick", false) else "Choose an untapped creature during attacker selection.")
		return
	targeting = true
	_update_actions()
	_update_lines()

func _choose_player(id: int) -> void:
	if is_instance_valid(board_choice) and board_choice.visible:
		board_choice.select_entity("player", int(snapshot.players[id].get("engineId", id)))
		return
	if live:
		if targeting:
			if _attackable_seat(id) and _can_attack() and snapshot.get("connectionReady", false):
				var attacker_id: int = selected.id
				_cancel_attack_target()
				_intent("attack", {"id": attacker_id, "target": id})
			return
		_intent("player", {"id": id})
		return
	if targeting and _attackable_seat(id) and _can_attack():
		targeting = false
		_intent("attack", {"id": selected.id, "target": id})
		_notify("Attack feedback · 3 demo damage")
	elif not targeting:
		_show_player(id)

## Any opponent seat still in the game (2-4 player tables); Forge validates the actual defender.
func _attackable_seat(id: int) -> bool:
	return id > 0 and id < snapshot.get("players", []).size() and not snapshot.players[id].get("lost", false)

func _update_lines() -> void:
	if targeting_overlay == null:
		return
	var lines: Array = []
	if targeting and not selected.is_empty() and cards.has(selected.id):
		lines.append([(cards[selected.id].get_global_transform() * (cards[selected.id].size * 0.5)), Vector2.INF])
	for combat in snapshot.get("combat", []):
		for blocker_id in combat.get("blockers", []):
			if cards.has(int(blocker_id)) and cards.has(int(combat.attacker)):
				var blocker: Control = cards[int(blocker_id)]
				var attacker: Control = cards[int(combat.attacker)]
				lines.append([attacker.get_global_transform() * (attacker.size * 0.5), blocker.get_global_transform() * (blocker.size * 0.5), Color("80d9ff")])
		if combat.get("blockers", []).is_empty() and (not combat.get("blocked", false) or combat.get("trample", false)) and cards.has(combat.attacker) and hud.has(combat.defenderId) and not (targeting and selected.get("id", -1) == combat.attacker):
			lines.append([(cards[combat.attacker].get_global_transform() * (cards[combat.attacker].size * 0.5)), hud_values[combat.defenderId].portrait.get_global_rect().get_center()])
	targeting_overlay.lines = lines

func _cancel_attack_target() -> void:
	targeting = false
	_update_actions()
	_update_lines()

func _secondary_action() -> void:
	if opening_hand.visible:
		opening_hand.submit("cancel")
		return
	if targeting:
		_cancel_attack_target()
	elif hand_pick_panel.visible and not snapshot.get("prompt", {}).get("cancelEnabled", false):
		return # A required hand pick (discard) has nothing to cancel.
	else:
		_intent("cancel")

func _use_mana(code: int) -> void:
	_intent("mana", {"id": code})

func _update_live_actions() -> void:
	if snapshot.is_empty():
		primary.disabled = true
		cancel_button.disabled = true
		library_pile.enabled = false
		library_pile.hide()
		library_count.hide()
		for button in mana_buttons + live_buttons:
			button.disabled = true
		return
	var ready: bool = snapshot.get("connectionReady", false)
	var controls_ready: bool = ready and snapshot.asks.is_empty() and not snapshot.game.get("gameOver", false) and not StartingPlayerDialog.needs_selection(snapshot)
	prompt_body.visible = not StartingPlayerDialog.needs_selection(snapshot)
	primary.text = snapshot.prompt.get("okLabel", "OK")
	if not snapshot.get("takebackCast", {}).is_empty():
		primary.text = "Continue"
	primary.disabled = not controls_ready or not snapshot.prompt.get("okEnabled", false)
	primary.disabled = primary.disabled or targeting
	primary.tooltip_text = "Forge's primary action / Space"
	if not snapshot.get("takebackCast", {}).is_empty():
		primary.tooltip_text = "Commit the cast and pass priority. Drag the card back to hand to undo its payment instead."
	cancel_button.text = snapshot.prompt.get("cancelLabel", "Cancel")
	cancel_button.disabled = not controls_ready or not snapshot.prompt.get("cancelEnabled", false)
	if targeting:
		cancel_button.text = "Cancel target"
		cancel_button.disabled = false
	return_button.hide()
	prompt_title.text = "Match complete" if snapshot.game.get("gameOver", false) else "Forge"
	prompt_body.text = str(snapshot.game.get("winner", "")) if snapshot.game.get("gameOver", false) else snapshot.prompt.get("message", "Waiting for Forge")
	if snapshot.prompt.get("inputKind", "") == "InputBlock":
		prompt_body.text += "\n\nClick an attacking creature, then your creature to block it. Click the blocker again to remove that assignment. Blue arrows show blocks. Press OK when finished."
	if not snapshot.get("takebackCast", {}).is_empty():
		prompt_body.text = "Cast accepted. Drag it back to hand to undo the card and mana, or Continue to commit."
	if Live.is_automatic_stack(snapshot):
		primary.text = "Resolving…"
		primary.disabled = true
		primary.tooltip_text = "Forge is handling priority and opponent responses."
		prompt_body.text = "Forge is resolving the action."
	elif snapshot.prompt.get("inputKind", "") == "InputPassPriority" and not snapshot.get("stack", []).is_empty() and snapshot.get("takebackCast", {}).is_empty():
		primary.text = "Resolve"
		primary.tooltip_text = "Pass this response window. You can cast an instant or activate an ability before continuing."
	phase_title.text = snapshot.game.phase
	if _attack_step():
		if snapshot.prompt.get("inputKind", "") == "InputAttack":
			phase_title.text = "Choose attackers"
			var attack_count: int = snapshot.get("combat", []).size()
			primary.text = "Skip attacking" if attack_count == 0 else "Confirm attacks"
			primary.tooltip_text = "Finish attacker selection with no attackers." if attack_count == 0 else "Commit your selected attackers. Forge handles tapping and any actual attack costs."
			prompt_body.text = "Click your creature, then an opponent's avatar to attack them. Attacking does not activate the creature's abilities. Select all attackers before confirming."
		elif snapshot.prompt.get("inputKind", "") == "InputPassPriority" and not Live.is_automatic_stack(snapshot):
			var has_attackers: bool = not snapshot.get("combat", []).is_empty()
			phase_title.text = "After attackers" if has_attackers else "No attackers"
			primary.text = ("Continue to blockers" if has_attackers else "Continue to main 2") if snapshot.get("stack", []).is_empty() else "Resolve combat effects"
			primary.tooltip_text = "Finish the response window after attackers and continue combat."
			if has_attackers:
				prompt_body.text += "\n\nAttackers are declared. You may cast an instant or activate an ability before continuing to blockers."
			else:
				primary.tooltip_text = "Finish this response window and continue to your second main phase."
				prompt_body.text += "\n\nNo attackers were declared. You may cast an instant or activate an ability before continuing to your second main phase."
	if targeting:
		prompt_title.text = "Choose who to attack"
		prompt_body.text = "Click an opponent's avatar. Escape cancels this selection."
	var outcome := _match_outcome()
	if outcome.get("title", "") == "Victory" and not victory_announced:
		victory_announced = true
		_announce_victory.call_deferred()
	elif outcome.get("title", "") == "Defeated" and not defeat_announced:
		defeat_announced = true
		_show_outcome_screen.call_deferred(false)
	if not outcome.is_empty():
		# Forge sends no prompt once this seat is out, so offer a clear way to finish.
		phase_title.text = outcome.title
		prompt_title.text = outcome.title
		prompt_body.text = outcome.body
		primary.text = "End game"
		primary.tooltip_text = "End this game and return to the computer."
		primary.disabled = not is_instance_valid(app_host)
		cancel_button.visible = false
	for i in range(mana_buttons.size()):
		mana_buttons[i].set_amount(int(snapshot.players[0].mana.get(ManaCounter.KEYS[i], 0)), controls_ready)
	for button in live_buttons:
		button.disabled = not controls_ready
		button.visible = outcome.is_empty()
	for child in stack_box.get_children():
		if child is Button:
			child.disabled = not controls_ready
	if open_ask >= 0 and is_instance_valid(modal_panel):
		modal_panel.set_submission_enabled(ready)
	_update_turn_steps()

## A win shows the YOU WIN screen once; I WON continues straight into the usual end-of-game wipe.
func _announce_victory() -> void:
	if not live or not is_instance_valid(app_host) or not app_host.has_method("end_after_victory"): return
	_show_outcome_screen(true)

## Full-screen YOU WIN / YOU LOSE. "I lost" closes it so the player can keep spectating.
func _show_outcome_screen(won: bool) -> void:
	if is_instance_valid(outcome_screen): outcome_screen.queue_free()
	outcome_screen = preload("res://scripts/ui/OutcomeScreen.gd").new()
	outcome_screen.z_index = 130
	add_child(outcome_screen)
	outcome_screen.present(won)
	outcome_screen.acknowledged.connect(func():
		outcome_screen.queue_free()
		outcome_screen = null
		if won and is_instance_valid(app_host) and app_host.has_method("end_after_victory"): app_host.end_after_victory())

## Defeat or game over for the local seat, as rail text; empty while still playing.
func _match_outcome() -> Dictionary:
	if not live or snapshot.is_empty() or snapshot.get("players", []).is_empty():
		return {}
	var me: Dictionary = snapshot.players[0]
	var lost: bool = me.get("lost", false)
	var finish := " End the game to return to the computer."
	if snapshot.game.get("gameOver", false):
		var winner := str(snapshot.game.get("winner", ""))
		if not lost and winner == str(me.get("name", "")):
			return {"title": "Victory", "body": "You won the game." + finish}
		var result := (winner + " won the game.") if not winner.is_empty() else "The game is over."
		return {"title": "Defeated" if lost else "Match complete", "body": ("You were defeated. " if lost else "") + result + finish}
	if lost:
		return {"title": "Defeated", "body": "You lost this game. The remaining players are still finishing it, and you have no more decisions to make." + finish + " You can also keep watching."}
	return {}

func _clear_live_session() -> void:
	coin_toss_seen.clear()
	victory_announced = false
	defeat_announced = false
	if is_instance_valid(outcome_screen): outcome_screen.queue_free()
	outcome_screen = null
	opening_hand_released = false
	target_gallery_requested = false
	target_gallery_on_board = false
	interaction_panel.present({}, true)
	_close_zone_browser()
	incoming_effect.reset()
	library_draw_pending = false
	library_ghost.hide()
	stack_attention.present({})
	opening_hand.reset()
	_cancel_pointer_gesture()
	for view in cards.values():
		view.queue_free()
	cards.clear()
	for view in hand_copies.values():
		view.queue_free()
	hand_copies.clear()
	manual_positions.clear()
	split_pile_cards.clear()
	local_pile_members.clear()
	pile_anchors.clear()
	pile_drag_ids.clear()
	play_positions.clear()
	announced_land_returns.clear()
	pending_returns.clear()
	hand_order.clear()
	hand_offset = 0
	hand_gap_index = -1
	pending_hand_slot = -1
	pending_hand_origin = Vector2.INF
	hovered_source = null
	selected = {}
	snapshot = {}
	targeting = false
	_close_modal()

func _show_revealed() -> void:
	if snapshot.is_empty():
		return
	_prepare_modal()
	open_ask = -1
	var panel := Prompt.new()
	modal_center.add_child(panel)
	modal_panel = panel
	panel.answered.connect(func(_id, _value): _close_modal())
	var options: Array = snapshot.get("revealed", []).map(func(card): return {"label": card.get("name", "Hidden card"), "card": card})
	panel.present({"id": -1, "kind": "message", "title": "Revealed cards", "message": "No cards revealed." if options.is_empty() else "", "options": options})

func _reset() -> void:
	if live:
		_intent("refresh")
		return
	_cancel_pointer_gesture()
	_close_zone_browser()
	_cancel_library_draw_preview()
	incoming_effect.reset()
	for view in cards.values():
		view.drop_pointer = Vector2.INF
	manual_positions.clear()
	split_pile_cards.clear()
	local_pile_members.clear()
	pile_anchors.clear()
	pile_drag_ids.clear()
	play_positions.clear()
	announced_land_returns.clear()
	pending_returns.clear()
	board_scroller.scroll_vertical = 0
	for row in rows.values():
		row.scroll.scroll_horizontal = 0
	selected = {}
	hand_offset = 0
	hand_order.clear()
	hand_gap_index = -1
	pending_hand_slot = -1
	pending_hand_origin = Vector2.INF
	hand_focus_id = -1
	targeting = false
	_close_modal()
	_intent("reset")
	_notify("The mock table has been reset.")

func _notify(message: String) -> void:
	if library_draw_pending:
		_cancel_library_draw_preview()
	var rejected_drop := not pending_returns.is_empty()
	pending_returns.clear()
	for id in play_positions.keys():
		if cards.has(id) and cards[id].data.zone == "Hand":
			play_positions.erase(id)
			rejected_drop = true
	if rejected_drop:
		_layout_board()
	if live and open_ask >= 0 and is_instance_valid(modal_panel):
		modal_panel.show_error(message)
	_show_toast(message)

func _show_toast(message: String, seconds: float = 1.8) -> void:
	toast.text = message
	toast.modulate.a = 1
	if toast_tween != null:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(seconds)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.3)

var announced_land_returns: Dictionary = {}

## Forge's own priority-time scan (the bridge's weakSelection) marks what this seat can cast or
## play right now with its available mana: hand, commander and graveyard/exile casts.
func _playable(card: Dictionary, owner: int, zone: String) -> bool:
	if not live or owner != 0 or zone == "Battlefield" or card.get("hidden", false): return false
	if snapshot.get("prompt", {}).get("inputKind", "") != "InputPassPriority" or not snapshot.get("asks", []).is_empty(): return false
	return int(card.get("weakSelection", 0)) > 0

## A playable card your floating mana already pays for (teal instead of purple). Lands and other
## free plays stay purple: tapping mana changes nothing for them. Graveyard/exile casts use other
## costs (flashback, escape) than the printed one, so only hand and commander casts turn teal.
func _ready_now(card: Dictionary, zone: String) -> bool:
	if zone not in ["Hand", "Command"]: return false
	var pool: Dictionary = snapshot.get("players", [{}])[0].get("mana", {})
	if pool.values().all(func(amount): return int(amount) <= 0): return false
	if str(card.get("typeLine", "")).contains("Land") and not str(card.get("typeLine", "")).contains("//"): return false
	var cost := str(card.get("manaCost", ""))
	var ManaPips = preload("res://scripts/ui/ManaPips.gd")
	if ManaPips.parse(cost).is_empty(): return false
	return ManaPips.pool_covers(cost, pool, int(card.get("commanderTax", 0)) if zone == "Command" else 0)

## A land you played that bounced straight back (Dimir Aqueduct with no other land) looks like a
## rejected play; Forge's log says it was accepted, so explain that the land drop is spent.
func _announce_returned_lands() -> void:
	if not live or snapshot.get("players", []).is_empty(): return
	var me: Dictionary = snapshot.players[0]
	for entry in snapshot.get("log", []):
		var text := str(entry)
		# Forge's log may use a different display name; the instance ID identifies the card.
		if not text.begins_with("Land: ") or not text.contains(" played ") or announced_land_returns.has(text + str(snapshot.game.get("turn", 0))): continue
		var id := int(text.get_slice("(", text.get_slice_count("(") - 1).trim_suffix(")"))
		# Still entering: decide once its trigger has resolved. A land that stayed is settled.
		if me.get("zones", {}).get("Battlefield", []).any(func(card): return int(card.get("id", -1)) == id):
			if snapshot.get("stack", []).is_empty(): announced_land_returns[text + str(snapshot.game.get("turn", 0))] = true
			continue
		announced_land_returns[text + str(snapshot.game.get("turn", 0))] = true
		var card_name := text.get_slice(" played ", 1).get_slice(" (", 0)
		if me.get("zones", {}).get("Hand", []).any(func(card): return int(card.get("id", -1)) == id):
			_show_toast("%s returned to your hand. Your land drop for this turn is used." % card_name, 5.0)

func _reject_card_action(id: int) -> void:
	var view: Control = cards.get(id, zone_views.get(id))
	if is_instance_valid(view): view.reject_action()
	if is_instance_valid(hovered_source) and int(hovered_source.data.get("id", -1)) == id:
		raised_card.reject_action()

func _prepare_modal() -> void:
	if is_instance_valid(modal_panel) and modal_panel is CoinTossDialog:
		modal_panel.set_process(false)
		coin_toss_seen[modal_panel.toss_id] = true
	_set_decision_board(false)
	modal.get_child(0).self_modulate.a = 1.0
	modal_center.offset_bottom = 0
	for child in modal_center.get_children():
		modal_center.remove_child(child)
		child.queue_free()
	modal.show()

func _open_decision(ask: Dictionary) -> void:
	_prepare_modal()
	open_ask = ask.id
	var panel := Prompt.new()
	panel.custom_minimum_size.x = 520
	modal_center.add_child(panel)
	modal_panel = panel
	panel.answered.connect(func(id: int, value: Variant): _intent("answer", {"id": id, "value": value}))
	panel.board_requested.connect(_toggle_decision_board)
	panel.present(_rank_table_types(ask))

## A creature type choice lists the types visible on the table first; Forge already ranks your own deck next.
func _rank_table_types(ask: Dictionary) -> Dictionary:
	if not str(ask.get("title", "")).to_lower().contains("creature type"): return ask
	var counts: Dictionary = {}
	for player in snapshot.get("players", []):
		for zone in ["Battlefield", "Graveyard", "Exile", "Command"]:
			for card in player.get("zones", {}).get(zone, []):
				if card.get("hidden", false) or card.get("faceDown", false): continue
				for type in _creature_types(str(card.get("typeLine", ""))): counts[type] = int(counts.get(type, 0)) + 1
	var ranked: Dictionary = ask.duplicate(true)
	for option in ranked.get("options", []):
		var count := int(counts.get(str(option.get("label", "")), 0))
		if count > 0:
			option.tableCount = count
			option.label = "%s  ·  %d on the table" % [option.label, count]
	return ranked

static func _creature_types(type_line: String) -> PackedStringArray:
	if not type_line.contains("Creature"): return PackedStringArray()
	for separator in ["—", "–", " - ", "·"]:
		if type_line.contains(separator): return type_line.get_slice(separator, 1).strip_edges().split(" ", false)
	return PackedStringArray()

## A decision stepped aside with View battlefield leaves the whole table readable.
func _modal_covers_table() -> bool:
	return modal.visible and not decision_board_button.visible

func _toggle_decision_board() -> void:
	_set_decision_board(not decision_board_button.visible)

var decision_board_pulse: Tween

func _set_decision_board(show_board: bool) -> void:
	if not is_instance_valid(decision_board_button): return
	modal_center.visible = not show_board
	modal.get_child(0).visible = not show_board
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE if show_board else Control.MOUSE_FILTER_STOP
	decision_board_button.visible = show_board
	if decision_board_pulse != null: decision_board_pulse.kill()
	decision_board_button.modulate = Color.WHITE
	if not show_board: return
	# A large, gently pulsing, see-through button in the middle of the table: impossible to miss.
	var title := ""
	if not snapshot.get("asks", []).is_empty(): title = str(snapshot.asks[0].get("title", ""))
	if title.is_empty(): title = str(snapshot.get("prompt", {}).get("message", "")).get_slice("\n", 0)
	decision_board_button.text = "◀  RETURN TO DECISION" + ("\n" + (title.left(34) + ("…" if title.length() > 34 else "")) if not title.is_empty() else "")
	_place_decision_board_button()
	_pulse_decision_board(decision_board_button.get_global_rect().has_point(get_global_mouse_position()))

func _place_decision_board_button() -> void:
	var table: Rect2 = board_scroller.get_global_rect() if is_instance_valid(board_scroller) and board_scroller.is_visible_in_tree() else get_global_rect()
	var button_size := Vector2(minf(480.0, table.size.x - 32.0), 124)
	var center: Vector2 = modal.get_global_transform().affine_inverse() * table.get_center()
	decision_board_button.size = button_size
	decision_board_button.position = (center - button_size * 0.5).round()

func _pulse_decision_board(hovered: bool) -> void:
	if decision_board_pulse != null: decision_board_pulse.kill()
	decision_board_pulse = null
	if not decision_board_button.visible: return
	if hovered:
		decision_board_button.modulate = Color(1.15, 1.15, 1.15, 1.0)
		return
	decision_board_button.modulate = Color(1, 1, 1, 0.55)
	decision_board_pulse = create_tween().set_loops()
	decision_board_pulse.tween_property(decision_board_button, "modulate:a", 0.75, 0.8)
	decision_board_pulse.tween_property(decision_board_button, "modulate:a", 0.5, 0.8)

func _board_ask(ask: Dictionary) -> bool:
	return ask.get("kind", "") == "choose" and ask.get("bulkSelection", false) and ask.get("options", []).all(func(option): return option.has("playerId") or (cards.has(int(option.get("cardId", -1))) and cards[int(option.cardId)].data.get("zone", "") == "Battlefield"))

func _present_coin_toss() -> bool:
	var toss: Dictionary = snapshot.get("startingToss", {})
	var current: bool = is_instance_valid(modal_panel) and modal_panel is CoinTossDialog
	var wanted := false
	if not toss.is_empty() and snapshot.get("asks", []).is_empty() and not snapshot.get("game", {}).get("gameOver", false):
		var id := int(toss.id)
		var pending: bool = not coin_toss_seen.has(id) and (int(snapshot.game.get("turn", 0)) == 0 or current)
		wanted = pending or (toss.get("choosing", false) and int(toss.get("winnerSeat", -1)) != 0)
		if wanted:
			# Begin on the visible table, after the boot/zoom fade has finished.
			if transition_preview or transition_reveal: return true
			if not current or int(modal_panel.toss_id) != id:
				_prepare_modal()
				open_ask = -2
				var panel := CoinTossDialog.new()
				modal_center.add_child(panel)
				modal_panel = panel
				panel.settled.connect(func():
					coin_toss_seen[id] = true
					_present_card_selection.call_deferred())
			modal.show()
			modal_panel.present(snapshot)
			return true
	if current: _close_modal()
	return false

## A Forge card selection drawn only from your own hand (discard, put back) is made on the hand itself:
## the table dims, the hand stays usable, a click toggles the card in Forge and this prompt confirms.
func _hand_pick_active() -> bool:
	if not live or snapshot.is_empty() or not snapshot.get("asks", []).is_empty() or snapshot.get("players", []).is_empty(): return false
	var prompt: Dictionary = snapshot.get("prompt", {})
	if prompt.get("inputKind", "") != "InputSelectCardsFromList" or prompt.has("selectionShortcut"): return false
	var offered: Array = prompt.get("cards", [])
	if offered.is_empty(): return false
	var hand_ids := {}
	for card in snapshot.players[0].get("zones", {}).get("Hand", []): hand_ids[int(card.id)] = true
	return offered.all(func(card): return hand_ids.has(int(card.id)))

func _hand_pick_is_discard() -> bool:
	return str(snapshot.get("prompt", {}).get("message", "")).to_lower().contains("discard")

func _build_hand_pick_panel() -> void:
	hand_pick_panel = PanelContainer.new()
	hand_pick_panel.z_index = 30
	hand_pick_panel.custom_minimum_size.x = 420
	P.style_popup(hand_pick_panel)
	hand_pick_panel.hide()
	add_child(hand_pick_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	hand_pick_panel.add_child(column)
	hand_pick_title = _label("", 22)
	column.add_child(hand_pick_title)
	hand_pick_message = _label("", 14, Color("bfc4ca"))
	hand_pick_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hand_pick_message.custom_minimum_size.x = 380
	column.add_child(hand_pick_message)
	hand_pick_count = _label("", 13, P.MUTED)
	column.add_child(hand_pick_count)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	hand_pick_confirm = _button("Confirm", func(): _intent("ok"), "Confirm the selected cards (Q)")
	P.style_popup_button(hand_pick_confirm, true)
	hand_pick_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(hand_pick_confirm)
	hand_pick_cancel = _button("Cancel", func(): _intent("cancel"))
	P.style_popup_button(hand_pick_cancel)
	buttons.add_child(hand_pick_cancel)
	resized.connect(_place_hand_pick)

## Shows or hides the hand-pick prompt; true while it owns the decision.
func _present_hand_pick() -> bool:
	if hand_pick_panel == null: return false
	var active := _hand_pick_active()
	hand_pick_panel.visible = active
	hand_pick_shade.visible = active
	if not active: return false
	var prompt: Dictionary = snapshot.prompt
	var discard := _hand_pick_is_discard()
	var chosen: int = prompt.get("chosen", []).size()
	var low := int(prompt.get("selMin", 0))
	var high := int(prompt.get("selMax", 0))
	var ready: bool = snapshot.get("connectionReady", false) and snapshot.get("pendingDraws", []).is_empty()
	hand_pick_title.text = "DISCARD" if discard else "CHOOSE FROM YOUR HAND"
	hand_pick_title.add_theme_color_override("font_color", Color("ff6b6b") if discard else P.TEXT)
	# Forge names the source with its engine id ("Faithless Looting (304)"); players don't need the number.
	var id_suffix := RegEx.create_from_string(" \\(\\d+\\)")
	hand_pick_message.text = id_suffix.sub(str(prompt.get("message", "")), "", true).strip_edges()
	hand_pick_count.text = ("%d of %d selected" % [chosen, high] if low == high else "%d selected (%d–%d)" % [chosen, low, high]) + "   ·   click cards in your hand"
	hand_pick_confirm.text = "Discard" if discard else "Confirm"
	hand_pick_confirm.disabled = not ready or not prompt.get("okEnabled", false) or (chosen == 0 and low > 0)
	hand_pick_cancel.visible = prompt.get("cancelEnabled", false)
	hand_pick_cancel.disabled = not ready
	_place_hand_pick.call_deferred()
	return true

## Centered over the table, above the hand fan, so it never covers the cards being picked.
func _place_hand_pick() -> void:
	if hand_pick_panel == null or not hand_pick_panel.visible: return
	hand_pick_panel.reset_size()
	var table: Rect2 = board_scroller.get_global_rect() if is_instance_valid(board_scroller) and board_scroller.is_visible_in_tree() else get_global_rect()
	var center: Vector2 = get_global_transform().affine_inverse() * Vector2(table.get_center().x, table.position.y + table.size.y * 0.4)
	hand_pick_panel.position = (center - hand_pick_panel.size * 0.5).round()

func _present_card_selection() -> void:
	if _present_coin_toss(): return
	if _present_hand_pick():
		if is_instance_valid(modal_panel) and modal_panel is SelectionDialog: _close_modal()
		return
	var reveal_pending: bool = snapshot.asks.is_empty() and snapshot.prompt.get("inputKind", "") == "InputConfirm" and not snapshot.get("revealed", []).is_empty()
	if reveal_pending:
		if not native_reveal or not is_instance_valid(modal_panel):
			_prepare_modal()
			open_ask = -2
			native_reveal = true
			var reveal_panel := Prompt.new()
			modal_center.add_child(reveal_panel)
			modal_panel = reveal_panel
			reveal_panel.answered.connect(func(_id, _value): _intent("ok"))
			reveal_panel.board_requested.connect(_toggle_decision_board)
			reveal_panel.present({"id": -2, "kind": "message", "title": snapshot.prompt.get("message", "Revealed hand"), "sourceCard": snapshot.prompt.get("sourceCard", {}), "options": snapshot.revealed.map(func(card): return {"label": card.get("name", "Card"), "card": card})})
		modal_panel.set_submission_enabled(snapshot.get("connectionReady", false) and snapshot.prompt.get("okEnabled", false))
		return
	if native_reveal: _close_modal()
	if snapshot.prompt.get("inputKind", "") != "InputSelectTargets":
		target_gallery_requested = false
		target_gallery_on_board = false
	if ManaColorDialog.needs_selection(snapshot):
		if not is_instance_valid(modal_panel) or not modal_panel is ManaColorDialog:
			_prepare_modal()
			open_ask = -2
			modal_panel = ManaColorDialog.new()
			modal_center.add_child(modal_panel)
			modal_panel.action_requested.connect(func(action): _intent(action))
		modal.show()
		modal_panel.present(snapshot)
		return
	if is_instance_valid(modal_panel) and modal_panel is ManaColorDialog:
		_close_modal()
	var paying: bool = snapshot.asks.is_empty() and snapshot.prompt.get("inputKind", "") == "InputPayManaOfCostPayment" and int(snapshot.get("pendingCastId", -1)) < 0
	var payment_key: String = JSON.stringify([snapshot.prompt, snapshot.players[0].mana]) if paying else ""
	if paying and int(snapshot.get("pendingEquipId", -1)) >= 0: payment_key = "equip:" + str(snapshot.pendingEquipId)
	if not paying: deferred_mana_payment = ""
	if paying and payment_key != deferred_mana_payment:
		if not is_instance_valid(modal_panel) or not modal_panel is ManaPaymentDialog:
			_prepare_modal()
			open_ask = -2
			var panel := ManaPaymentDialog.new()
			modal_center.add_child(panel)
			modal_panel = panel
			panel.mana_selected.connect(func(code): _intent("mana", {"id": code}))
			panel.cancel_requested.connect(func(): _intent("cancel"))
			panel.sources_requested.connect(func():
				deferred_mana_payment = "equip:" + str(snapshot.pendingEquipId) if int(snapshot.get("pendingEquipId", -1)) >= 0 else JSON.stringify([snapshot.prompt, snapshot.players[0].mana])
				_close_modal())
		modal.show()
		modal_panel.present(snapshot)
		return
	if is_instance_valid(modal_panel) and modal_panel is ManaPaymentDialog:
		_close_modal()
	if StartingPlayerDialog.needs_selection(snapshot):
		if not is_instance_valid(modal_panel) or not modal_panel is StartingPlayerDialog:
			_prepare_modal()
			open_ask = -2
			var panel := StartingPlayerDialog.new()
			modal_center.add_child(panel)
			modal_panel = panel
			panel.player_selected.connect(func(id): _intent("player", {"id": id}))
		modal.show()
		modal_panel.present(snapshot)
		return
	var targeting_offboard: bool = not target_gallery_on_board and snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and snapshot.prompt.get("cards", []).any(func(card): return not cards.has(int(card.id)))
	var target_gallery: bool = snapshot.prompt.get("inputKind", "") == "InputSelectTargets" and (target_gallery_requested or targeting_offboard)
	var board_native: bool = snapshot.prompt.has("selectionShortcut") and snapshot.prompt.get("inputKind", "") in ["InputSelectCardsFromList", "InputSelectEntitiesFromList"]
	var needs_selection: bool = not board_native and snapshot.asks.is_empty() and (snapshot.prompt.get("inputKind", "") in ["InputSelectCardsFromList", "InputSelectEntitiesFromList", "InputSelectStackItems"] or target_gallery) and (not snapshot.prompt.get("cards", []).is_empty() or not snapshot.prompt.get("entities", []).is_empty())
	if not needs_selection:
		if is_instance_valid(modal_panel) and (modal_panel is SelectionDialog or modal_panel is StartingPlayerDialog):
			_close_modal()
		return
	if not is_instance_valid(modal_panel) or not modal_panel is SelectionDialog:
		_prepare_modal()
		open_ask = -2
		var panel := preload("res://scripts/ui/SelectionPanel.gd").new()
		modal_center.add_child(panel)
		modal_panel = panel
		panel.selected_card.connect(func(id): _intent("card", {"id": id}))
		panel.entity_selected.connect(func(action, id): _intent(action, {"id": id}))
		panel.board_requested.connect(func():
			if snapshot.prompt.get("inputKind", "") == "InputSelectTargets":
				target_gallery_requested = false
				target_gallery_on_board = true
				_close_modal()
				_present_interaction()
			else: _toggle_decision_board())
		panel.action_requested.connect(func(action): _intent(action))
	modal.show()
	modal_panel.present(snapshot)

func _dismiss_modal() -> void:
	# Only informational windows may be dismissed locally. Negative IDs also
	# identify synchronous engine selections (-2), not just information (-1).
	if open_ask == -1:
		_close_modal()

func _close_modal() -> void:
	if is_instance_valid(modal_panel) and modal_panel is CoinTossDialog: modal_panel.set_process(false)
	_set_decision_board(false)
	native_reveal = false
	if modal != null:
		modal.hide()
	open_ask = -1
	modal_panel = null

func _information(title: String, body: String) -> VBoxContainer:
	_prepare_modal()
	open_ask = -1
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 520
	P.style_popup(panel)
	modal_center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 17)
	panel.add_child(column)
	column.add_child(_label(title, 25))
	var label := _label(body, 14, Color("bfc4ca"))
	label.name = "BodyText"
	label.custom_minimum_size.x = 470
	label.size.x = 470
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var body_scroll := ScrollContainer.new()
	body_scroll.name = "BodyScroll"
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(body_scroll)
	body_scroll.add_child(label)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.custom_minimum_size = Vector2(470, minf(label.get_minimum_size().y, minf(360, size.y * 0.4)))
	var back := _button("Back to table", _close_modal)
	P.style_popup_button(back, true)
	column.add_child(back)
	return column

func _set_ui_layout(key: String, value: float) -> void:
	ui_layout[key] = value
	_apply_table_style()
	if key in ["pile_spread", "pile_tap"] and not snapshot.is_empty(): _layout_board()
	_layout_hand()
	_save_table_settings()

var sound_mark: Callable

func _files_dropped(files: PackedStringArray) -> void:
	for path in files:
		if not path.to_lower().ends_with(".mp3"): continue
		if NotificationSound.import_custom(path):
			_set_ui_layout("notify_sound", 4.0)
			notify_sound.play_cue()
			if sound_mark.is_valid(): sound_mark.call()
			toast.text = "Custom notification sound set."
		else:
			toast.text = "That MP3 could not be read."
		toast.modulate.a = 1
		if toast_tween != null: toast_tween.kill()
		toast_tween = create_tween()
		toast_tween.tween_interval(1.8)
		toast_tween.tween_property(toast, "modulate:a", 0.0, 0.3)
		return

func _show_table_settings() -> void:
	var column := _information("Table settings", "Changes apply right away and save for every game.")
	# Keep the hand and library in view while they are being adjusted.
	modal.get_child(0).self_modulate.a = 0.3
	modal_center.offset_bottom = -200
	var sliders: Array = []
	var position_in_column := column.get_child_count() - 1
	column.add_theme_constant_override("separation", 12)
	# Two columns keep every setting on screen above the hand and library.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	column.move_child(grid, position_in_column)
	position_in_column += 1
	for setting in UI_LAYOUT_SETTINGS:
		var row := VBoxContainer.new()
		row.add_child(_label(setting.title, 14))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var low := _label(setting.low, 13, Color("bfc4ca"))
		low.custom_minimum_size.x = 44
		line.add_child(low)
		var slider := HSlider.new()
		slider.name = setting.key
		slider.min_value = setting.min
		slider.max_value = setting.max
		slider.step = setting.step
		slider.value = ui_layout[setting.key]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.y = 28
		slider.focus_mode = Control.FOCUS_NONE
		slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slider.value_changed.connect(func(value: float): _set_ui_layout(setting.key, value))
		line.add_child(slider)
		var high := _label(setting.high, 13, Color("bfc4ca"))
		high.custom_minimum_size.x = 44
		high.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(high)
		row.add_child(line)
		row.custom_minimum_size.x = 380
		grid.add_child(row)
		sliders.append(slider)
	var backs := VBoxContainer.new()
	backs.add_child(_label("Library card back", 14))
	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 8)
	var back_buttons: Array = []
	for index in range(CARD_BACKS.size()):
		var thumb := AtlasTexture.new()
		thumb.atlas = preload("res://assets/forge-sleeves.png")
		thumb.region = CARD_BACKS[index].region
		var choice := TextureButton.new()
		choice.texture_normal = thumb
		choice.ignore_texture_size = true
		choice.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		choice.custom_minimum_size = Vector2(54, 75)
		choice.tooltip_text = CARD_BACKS[index].name
		choice.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		choice.focus_mode = Control.FOCUS_NONE
		back_row.add_child(choice)
		back_buttons.append(choice)
	var mark_back := func():
		for index in range(back_buttons.size()):
			back_buttons[index].modulate = Color.WHITE if index == int(ui_layout.card_back) else Color(1, 1, 1, 0.45)
	for index in range(back_buttons.size()):
		back_buttons[index].pressed.connect(func():
			_set_ui_layout("card_back", float(index))
			mark_back.call())
	mark_back.call()
	backs.add_child(back_row)
	var extras := GridContainer.new()
	extras.columns = 2
	extras.add_theme_constant_override("h_separation", 32)
	extras.add_child(backs)
	column.add_child(extras)
	column.move_child(extras, position_in_column)
	position_in_column += 1
	var sounds := VBoxContainer.new()
	sounds.add_child(_label("Sound when the stack needs you", 14))
	var sound_row := HBoxContainer.new()
	sound_row.add_theme_constant_override("separation", 6)
	var sound_buttons: Array = []
	for index in range(NotificationSound.CHOICES.size()):
		var option := _button(NotificationSound.CHOICES[index], func(): pass)
		P.style_popup_button(option)
		option.disabled = index == 4 and not NotificationSound.has_custom()
		sound_row.add_child(option)
		sound_buttons.append(option)
	var mark_sound := func():
		for index in range(sound_buttons.size()):
			sound_buttons[index].modulate = Color.WHITE if index == int(ui_layout.notify_sound) else Color(1, 1, 1, 0.5)
			if index == 4: sound_buttons[index].disabled = not NotificationSound.has_custom()
	for index in range(sound_buttons.size()):
		sound_buttons[index].pressed.connect(func():
			_set_ui_layout("notify_sound", float(index))
			notify_sound.play_cue()
			mark_sound.call())
	sound_mark = mark_sound
	mark_sound.call()
	sounds.add_child(sound_row)
	sounds.add_child(_label("Drop an MP3 file onto this window to use it as Custom.", 12, Color("bfc4ca")))
	extras.add_child(sounds)
	var hand_box := VBoxContainer.new()
	hand_box.add_child(_label("Hand cards", 14))
	var hand_row := HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 6)
	var toggle_buttons: Dictionary = {}
	for toggle in [{"key": "mana_overlay", "name": "Mana cost overlay", "hint": "Large mana symbols across each hand card: a gray number for generic mana, then one symbol per colored mana."}, {"key": "playable_glow", "name": "Highlight playable", "hint": "Purple glow on cards you can cast or play right now with your available mana, including your commander and graveyard casts."}]:
		var option := _button("", func(): pass)
		option.name = "Toggle_" + toggle.key
		option.tooltip_text = toggle.hint
		P.style_popup_button(option)
		hand_row.add_child(option)
		toggle_buttons[toggle.key] = [option, toggle.name]
	var mark_toggles := func():
		for key in toggle_buttons:
			var on: bool = float(ui_layout[key]) >= 0.5
			toggle_buttons[key][0].text = "%s: %s" % [toggle_buttons[key][1], "On" if on else "Off"]
			toggle_buttons[key][0].modulate = Color.WHITE if on else Color(1, 1, 1, 0.6)
	for key in toggle_buttons:
		toggle_buttons[key][0].pressed.connect(func():
			_set_ui_layout(key, 0.0 if float(ui_layout[key]) >= 0.5 else 1.0)
			mark_toggles.call())
	mark_toggles.call()
	hand_box.add_child(hand_row)
	extras.add_child(hand_box)
	var stack_box := VBoxContainer.new()
	stack_box.add_child(_label("Stack responses", 14))
	var stack_row := HBoxContainer.new()
	stack_row.add_theme_constant_override("separation", 6)
	var stack_buttons: Array = []
	for index in range(STACK_MODES.size()):
		var option := _button(STACK_MODES[index].name, func(): pass)
		option.name = "StackMode" + str(index)
		P.style_popup_button(option)
		stack_row.add_child(option)
		stack_buttons.append(option)
	stack_box.add_child(stack_row)
	var stack_hint := _label("", 12, Color("bfc4ca"))
	stack_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack_hint.custom_minimum_size.x = 760
	stack_box.add_child(stack_hint)
	var mark_stack := func():
		for index in range(stack_buttons.size()):
			stack_buttons[index].modulate = Color.WHITE if index == int(ui_layout.stack_mode) else Color(1, 1, 1, 0.5)
		stack_hint.text = STACK_MODES[int(ui_layout.stack_mode)].hint
	for index in range(stack_buttons.size()):
		stack_buttons[index].pressed.connect(func():
			_set_ui_layout("stack_mode", float(index))
			mark_stack.call())
	mark_stack.call()
	column.add_child(stack_box)
	column.move_child(stack_box, position_in_column)
	position_in_column += 1
	var reset := _button("Reset to default", func():
		for index in range(sliders.size()):
			sliders[index].value = UI_LAYOUT_SETTINGS[index].default
		_set_ui_layout("card_back", 0.0)
		_set_ui_layout("notify_sound", 0.0)
		_set_ui_layout("stack_mode", 1.0)
		_set_ui_layout("mana_overlay", 0.0)
		_set_ui_layout("playable_glow", 1.0)
		mark_toggles.call()
		mark_stack.call()
		mark_sound.call()
		mark_back.call())
	P.style_popup_button(reset)
	column.add_child(reset)
	column.move_child(reset, position_in_column)

func _show_help() -> void:
	if live:
		_information("Forge controls", "Follow Forge's prompt on the right. Click cards, players, and stack entries to select them for the current action. Q presses Forge's primary button (advance phase / resolve). Space passes the rest of the turn using Forge's End Turn: it still stops for your required choices and when you are attacked, targeted or facing a board wipe. D takes a pending draw. Click lands to generate mana before playing a spell.\n\nDuring Declare attackers, click your creature to start an arrow, then click an opponent's avatar. Escape or Cancel target dismisses the arrow. Choose your attackers, then use OK to commit them.\n\nDrag a hand card onto your field to play it. Hold and drag battlefield cards to move them. Click a card in Command, Graveyard, or Exile to select it in Forge. Right-click cards to read their rules.\n\nForge controls costs, tap state, targeting, combat, automatic draws, and undo. Live phase stops follow Forge preferences. Refresh reconnects without restarting the match. Atraxa and Doom decks include complete card images.")
		return
	_information("A table to explore", "This is a visual prototype, using original placeholder cards. Forge is not connected; no Magic legality, costs or rules are simulated.\n\nHover · inspect / right-click · enlarge\nClick your battlefield card: tap / untap; in Declare attackers choose a defender\nHold + drag your card · move / Escape · cancel\nClick a hand card · select / double-click · play\nSpace · advance phase or resolve a demo spell\nT: selected card tap / attack action\nDeclare attackers: click an untapped creature, then an opponent\nD · draw / C · toggle a crowded battlefield\n1–5 · try each fallback decision\nR · reset / Escape · cancel targeting or close a browser\n\nCrowded battlefields wrap and overlap at full card size. The table can be moved vertically with the mouse wheel. Keyboard focus remains inside active decisions.")

## Right-clicking one of your declared attackers calls it back; anything else opens its details.
func _card_right_clicked(data: Dictionary) -> void:
	if live and _attack_step() and snapshot.prompt.get("inputKind", "") == "InputAttack" and snapshot.asks.is_empty() and int(data.get("owner", -1)) == 0 and data.get("zone", "") == "Battlefield" 			and snapshot.get("combat", []).any(func(entry): return int(entry.attacker) == int(data.id)):
		if targeting and selected.get("id", -1) == data.id: _cancel_attack_target()
		_intent("undeclare", {"id": data.id})
		return
	_show_card_detail(data)

func _show_card_detail(data: Dictionary) -> void:
	var column := _information(data.get("name", "Card inspection"), "")
	var body_scroll: ScrollContainer = column.get_node("BodyScroll")
	body_scroll.hide()
	var card_view := Card.new()
	card_view.inspection = true
	card_view.table_angle = false
	var height := clampf(size.y - 250, 350, 660)
	card_view.custom_minimum_size = Vector2(height * 144.0 / 202, height)
	card_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(card_view)
	column.move_child(card_view, 1)
	card_view.update_card(data)

func _show_player(id: int) -> void:
	if snapshot.is_empty():
		return
	var p: Dictionary = snapshot.players[id]
	if live:
		var damage: Array = p.get("commanderDamage", []).map(func(d): return str(d.name) + " / " + str(d.amount))
		_information(p.name + " / " + str(p.life) + " life", "Commander damage taken\n" + ("None" if damage.is_empty() else "\n".join(damage)) + "\nLibrary / " + str(p.libraryCount) + "\nHand / " + str(p.handCount))
		return
	_information(p.name + "  ·  " + str(p.life) + " life", "Commander damage taken\nSeren, Tidekeeper · 4\n\nLibrary · " + str(p.libraryCount) + " cards\nHand · " + str(p.handCount) + " cards\n\nMock player information. Opponent hands remain hidden.")

func _show_zone(id: int, zone: String) -> void:
	if snapshot.is_empty() or _modal_covers_table() or is_instance_valid(dragged_source):
		return
	if zone_owner == id and zone_name == zone:
		_close_zone_browser()
		return
	_close_zone_browser()
	zone_owner = id
	zone_name = zone
	if zone_panel == null:
		zone_panel = PanelContainer.new()
		zone_panel.z_index = 35
		P.style_popup(zone_panel, 12)
		add_child(zone_panel)
		var column := VBoxContainer.new()
		zone_panel.add_child(column)
		var header := HBoxContainer.new()
		column.add_child(header)
		zone_title = Label.new()
		zone_title.add_theme_font_override("font", P.display_font())
		zone_title.add_theme_font_size_override("font_size", 18)
		zone_title.clip_text = true
		zone_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(zone_title)
		var close := _button("×", _close_zone_browser, "Close zone")
		header.add_child(close)
		zone_scroll = ScrollContainer.new()
		zone_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		column.add_child(zone_scroll)
		zone_content = Control.new()
		zone_scroll.add_child(zone_content)
		zone_empty = _label("NO CARDS", 14, P.MUTED)
		zone_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		zone_content.add_child(zone_empty)
	zone_title.text = "Command Zone" if zone == "Command" else zone
	zone_scroll.scroll_horizontal = 0
	_refresh_zone_browser()
	zone_expansion = 0.0
	if zone_animation != null: zone_animation.kill()
	zone_animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	zone_animation.tween_property(self, "zone_expansion", 1.0, 0.18)
	_layout_zone_browser()

func _close_zone_browser() -> void:
	if zone_animation != null: zone_animation.kill()
	pending_command_cast = -1
	zone_owner = -1
	zone_name = ""
	for view in zone_views.values():
		view.queue_free()
	zone_views.clear()
	if zone_panel != null:
		zone_panel.hide()

func _close_accepted_commander_browser() -> void:
	if zone_name != "Command" or zone_owner != 0 or pending_command_cast < 0: return
	var still_in_command: bool = snapshot.players[0].zones.Command.any(func(card): return int(card.id) == pending_command_cast)
	var kind: String = snapshot.get("prompt", {}).get("inputKind", "")
	var cast_decision: bool = int(snapshot.get("pendingCastId", -1)) == pending_command_cast and (kind.begins_with("InputPayMana") or kind.begins_with("InputSelect") or not snapshot.get("asks", []).is_empty())
	if not still_in_command or cast_decision:
		_close_zone_browser()

func _refresh_zone_browser() -> void:
	if zone_owner < 0 or snapshot.is_empty():
		return
	var wanted: Dictionary = {}
	var index := 0
	for source in snapshot.players[zone_owner].zones[zone_name]:
		if cards.has(source.id):
			continue # A cast preview already owns this instance until Forge responds.
		wanted[source.id] = true
		var view: Control = zone_views.get(source.id)
		if view == null:
			view = Card.new()
			view.zone_browser = true
			view.table_angle = false
			zone_content.add_child(view)
			zone_views[source.id] = view
			view.hovered.connect(_card_hovered.bind(view))
			view.unhovered.connect(_card_unhovered.bind(view))
			view.inspect_requested.connect(_card_right_clicked)
			view.picked.connect(_pick)
			view.drag_started.connect(_start_card_drag)
			view.drag_moved.connect(_move_card_drag)
			view.drag_finished.connect(_finish_card_drag)
		var data: Dictionary = source.duplicate(true)
		data.owner = zone_owner
		data.zone = zone_name
		data.playable = _playable(data, zone_owner, zone_name)
		data.ready = data.playable and _ready_now(data, zone_name)
		if zone_name == "Command" and data.get("commander", false):
			view.tooltip_text = "Commander tax: +{%d} generic mana in addition to the printed cost when cast from the command zone. Previous command-zone casts: %d." % [int(data.get("commanderTax", 0)), int(data.get("commanderCasts", 0))]
		view.update_card(data)
		if view != dragged_source:
			view.settle(Vector2(index * (zone_card_size.x + 12), 0), zone_card_size, false, true)
		index += 1
	for id in zone_views.keys():
		if not wanted.has(id) and zone_views[id] != dragged_source:
			zone_views[id].queue_free()
			zone_views.erase(id)
	zone_content.custom_minimum_size = Vector2(maxi(1, index) * (TABLE_CARD_SIZE.x + 12) - 12, TABLE_CARD_SIZE.y)
	_layout_zone_browser()

func _layout_zone_browser() -> void:
	if zone_panel == null or zone_owner < 0:
		return
	zone_panel.visible = not _modal_covers_table() and not opening_hand.visible
	var field: Rect2 = player_areas[zone_owner].get_global_rect().intersection(board_scroller.get_global_rect())
	if field.size.x < 48 or field.size.y < 80:
		zone_panel.hide()
		return
	var icon: Rect2 = hud_values[zone_owner].zones[zone_name].get_global_rect()
	var factor := clampf((field.end.y - icon.end.y - 8 - 84) / TABLE_CARD_SIZE.y, 0.55, 1.0)
	zone_card_size = (TABLE_CARD_SIZE * factor).floor()
	var index := 0
	for view in zone_views.values():
		if view != dragged_source: view.settle(Vector2(index * (zone_card_size.x + 12), 0), zone_card_size, false, true)
		index += 1
	zone_content.custom_minimum_size = Vector2(maxi(1, index) * (zone_card_size.x + 12) - 12, zone_card_size.y)
	zone_empty.visible = index == 0
	if index == 0: zone_content.custom_minimum_size = Vector2(148, 28)
	var width := minf(minf(424, field.size.x - 40), zone_content.custom_minimum_size.x)
	zone_scroll.custom_minimum_size = Vector2(width, zone_content.custom_minimum_size.y + 16)
	zone_panel.size = zone_panel.get_combined_minimum_size()
	zone_panel.position = Vector2(clampf(icon.end.x - zone_panel.size.x, field.position.x + 8, maxf(field.position.x + 8, field.end.x - zone_panel.size.x - 8)), clampf(icon.end.y + 8, field.position.y + 8, maxf(field.position.y + 8, field.end.y - zone_panel.size.y - 8)))
	zone_panel.pivot_offset = icon.get_center() - zone_panel.position
	zone_panel.scale = Vector2.ONE * lerpf(0.12, 1.0, zone_expansion)
	zone_panel.modulate.a = zone_expansion

func _adjust_card_zoom(step: float) -> void:
	var zoom := clampf(snappedf(card_zoom + step, 0.05), MIN_CARD_ZOOM, MAX_CARD_ZOOM)
	if is_equal_approx(zoom, card_zoom): return
	card_zoom = zoom
	HAND_CARD_SIZE = BASE_CARD_SIZE * card_zoom
	TABLE_CARD_SIZE = HAND_CARD_SIZE
	zone_card_size = TABLE_CARD_SIZE
	if snapshot.is_empty(): return
	_layout_board()
	_layout_hand()

func _unhandled_key_input(event: InputEvent) -> void:
	if layout_paused:
		get_viewport().set_input_as_handled()
		return
	if transition_preview or transition_reveal: return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if is_instance_valid(dragged_source):
		return
	if is_instance_valid(outcome_screen):
		outcome_screen.handle_key(event)
		get_viewport().set_input_as_handled()
		return
	if modal.visible:
		if event.keycode == KEY_ESCAPE and decision_board_button.visible:
			_set_decision_board(false)
		elif event.keycode == KEY_ESCAPE:
			if open_ask >= 0 and modal_panel != null:
				modal_panel.cancel_input()
			elif open_ask == -1:
				_dismiss_modal()
		get_viewport().set_input_as_handled()
		return
	if opening_hand.visible:
		if event.keycode == KEY_ESCAPE:
			opening_hand._toggle_board()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE and zone_owner >= 0:
		_close_zone_browser()
		get_viewport().set_input_as_handled()
		return
	if event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
		_adjust_card_zoom(0.1 if event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD] else -0.1)
		get_viewport().set_input_as_handled()
		return
	if live:
		match event.keycode:
			KEY_SPACE: _pass_turn()
			KEY_Q: _primary_action()
			KEY_D: _intent("draw")
			KEY_T: _tap(true)
			KEY_H: _show_help()
			KEY_R: _intent("refresh")
			KEY_ESCAPE: _secondary_action()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_SPACE, KEY_Q: _primary_action()
		KEY_T: _tap(true)
		KEY_D: _intent("draw")
		KEY_C: _intent("crowd")
		KEY_R: _reset()
		KEY_H: _show_help()
		KEY_ESCAPE:
			targeting = false
			selected = {}
			_layout_board()
			_update_actions()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			_intent("prompt", {"kind": ["choose", "order", "distribute", "input", "message"][event.keycode - KEY_1]})
	_update_lines()
	get_viewport().set_input_as_handled()

func _pass_turn() -> void:
	# Pass turn only applies while Forge is waiting on this seat's priority.
	if snapshot.is_empty() or not snapshot.get("asks", []).is_empty() or not snapshot.get("pendingDraws", []).is_empty() or snapshot.get("prompt", {}).get("inputKind", "") != "InputPassPriority":
		return
	_intent("pass_turn")
	toast.text = "Passing until end of turn. Your required choices, attacks, targets and board wipes still stop you."
	toast.modulate.a = 1
	if toast_tween != null: toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.4)
	toast_tween.tween_property(toast, "modulate:a", 0.0, 0.3)

func _capture(path: String) -> void:
	await get_tree().process_frame
	if live:
		# A live table (the sandbox's --shot) shows nothing until Forge's first snapshot arrives;
		# then give the layout and cached artwork a moment to settle.
		var deadline := Time.get_ticks_msec() + 60000
		while (snapshot.is_empty() or sandbox_starting) and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		await get_tree().create_timer(2.5).timeout
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Screenshot failed: " + str(error))
		get_tree().quit(1)
	else:
		print("Screenshot saved: " + path)
		get_tree().quit()

func _layout_loop_check() -> void:
	var layout_checks := preload("res://tests/LayoutLoopChecks.gd").new()
	await layout_checks.run(self)
	if layout_checks.failed:
		get_tree().quit(1)
		return
	get_tree().quit()

func _hand_hover_check() -> void:
	await preload("res://tests/HandHoverRenderChecks.gd").new().run(self)

func _smoke() -> void:
	# The headless display has no native window rectangle; give the UI a logical viewport.
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(1600, 1000)
	await get_tree().create_timer(0.2).timeout
	if not _only_checks().is_empty():
		await _run_only_checks("")
		return
	var layout_checks := preload("res://tests/LayoutLoopChecks.gd").new()
	await layout_checks.run(self)
	if layout_checks.failed:
		get_tree().quit(1)
		return
	await preload("res://tests/HandPickingChecks.gd").new().run(self)
	await preload("res://tests/ZoneBrowserChecks.gd").new().run(self)
	await preload("res://tests/GameplayCleanupChecks.gd").new().run(self)
	await preload("res://tests/CardImageChecks.gd").new().run(self)
	await preload("res://tests/LibraryImageChecks.gd").new().run(self)
	await preload("res://tests/StartupProgressChecks.gd").new().run(self)
	await preload("res://tests/FormatLogChecks.gd").new().run(self)
	await preload("res://tests/IncomingEffectChecks.gd").new().run(self)
	await preload("res://tests/HandOverlayChecks.gd").new().run(self)
	await preload("res://tests/OutcomeScreenChecks.gd").new().run(self)
	await preload("res://tests/ReadyScreenChecks.gd").new().run(self)
	await preload("res://tests/CardFeedbackChecks.gd").new().run(self)
	await preload("res://tests/StackFeedChecks.gd").new().run(self)
	await preload("res://tests/PreviewChecks.gd").new().run(self)
	await preload("res://tests/TraitIconChecks.gd").new().run(self)
	await preload("res://tests/TapAnimationChecks.gd").new().run(self)
	await preload("res://tests/SelectionChecks.gd").new().run(self)
	await preload("res://tests/InteractionFlowChecks.gd").new().run(self)
	await preload("res://tests/RequiredModalChecks.gd").new().run(self)
	await preload("res://tests/DecisionReviewChecks.gd").new().run(self)
	await preload("res://tests/ManaPaymentChecks.gd").new().run(self)
	await preload("res://tests/StartingPlayerChecks.gd").new().run(self)
	await preload("res://tests/BattlefieldLayoutChecks.gd").new().run(self)
	preload("res://tests/AutoPriorityChecks.gd").new().run()
	await preload("res://tests/PendingCastChecks.gd").new().run(self)
	await preload("res://tests/PendingDrawChecks.gd").new().run(self)
	await preload("res://tests/StackAttentionChecks.gd").new().run(self)
	await preload("res://tests/OpeningHandChecks.gd").new().run(self)
	for seat in [0, 1, 2]:
		var before_color: Color = phase_labels[seat]["Main 2"].get_theme_stylebox("normal").bg_color
		await _click_phase_button(seat, "Main 2")
		assert(not phase_labels[seat]["Main 2"].button_pressed and phase_labels[seat]["Main 2"].get_theme_stylebox("normal").bg_color != before_color, "Actual phase-button clicks must visibly toggle row %s: button=%s viewport=%s hovered=%s" % [seat, phase_labels[seat]["Main 2"].get_global_rect(), get_viewport_rect(), get_viewport().gui_get_hovered_control()])
		await _click_phase_button(seat, "Main 2")
		assert(phase_labels[seat]["Main 2"].button_pressed, "Phase stop must re-enable on the next click")
	var phase_button: Button = phase_labels[0]["Begin combat"]
	phase_labels[1]["Begin combat"].button_pressed = true
	phase_button.button_pressed = false
	assert(not phase_stops[0]["Begin combat"] and phase_labels[1]["Begin combat"].button_pressed, "Phase stops must toggle per player")
	_primary_action()
	assert(snapshot.game.phase == "Declare attackers", "Disabled stops must auto-pass to the next enabled step")
	phase_button.button_pressed = true
	for step in TURN_STEPS:
		phase_labels[0][step].button_pressed = false
	var turn_before: int = snapshot.game.turn
	_intent("advance")
	assert(snapshot.game.turn == turn_before + 1, "All stops off must advance a turn without an infinite loop")
	for step in TURN_STEPS:
		phase_labels[0][step].button_pressed = true
	var left_before: float = player_areas[1].size.x
	_resize_fields(board.global_position + Vector2(board.size.x * 0.65, 100), false)
	assert(player_areas[1].size.x > left_before and player_areas[2].size.x < left_before, "Opponent divider must redistribute field widths")
	_resize_fields(board.global_position + Vector2(100, 500), true)
	await get_tree().process_frame
	assert(player_areas[0].position.y >= 500, "Horizontal divider must resize player fields")
	_resize_fields(Vector2.INF, false)
	_resize_fields(Vector2.INF, true)
	await get_tree().create_timer(0.2).timeout
	_reset()
	assert(snapshot.players.size() == 3)
	assert(cards.size() == 18)
	for view in cards.values():
		if view.data.get("owner", 0) == 0:
			assert(view.size.is_equal_approx(HAND_CARD_SIZE if view.hand_mode else TABLE_CARD_SIZE), "Local hand and battlefield cards retain their base size")
		else:
			assert(view.size.x <= TABLE_CARD_SIZE.x and view.size.x >= TABLE_CARD_SIZE.x * 0.5, "Opponent cards adapt within readable size limits")
		assert(is_zero_approx(float(view.visual.material.get_shader_parameter("tilt"))), "Card faces must remain flat")
	var before: int = snapshot.players[0].handCount
	_pick(cards[11].data, false)
	_intent("draw")
	assert(snapshot.players[0].handCount == before + 1)
	assert(selected.zone == "Hand" and selected.owner == 0, "Selection context lost during snapshot reconciliation")
	_primary_action()
	assert(snapshot.stack.size() == 1)
	_intent("advance")
	assert(snapshot.players[0].zones.Battlefield.any(func(c): return c.id == 11))
	_click_card(1)
	assert(cards[1].data.tapped, "A single battlefield click must tap")
	_click_card(1)
	assert(not cards[1].data.tapped, "A second click must untap")
	_click_card(1)
	_click_card(1, true)
	assert(not cards[1].data.tapped, "Rapid clicks must toggle the card once per physical click")
	_click_card(3)
	assert(cards[3].data.tapped, "Land must tap by clicking too")
	_click_card(3)
	assert(not cards[3].data.tapped)
	var opponent_tapped: bool = cards[40].data.tapped
	_click_card(40)
	assert(cards[40].data.tapped == opponent_tapped, "Clicking an opponent's card must not tap it")
	_click_card(1)
	assert(cards[1].data.tapped)
	var tapped_before_drag: bool = cards[1].data.tapped
	_drag_card(1, Vector2(130, -35))
	assert(cards[1].data.tapped == tapped_before_drag, "Dragging must not toggle tap state")
	assert(manual_positions.has(1) and cards[1].get_parent() == free_cards, "Dropped card must remain movable outside its row")
	var placed: Vector2 = cards[1].resting_position
	_intent("draw")
	assert(cards[1].resting_position.is_equal_approx(placed), "State updates must preserve manual card positions: before=%s after=%s board=%s saved=%s" % [placed, cards[1].resting_position, board.size, manual_positions[1]])
	_click_card(1)
	var untapped_position: Vector2 = cards[1].resting_position
	assert(not cards[1].data.tapped and manual_positions.has(1) and is_equal_approx(untapped_position.x, placed.x) and untapped_position.y >= placed.y and untapped_position.y - placed.y <= (TABLE_CARD_SIZE.y - TABLE_CARD_SIZE.x) * 0.5 + 0.1, "Untapping a moved card may shift inward only enough to keep its taller footprint in its field")
	_drag_card(3, Vector2(75, 15), true)
	assert(not manual_positions.has(3) and not cards[3].data.tapped, "Escape must cancel dragging without tapping")
	var hand_before_drag: int = snapshot.players[0].handCount
	var hand_center: Vector2 = cards[14].get_global_transform() * (cards[14].size * 0.5)
	_drag_card(14, board_scroller.global_position + Vector2(100, 100) - hand_center)
	assert(snapshot.players[0].handCount == hand_before_drag and cards[14].data.zone == "Hand", "Dropping onto an opponent's field must not play a hand card")
	_select_card(cards[1].data)
	_begin_targeting()
	assert(not targeting, "Main phase must not allow attacking")
	_intent("attack", {"id": 1, "target": 1})
	assert(snapshot.players[1].life == 40, "Mock adapter must reject attacks outside Declare attackers")
	while snapshot.game.phase != "Declare attackers":
		_intent("advance")
	_click_card(1)
	assert(targeting and not cards[1].data.tapped, "Clicking an attacker must require a defender before tapping")
	var phase_before: String = snapshot.game.phase
	_primary_action()
	assert(snapshot.game.phase == phase_before, "Cannot pass while choosing a defender")
	_choose_player(0)
	assert(targeting, "Cannot attack yourself")
	_choose_player(1)
	assert(not targeting and cards[1].data.tapped, "Choosing a defender commits the attacker")
	assert(snapshot.players[1].life == 37)
	_click_card(1)
	assert(not targeting and cards[1].data.tapped, "An already tapped attacker cannot attack again")
	_intent("attack", {"id": 1, "target": 2})
	assert(snapshot.players[2].life == 34, "Mock adapter must reject a tapped attacker")
	_click_card(2)
	assert(targeting, "Another untapped creature must be able to choose its defender")
	_choose_player(2)
	assert(snapshot.combat.size() == 2 and snapshot.players[2].life == 31, "Keep each attacker's selected defender")
	_intent("crowd")
	assert(snapshot.players[0].zones.Battlefield.size() == 20)
	for kind in ["choose", "order", "distribute", "input", "message"]:
		_intent("prompt", {"kind": kind})
		assert(modal.visible and open_ask >= 0)
		var panel: Control = modal_panel
		match kind:
			"choose":
				assert(panel.confirm_button.disabled)
				panel._toggle(0)
				assert(not panel.confirm_button.disabled)
			"order":
				panel._toggle(1)
				panel._toggle(0)
				assert(panel.confirm_button.disabled)
				panel._toggle(2)
				assert(not panel.confirm_button.disabled)
			"distribute":
				assert(panel.confirm_button.disabled)
				panel.amounts.assign([1, 2, 2])
				panel._validate()
				assert(not panel.confirm_button.disabled)
			"input":
				panel.input.text = "Original mock card"
				panel._validate()
		panel._submit()
		assert(not modal.visible)
	_reset()
	assert(snapshot.players[0].zones.Battlefield.size() == 5)
	await _verify_return_permissions()
	await _verify_return_continuity()
	_reset()
	_verify_library_draw()
	_reset()
	await _verify_hand_insertion()
	_reset()
	await _verify_drag_play()
	_reset()
	await load("res://tests/LiveAdapterChecks.gd").new().run()
	print("PASS: mock table smoke (state, play, stack, tap, attack, crowd, five prompt kinds, reset)")
	get_tree().quit()

## --only=Name[,Name] (with --smoke or --visual-checks=DIR) runs just tests/<Name>Checks.gd and quits.
## Use it while iterating; the full sweep runs once before a push. See docs/testing.md.
func _only_checks() -> PackedStringArray:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): return arg.trim_prefix("--only=").split(",", false)
	return PackedStringArray()

func _run_only_checks(directory: String) -> void:
	for check_name in _only_checks():
		var path := "res://tests/%sChecks.gd" % check_name.strip_edges()
		if not ResourceLoader.exists(path):
			push_error("Unknown check %s (expected %s)" % [check_name, path])
			get_tree().quit(1)
			return
		var check: Object = load(path).new()
		var parameters: Array = []
		for method in check.get_method_list():
			if method.name == "run": parameters = method.args
		var args: Array = []
		if not parameters.is_empty(): args.append(self)
		if parameters.size() > 1 and not directory.is_empty():
			# The full visual run passes captures as a directory or a bool; match the signature.
			args.append(true if int(parameters[1].type) == TYPE_BOOL else directory)
			synthetic_hover = not check_name in ["HandPicking", "ZoneBrowser", "GameplayCleanup"]
		await check.callv("run", args)
		_reset()
		await get_tree().process_frame
	print("ONLY CHECKS DONE: ", ", ".join(_only_checks()))
	get_tree().quit()

func _click_phase_button(seat: int, step: String) -> void:
	if get_viewport_rect().size.x < 100:
		# The headless display exposes a 64px window. Rendered runs check real hit testing.
		phase_labels[seat][step].button_pressed = not phase_labels[seat][step].button_pressed
		await get_tree().process_frame
		return
	var point: Vector2 = phase_labels[seat][step].get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	click.global_position = point
	click.pressed = true
	get_viewport().push_input(click)
	click = click.duplicate()
	click.pressed = false
	get_viewport().push_input(click)
	await get_tree().process_frame

func _verify_return_continuity() -> void:
	for fraction in [0.01, 0.5, 0.99]:
		_reset()
		for _card in range(12):
			_intent("draw")
		_select_card(cards[14].data)
		_primary_action()
		if fraction > 0.9:
			_scroll_hand(100)
		await get_tree().create_timer(0.2).timeout
		var center: Vector2 = cards[14].get_global_transform() * (cards[14].size * 0.5)
		var target := hand_root.global_position + Vector2(hand_root.size.x * fraction, 100)
		_drag_card(14, target - center)
		var settle_animation: Tween = cards[14].animation
		adapter._publish()
		assert(cards[14].animation == settle_animation, "Repeated snapshots must not restart a return's settle")
		await get_tree().create_timer(0.2).timeout
		assert(cards[14].position.is_equal_approx(cards[14].resting_position), "Returned card must finish in its selected slot")

func _verify_return_permissions() -> void:
	_intent("return_to_hand", {"id": 1})
	assert(cards[1].data.zone == "Battlefield", "Starting permanents must not be freely bounced")
	_select_card(cards[14].data)
	_primary_action()
	assert(return_button.visible and cards[14].data.availableActions.returnToHand, "A new unused mock land may return")
	_return_selected()
	assert(cards[14].data.zone == "Hand" and snapshot.players[0].handCount == 5, "Returning must restore the same card to hand")
	_primary_action()
	await get_tree().create_timer(0.2).timeout
	var original_center: Vector2 = cards[14].get_global_transform() * (cards[14].size * 0.5)
	var hand_target := Vector2(hand_root.global_position.x + hand_root.size.x * 0.5, size.y - 30)
	_drag_card(14, hand_target - original_center)
	assert(cards[14].data.zone == "Hand", "Dropping an eligible unused permanent onto the hand must request its return")
	_primary_action()
	_click_card(14)
	_click_card(14)
	assert(not cards[14].data.tapped and not cards[14].data.availableActions.returnToHand, "Using then untapping a card must not restore return permission")
	_intent("return_to_hand", {"id": 14})
	assert(cards[14].data.zone == "Battlefield", "Adapter must reject unauthorized returns")
	_reset()
	_select_card(cards[11].data)
	_primary_action()
	assert(selected.zone == "Stack" and return_button.visible, "A pending mock play can be withdrawn before use")
	_return_selected()
	assert(snapshot.stack.is_empty() and cards[11].data.zone == "Hand", "Return must remove the pending stack entry")
	_primary_action()
	_primary_action()
	assert(cards[11].data.availableActions.returnToHand, "A resolved mock creature with no effects remains unused")
	_return_selected()
	assert(cards[11].data.zone == "Hand")
	_primary_action()
	_primary_action()
	_intent("draw")
	_intent("return_to_hand", {"id": 11})
	assert(cards[11].data.zone == "Battlefield" and not cards[11].data.availableActions.returnToHand, "New information must close the return window")
	_reset()
	_select_card(cards[13].data)
	_primary_action()
	_primary_action()
	_intent("return_to_hand", {"id": 13})
	assert(snapshot.players[0].zones.Graveyard.any(func(c): return c.id == 13), "Resolved effects cannot be undone by returning a card")
	_reset()
	for _i in range(12):
		_intent("draw")
	_scroll_hand(100)
	assert(hand_offset > 0 and cards[snapshot.players[0].zones.Hand.back().id].visible, "Carousel must expose every card in a large hand")
	for value in snapshot.players[0].zones.Hand:
		assert(cards[value.id].size.is_equal_approx(HAND_CARD_SIZE), "Paging must keep enlarged hand cards")

func _drag_library(target: Vector2, cancel: bool = false) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = library_pile.get_global_rect().intersection(Rect2(Vector2.ZERO, size)).get_center()
	library_pile._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.global_position = press.global_position + Vector2(15, 0)
	library_pile._input(motion)
	assert(library_ghost.visible, "Library drag must show a face-down preview")
	motion.global_position = target
	library_pile._input(motion)
	if hand_root.get_global_rect().has_point(target):
		assert(hand_gap_index >= 0, "Dragging a library card over the hand must open an insertion gap")
	if cancel:
		library_pile.cancel_drag()
	else:
		press.pressed = false
		press.global_position = target
		library_pile._input(press)
	assert(not library_pile.pressed, "Library drag input must always end")
	if library_draw_pending:
		assert(library_ghost.visible and hand_gap_index >= 0, "The pending draw must keep its held card and gap")
	else:
		assert(not library_ghost.visible and hand_gap_index == -1, "Completed/canceled draws must close the preview")

func _verify_library_draw() -> void:
	var count: int = snapshot.players[0].handCount
	var remaining: int = snapshot.players[0].libraryCount
	var target := Vector2(hand_root.global_position.x + hand_root.size.x * 0.5, size.y - 40)
	_drag_library(target, true)
	assert(snapshot.players[0].handCount == count, "Canceled library drags must not draw")
	_drag_library(board_scroller.global_position + Vector2(100, 100))
	assert(snapshot.players[0].handCount == count, "Dropping outside hand must not draw")
	_drag_library(target)
	assert(snapshot.players[0].handCount == count + 1 and snapshot.players[0].libraryCount == remaining - 1, "Dropping from the library into hand must draw exactly one card")
	adapter.state.players[0].libraryCount = 0
	adapter._publish()
	_intent("draw")
	assert(not library_pile.enabled and snapshot.players[0].handCount == count + 1, "An empty library must reject drawing")

func _verify_drag_play() -> void:
	await get_tree().create_timer(0.2).timeout
	var target: Vector2 = player_areas[0].get_global_rect().position + Vector2(220, 160)
	var center: Vector2 = cards[14].get_global_transform() * (cards[14].size * 0.5)
	_drag_card(14, target - center, true)
	assert(cards[14].data.zone == "Hand", "Canceling drag-to-play must leave the card in hand")
	center = cards[14].get_global_transform() * (cards[14].size * 0.5)
	_drag_card(14, target - center)
	assert(cards[14].data.zone == "Battlefield", "A land dropped on the local field must request play")
	assert((cards[14].get_global_transform() * (cards[14].size * 0.5)).distance_to(target) < 1, "A dropped land must stay at its release position")
	await get_tree().create_timer(0.2).timeout
	assert(cards[14].data.stackCount == 1 and (cards[14].get_global_transform() * (cards[14].size * 0.5)).distance_to(target) < 1, "A matching played land must remain where dropped until cleanup is explicitly requested")
	center = cards[11].get_global_transform() * (cards[11].size * 0.5)
	var spell_target := target + Vector2(180, 0)
	_drag_card(11, spell_target - center)
	assert(snapshot.stack.any(func(item): return item.sourceId == 11), "A dropped spell must use the adapter's stack path")
	assert(cards.has(11) and (cards[11].get_global_transform() * (cards[11].size * 0.5)).distance_to(spell_target) < 1, "A pending spell must stay where dropped")
	_intent("advance")
	assert(cards[11].data.zone == "Battlefield" and (cards[11].get_global_transform() * (cards[11].size * 0.5)).distance_to(spell_target) < 1, "Resolving a dropped permanent must preserve its placement")
	for id in player_areas:
		var style: StyleBoxFlat = player_areas[id].get_theme_stylebox("panel")
		assert(style.border_color == (Color.WHITE if snapshot.game.activePlayer == id else Color("64676d")), "Only the active player's field may have a white border")

func _verify_hand_insertion() -> void:
	for fraction in [0.01, 0.5, 0.99]:
		_reset()
		var target := Vector2(hand_root.global_position.x + hand_root.size.x * fraction, size.y - 40)
		var slot := _hand_insertion_index(target)
		var expected := hand_order.duplicate()
		_drag_library(target)
		var drawn_id: int = snapshot.players[0].zones.Hand.back().id
		var drawn_center: Vector2 = cards[drawn_id].global_position + HAND_CARD_SIZE * 0.5
		assert(drawn_center.is_equal_approx(target), "The revealed draw must start at the drop position, without flying in from outside the hand")
		expected.insert(slot, drawn_id)
		assert(hand_order == expected, "A drawn card must enter at the chosen hand position")
	_reset()
	await get_tree().create_timer(0.2).timeout
	var engine_order: Array = snapshot.players[0].zones.Hand.map(func(value): return value.id)
	var first_target := Vector2(hand_root.global_position.x + 1, size.y - 40)
	var center: Vector2 = cards[14].get_global_transform() * (cards[14].size * 0.5)
	_drag_card(14, first_target - center)
	assert(hand_order.front() == 14 and hand_order.size() == engine_order.size(), "A hand card must reorder without changing the hand count")
	adapter._publish()
	assert(hand_order.front() == 14, "Presentation order must survive snapshots")
	assert(snapshot.players[0].zones.Hand.map(func(value): return value.id) == engine_order, "Sorting the hand must not alter engine zone order")
	await get_tree().create_timer(0.2).timeout
	var before := hand_order.duplicate()
	center = cards[14].get_global_transform() * (cards[14].size * 0.5)
	var end_target := Vector2(hand_root.get_global_rect().end.x - 1, size.y - 40)
	_drag_card(14, end_target - center, true)
	assert(hand_order == before, "Canceling a hand drag must preserve its order")
	await get_tree().create_timer(0.2).timeout
	center = cards[14].get_global_transform() * (cards[14].size * 0.5)
	_drag_card(14, end_target - center)
	assert(hand_order.back() == 14, "A hand card must also move to the end of the fan")
	for _i in range(12):
		_intent("draw")
	_scroll_hand(100)
	await get_tree().create_timer(0.2).timeout
	var offset_before := hand_offset
	var last_id: int = hand_order.back()
	center = cards[last_id].get_global_transform() * (cards[last_id].size * 0.5)
	_drag_card(last_id, Vector2(0, -10), true)
	assert(hand_offset == offset_before, "Dragging on the last carousel page must not shift the page")

func _click_card(id: int, double_click: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double_click
	event.global_position = cards[id].get_global_transform() * (cards[id].size * 0.5)
	cards[id]._gui_input(event)
	event.pressed = false
	cards[id]._input(event)

func _drag_card(id: int, delta: Vector2, cancel: bool = false) -> void:
	var view: Control = cards[id]
	var was_battlefield: bool = view.data.zone == "Battlefield"
	var before_position: Vector2 = view.get_global_transform() * (view.size * 0.5)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.global_position = before_position
	view._gui_input(press)
	view._process(0.2)
	assert(view.drag_active and dragged_source == view, "Holding a card must begin moving without tapping")
	var motion := InputEventMouseMotion.new()
	motion.global_position = before_position + delta
	view._input(motion)
	if view.hand_mode and hand_root.get_global_rect().has_point(motion.global_position):
		assert(hand_gap_index >= 0 and not _hand_layout_values().any(func(value): return value.id == id), "A held hand card must vacate its slot and open an insertion gap")
	if cancel:
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		view._input(escape)
	else:
		press.pressed = false
		press.global_position = motion.global_position
		var returning: bool = was_battlefield and view.data.get("availableActions", {}).get("returnToHand", false) and _hand_drop_area().has_point(motion.global_position)
		var gap_targets: Dictionary = {}
		if returning:
			for value in _hand_layout_values():
				var neighbor: Control = cards[value.id]
				if neighbor.visible:
					gap_targets[value.id] = [neighbor.resting_position, neighbor.base_rotation]
		var release_pose: Transform2D = view.get_global_transform()
		var release_center: Vector2 = view.get_global_transform() * (view.size * 0.5)
		var release_size: Vector2 = view.size
		view._input(press)
		var after_position: Vector2 = view.get_global_transform() * (view.size * 0.5)
		if returning:
			assert(view.get_global_transform().is_equal_approx(release_pose), "Releasing a return must preserve the held pose before its smooth settle")
			for neighbor_id in gap_targets:
				var neighbor: Control = cards[neighbor_id]
				assert(neighbor.visible and neighbor.resting_position.is_equal_approx(gap_targets[neighbor_id][0]) and is_equal_approx(neighbor.base_rotation, gap_targets[neighbor_id][1]), "The insertion gap and final hand must use identical spacing")
		if view.data.zone == "Battlefield" and not hand_root.get_global_rect().has_point(motion.global_position):
			assert(after_position.distance_to(release_center) < 1, "A board drop must preserve its held center immediately at release")
			assert(view.size.is_equal_approx(release_size), "A board drop must not resize the held card at release")
		if was_battlefield and view.data.zone == "Battlefield":
			assert(after_position.distance_to(before_position) > 8, "Dragging must visibly move the card")
	assert(not view.press_pending and not view.drag_active and dragged_source == null, "Drop must end the gesture")

func _save_frame(path: String) -> void:
	# Native Windows resize events can arrive after a frame has been queued.
	# Wait for a stable requested size before validating or writing the image.
	for _attempt in range(4):
		if get_window().size != capture_size:
			get_window().size = capture_size
		await get_tree().create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		if get_window().size == capture_size and Vector2i(get_viewport_rect().size) == capture_size:
			break
	assert(Vector2i(get_viewport_rect().size) == capture_size, "Capture size changed: expected %s actual %s window %s min %s" % [capture_size, get_viewport_rect().size, get_window().size, get_window().min_size])
	var error := get_viewport().get_texture().get_image().save_png(path)
	assert(error == OK, "Screenshot failed")
	print("Screenshot saved: " + path)

func _visual_checks(directory: String) -> void:
	if not _only_checks().is_empty():
		await _run_only_checks(directory)
		return
	await preload("res://tests/HandPickingChecks.gd").new().run(self, true)
	await preload("res://tests/ZoneBrowserChecks.gd").new().run(self, directory)
	await preload("res://tests/GameplayCleanupChecks.gd").new().run(self)
	synthetic_hover = true
	await preload("res://tests/BattlefieldLayoutChecks.gd").new().run(self, directory)
	await preload("res://tests/SelectionChecks.gd").new().run(self, directory)
	await preload("res://tests/InteractionFlowChecks.gd").new().run(self, directory)
	await preload("res://tests/RequiredModalChecks.gd").new().run(self)
	await preload("res://tests/DecisionReviewChecks.gd").new().run(self, directory)
	await preload("res://tests/ManaPaymentChecks.gd").new().run(self)
	await preload("res://tests/StartingPlayerChecks.gd").new().run(self, directory)
	await preload("res://tests/TapAnimationChecks.gd").new().run(self, true)
	await preload("res://tests/IncomingEffectChecks.gd").new().run(self, directory)
	await preload("res://tests/OutcomeScreenChecks.gd").new().run(self, directory)
	await preload("res://tests/ReadyScreenChecks.gd").new().run(self, directory)
	await preload("res://tests/CardFeedbackChecks.gd").new().run(self, directory)
	await preload("res://tests/StackFeedChecks.gd").new().run(self, directory)
	await preload("res://tests/PendingDrawChecks.gd").new().run(self, directory)
	await preload("res://tests/PreviewChecks.gd").new().run(self, directory)
	await preload("res://tests/TraitIconChecks.gd").new().run(self, directory)
	await preload("res://tests/StackAttentionChecks.gd").new().run(self, directory)
	await preload("res://tests/OpeningHandChecks.gd").new().run(self, directory)
	for view in cards.values():
		if view.hover_active:
			view._on_exit()
	await get_tree().process_frame
	await _save_frame(directory.path_join("table-1600.png"))
	phase_labels[0]["Begin combat"].button_pressed = false
	await _save_frame(directory.path_join("phase-stops-1600.png"))
	phase_labels[0]["Begin combat"].button_pressed = true
	_resize_fields(board.global_position + Vector2(board.size.x * 0.62, 100), false)
	_resize_fields(board.global_position + Vector2(100, 470), true)
	await _save_frame(directory.path_join("resized-fields-1600.png"))
	_resize_fields(Vector2.INF, false)
	_resize_fields(Vector2.INF, true)
	await get_tree().create_timer(0.2).timeout
	await _capture_hover(10, directory.path_join("hover-hand-1600.png"))
	var pile_press := InputEventMouseButton.new()
	pile_press.button_index = MOUSE_BUTTON_LEFT
	pile_press.pressed = true
	pile_press.global_position = library_pile.get_global_rect().intersection(Rect2(Vector2.ZERO, size)).get_center()
	library_pile._gui_input(pile_press)
	var pile_motion := InputEventMouseMotion.new()
	pile_motion.global_position = Vector2(hand_root.global_position.x + hand_root.size.x * 0.5, size.y - 75)
	library_pile._input(pile_motion)
	await _save_frame(directory.path_join("library-drag-1600.png"))
	pile_press.pressed = false
	pile_press.global_position = pile_motion.global_position
	library_pile._input(pile_press)
	await _save_frame(directory.path_join("library-drawn-1600.png"))
	var held: Control = cards[10]
	var hand_press := InputEventMouseButton.new()
	hand_press.button_index = MOUSE_BUTTON_LEFT
	hand_press.pressed = true
	hand_press.global_position = held.get_global_transform() * (held.size * 0.5)
	held._gui_input(hand_press)
	held._process(0.2)
	var hand_motion := InputEventMouseMotion.new()
	hand_motion.global_position = Vector2(hand_root.global_position.x + hand_root.size.x * 0.6, size.y - 110)
	held._input(hand_motion)
	assert(hand_gap_index >= 0, "Reordering must display a hand gap")
	await _save_frame(directory.path_join("hand-reorder-1600.png"))
	hand_press.pressed = false
	hand_press.global_position = hand_motion.global_position
	held._input(hand_press)
	await _save_frame(directory.path_join("hand-reordered-1600.png"))
	_reset()
	await _capture_hover(1, directory.path_join("hover-guardian-1600.png"))
	await _capture_hover(2, directory.path_join("hover-oracle-1600.png"))
	capture_size = Vector2i(1280, 800)
	get_window().size = capture_size
	await _save_frame(directory.path_join("table-1280.png"))
	for seat in [1, 2]:
		await _click_phase_button(seat, "Main 2")
		assert(not phase_labels[seat]["Main 2"].button_pressed, "The opponent phase strip must receive clicks at 1280px: seat=%s rect=%s hover=%s" % [seat, phase_labels[seat]["Main 2"].get_global_rect(), get_viewport().gui_get_hovered_control()])
		await _save_frame(directory.path_join("phase-stop-%s-1280.png" % seat))
		await _click_phase_button(seat, "Main 2")
		assert(phase_labels[seat]["Main 2"].button_pressed, "The opponent phase strip must re-enable its stop at 1280px")
	await _capture_hover(1, directory.path_join("hover-guardian-1280.png"))
	await _capture_hover(2, directory.path_join("hover-oracle-1280.png"))
	await _capture_hover(10, directory.path_join("hover-hand-1280.png"))
	await _capture_hover(30, directory.path_join("hover-tapped-1280.png"))
	assert(primary.get_global_rect().end.y < size.y - 24, "Action controls clipped by viewport")
	_select_card(cards[14].data)
	_primary_action()
	await _save_frame(directory.path_join("unused-play-1280.png"))
	_return_selected()
	await _save_frame(directory.path_join("returned-hand-1280.png"))
	for _i in range(12):
		_intent("draw")
	_scroll_hand(100)
	await _save_frame(directory.path_join("large-hand-1280.png"))
	_reset()
	_show_card_detail(cards[2].data)
	await _save_frame(directory.path_join("inspection-1280.png"))
	_close_modal()
	_intent("crowd")
	await _save_frame(directory.path_join("crowded-1280.png"))
	await get_tree().process_frame
	assert(not rows.your_creatures.scroll.get_h_scroll_bar().visible, "Crowded fields must fit without a horizontal scrollbar")
	_reset()
	await get_tree().create_timer(0.25).timeout
	_drag_card(1, Vector2(100, -40))
	await _save_frame(directory.path_join("moved-card-1280.png"))
	assert(not cards[1].data.tapped, "Drag screenshot must preserve untapped state")
	_click_card(1)
	await _save_frame(directory.path_join("moved-tapped-card-1280.png"))
	_reset()
	while snapshot.game.phase != "Declare attackers":
		_intent("advance")
	_click_card(1)
	await _save_frame(directory.path_join("choose-defender-1280.png"))
	_choose_player(1)
	await _save_frame(directory.path_join("attack-1280.png"))
	_intent("prompt", {"kind": "order"})
	modal_panel._toggle(1)
	modal_panel._toggle(0)
	await _save_frame(directory.path_join("prompt-1280.png"))
	_open_decision({"id": 99108, "mode": "live", "kind": "message", "title": "Message", "message": "Mira is going first.\n\nYou are going second.\nReview your opening hand before the game begins.", "options": []})
	await _save_frame(directory.path_join("forge-message-1280.png"))

	var siege := {"id": 352, "name": "Citadel Siege", "imageKey": "c:Citadel Siege|FRF|8", "text": "As Citadel Siege enters, choose Khans or Dragons.\n\n\n\n\u2022 Khans \u2014 At the beginning of combat on your turn, put two +1/+1 counters on target creature you control.\n\n\u2022 Dragons \u2014 At the beginning of combat on each opponent's turn, tap target creature that player controls.", "typeLine": "Enchantment", "color": "W"}
	_open_decision({"id": 99109, "mode": "live", "kind": "message", "title": "Citadel Siege (352)", "message": "Bot 3 chose Dragons", "sourceCard": siege, "options": []})
	await _save_frame(directory.path_join("terminal-citadel-message-1280.png"))
	var siege_text: Control = modal_panel.source_view.get_parent().get_child(1)
	assert(siege_text.label.text == "Bot 3 chose Dragons" and not siege_text.reading_hint.visible, "Source messages retain the actual decision without duplicating the card's printed rules")
	assert(Rect2(Vector2.ZERO, size).encloses(modal_panel.get_global_rect()), "The source-card message fits the smaller viewport")

	_show_help()
	await _save_frame(directory.path_join("help-popup-1280.png"))
	assert(Rect2(Vector2.ZERO, size).encloses(modal_center.get_child(0).get_global_rect()), "Long information text must fit inside the viewport")
	_close_modal()
	print("PASS: rendered visual checks (two sizes, inspection, crowded packing, attack, ordering)")
	get_tree().quit()

func _capture_hover(id: int, path: String) -> void:
	var was_synthetic := synthetic_hover
	synthetic_hover = true
	# A synthetic hover must not be replaced by OS mouse-enter/exit notifications
	# while the offscreen window and scroll containers settle.
	for view in cards.values():
		if view.mouse_entered.is_connected(view._mouse_enter):
			view.mouse_entered.disconnect(view._mouse_enter)
		if view.mouse_exited.is_connected(view._mouse_exit):
			view.mouse_exited.disconnect(view._mouse_exit)
	if not cards[id].hand_mode:
		board_scroller.ensure_control_visible(cards[id])
	await get_tree().create_timer(0.2).timeout
	cards[id]._on_enter()
	await _save_frame(path)
	if cards[id].hand_mode:
		var copy: Control = hand_copies[id]
		assert(copy.visible and absf((copy.global_position.y - cards[id].get_global_transform().origin.y) + 22) < 1, "Hand hover must lift only slightly")
		assert(copy.z_index == cards[id].resting_z * 2 + 1 and copy.get_parent() == hand_root, "Hover must preserve the hand's occlusion order")
		assert(inspection.visible and inspection_card.size.y >= 450 and inspection.get_parent() == self, "The side preview must be 25 percent larger")
		assert(absf(inspection.get_global_rect().get_center().y - size.y * 0.5) < 1, "Preview must be vertically centered")
		assert(cards[id].position.distance_to(cards[id].resting_position) < 0.5, "Hand hover input must stay stable")
		cards[id]._on_exit()
		assert(copy.visible and cards[id].hand_hover_amount > 0.5, "Unhover must retain the lifted card for its return animation")
		cards[id].animation.pause()
		cards[id].animation.custom_step(0.05)
		_sync_hand_copies()
		assert(copy.visible and cards[id].hand_hover_amount > 0 and cards[id].hand_hover_amount < 1, "Return must interpolate smoothly")
		cards[id].animation.play()
		await get_tree().create_timer(0.22).timeout
		assert(not copy.visible and cards[id].visual.visible, "Return must finish in the fan")
	else:
		assert(raised_card.visible and raised_card.get_parent() == self, "Hovered card must render outside row clipping")
		assert(raised_card.get_global_transform().is_equal_approx(cards[id].get_global_transform()), "Hover copy must match the animated card transform")
		cards[id]._on_exit()
		assert(not raised_card.visible, "Hover copy must disappear when leaving a battlefield card")
	for view in cards.values():
		if not view.mouse_entered.is_connected(view._mouse_enter):
			view.mouse_entered.connect(view._mouse_enter)
		if not view.mouse_exited.is_connected(view._mouse_exit):
			view.mouse_exited.connect(view._mouse_exit)
	synthetic_hover = was_synthetic
