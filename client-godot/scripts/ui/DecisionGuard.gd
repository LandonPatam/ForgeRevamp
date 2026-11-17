extends Control
## Never a dead end. Forge is the rules authority; the table only presents its questions. When
## Forge waits on this seat and nothing on screen can answer it (a tether that didn't recognise
## the question, picks that never reached Forge), this shows Forge's raw question with its own
## buttons after a few seconds and saves a bug report. F8 saves a report any time.
##
## A report is a folder under user://reports/: the seat's snapshot, recent prompt history, which
## controls were showing, a screenshot and, for the host, Forge's full board export (board.state,
## the test-board format): `node client-godot/tools/report-to-scenario.mjs <folder> <name>`.
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const Prompt = preload("res://scripts/ui/PromptPanel.gd")
const STUCK_SECONDS := 4.0
## Picks staged locally that Forge hasn't confirmed this long are a stall too.
const COMMIT_STALL_SECONDS := 8.0
const HISTORY := 40

var main: Control
var history: Array = []
var last_revision := -1
var stuck_key := ""
var stuck_since := 0
var dismissed_key := ""
var commit_key := ""
var commit_since := 0
var box: PanelContainer
var body: VBoxContainer
var showing_key := ""
var last_report := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 400
	box = PanelContainer.new()
	Terminal.panel(box, 16)
	box.custom_minimum_size.x = 520
	box.hide()
	add_child(box)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	box.add_child(body)

func _process(_delta: float) -> void:
	if main == null or not main.live: return
	var state: Dictionary = main.snapshot
	if state.is_empty(): return
	_record(state)
	var waiting := _waiting(state)
	var key := ""
	if not waiting.is_empty() and not _answerable(state): key = waiting + "|" + _question_key(state)
	elif _commit_stalled(state): key = "stalled|" + _question_key(state)
	if key != stuck_key:
		stuck_key = key
		stuck_since = Time.get_ticks_msec()
	if not showing_key.is_empty() and showing_key != key:
		_hide()
	if key.is_empty() or key == dismissed_key or key == showing_key: return
	if Time.get_ticks_msec() - stuck_since < STUCK_SECONDS * 1000.0: return
	print("DECISION GUARD: nothing on screen answers Forge (%s); showing its raw question" % key.left(160))
	last_report = save_report("Stuck: Forge waited on this seat with nothing on screen to answer it (%s)." % key.left(300))
	_show(state, key)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8 and main != null and main.live:
		save_report("Manual report (F8).")
		get_viewport().set_input_as_handled()

## What Forge is waiting for from this seat, or "" when it isn't.
static func _waiting(state: Dictionary) -> String:
	if not state.get("connectionReady", false) or state.get("game", {}).get("gameOver", false): return ""
	if not state.get("asks", []).is_empty(): return "ask:" + str(state.asks[0].get("kind", ""))
	var prompt: Dictionary = state.get("prompt", {})
	var kind := str(prompt.get("inputKind", ""))
	if kind in ["", "InputLockUI"]: return ""
	if prompt.get("okEnabled", false) or prompt.get("cancelEnabled", false) or not prompt.get("selectable", []).is_empty() or not prompt.get("entities", []).is_empty(): return kind
	return ""

static func _question_key(state: Dictionary) -> String:
	var prompt: Dictionary = state.get("prompt", {})
	return str(prompt.get("inputKind", "")) + "|" + str(prompt.get("message", "")).left(120) + "|" + str(state.get("asks", []).map(func(ask): return ask.get("id", -1)))

## Whether any control that reaches Forge is on screen (or an action is already in flight).
func _answerable(state: Dictionary) -> bool:
	if not main._match_outcome().is_empty() or main.layout_paused: return true
	if str(main.adapter.get("pending")) != "" or main.adapter.get("syncing") == true: return true
	if main.modal.visible or main.opening_hand.visible or main.board_choice.visible or main.hand_pick_panel.visible: return true
	if main.targeting or main.incoming_effect.showing(): return true
	# Answering a stack spell with one you're casting (Counterspell -> Wrath) and the end screens.
	if is_instance_valid(main.response_target) and main.response_target.is_visible_in_tree(): return true
	if is_instance_valid(main.outcome_screen) and main.outcome_screen.is_visible_in_tree(): return true
	var panel: Control = main.interaction_panel
	if panel.panel.is_visible_in_tree() or panel.callout.is_visible_in_tree(): return true
	if not state.get("pendingDraws", []).is_empty() and main.library_pile.is_visible_in_tree(): return true
	for button in [main.primary, main.cancel_button]:
		if is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled: return true
	return false

## Targets or hand picks staged and being sent, but Forge's prompt hasn't moved for a while.
func _commit_stalled(state: Dictionary) -> bool:
	var committing: bool = main.target_committing or main.hand_pick_committing
	var key := (str(state.get("revision", -1)) + "|" + _question_key(state)) if committing else ""
	if key != commit_key:
		commit_key = key
		commit_since = Time.get_ticks_msec()
	return committing and Time.get_ticks_msec() - commit_since > COMMIT_STALL_SECONDS * 1000.0

func _record(state: Dictionary) -> void:
	var revision := int(state.get("revision", -1))
	if revision == last_revision: return
	last_revision = revision
	var prompt: Dictionary = state.get("prompt", {})
	history.append({"time": Time.get_datetime_string_from_system(), "revision": revision,
		"turn": state.get("game", {}).get("turn", -1), "phase": state.get("game", {}).get("phase", ""),
		"inputKind": prompt.get("inputKind", ""), "message": str(prompt.get("message", "")).left(300),
		"source": prompt.get("sourceCard", {}).get("name", ""), "ok": prompt.get("okEnabled", false), "cancel": prompt.get("cancelEnabled", false),
		"selectable": prompt.get("selectable", []).size(), "chosen": prompt.get("chosen", []),
		"asks": state.get("asks", []).map(func(ask): return {"kind": ask.get("kind", ""), "title": ask.get("title", ""), "message": str(ask.get("message", "")).left(200), "options": ask.get("options", []).map(func(option): return option.get("label", ""))}),
		"stack": state.get("stack", []).map(func(item): return item.get("sourceName", item.get("card", {}).get("name", "")))})
	if history.size() > HISTORY: history.pop_front()

# ------------------------------------------------------------------ fallback panel

func _show(state: Dictionary, key: String) -> void:
	showing_key = key
	for child in body.get_children(): child.queue_free()
	body.add_child(_label("[ FORGE IS WAITING ON YOU ]", 12, Terminal.MUTED))
	body.add_child(_label("The table couldn't show this decision, so here is Forge's own question. A bug report was saved" + (":\n" + last_report if not last_report.is_empty() else "."), 13, Terminal.MUTED))
	var asks: Array = state.get("asks", [])
	if not asks.is_empty():
		var panel := Prompt.new()
		body.add_child(panel)
		panel.answered.connect(func(id, value):
			main._intent("answer", {"id": id, "value": value})
			_hide())
		panel.present(asks[0])
	else:
		var prompt: Dictionary = state.get("prompt", {})
		body.add_child(_label(str(prompt.get("message", "")).strip_edges(), 16, Terminal.INK))
		var picks := HFlowContainer.new()
		picks.add_theme_constant_override("h_separation", 8)
		picks.add_theme_constant_override("v_separation", 8)
		body.add_child(picks)
		var names := {}
		for card in prompt.get("cards", []): names[int(card.get("id", -1))] = str(card.get("name", "Card"))
		for id in prompt.get("selectable", []).slice(0, 16):
			var card_id := int(id)
			var name: String = names.get(card_id, main.cards[card_id].data.get("name", "Card") if main.cards.has(card_id) else "Card %d" % card_id)
			picks.add_child(_button(name, func(): _act("card", {"id": card_id})))
		for entity in prompt.get("entities", []):
			if entity.get("kind", "") != "player": continue
			var seat := int(entity.get("id", -1))
			picks.add_child(_button(str(entity.get("name", "Player")), func(): _act("player", {"id": seat})))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		body.add_child(row)
		if prompt.get("okEnabled", false): row.add_child(_button(str(prompt.get("okLabel", "OK")), func(): _act("ok"), true))
		if prompt.get("cancelEnabled", false): row.add_child(_button(str(prompt.get("cancelLabel", "Cancel")), func(): _act("cancel")))
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	body.add_child(tools)
	tools.add_child(_button("Hide", func():
		dismissed_key = showing_key
		_hide()))
	box.show()
	box.reset_size()
	box.position = ((size - box.size) * 0.5).round()

func _act(action: String, extra: Dictionary = {}) -> void:
	main._intent(action, extra)
	_hide()

func _hide() -> void:
	showing_key = ""
	box.hide()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 480
	label.add_theme_font_override("font", Terminal.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	Terminal.button(button, primary)
	button.pressed.connect(callback)
	return button

# ------------------------------------------------------------------ reports

## Writes a report folder and returns its absolute path. The host's bridge adds board.state.
func save_report(reason: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "-")
	var folder := "user://reports/report-%s-%d" % [stamp, Time.get_ticks_msec() % 1000]
	DirAccess.make_dir_recursive_absolute(folder)
	var absolute := ProjectSettings.globalize_path(folder)
	_write(folder.path_join("snapshot.json"), JSON.stringify(main.snapshot, "\t"))
	_write(folder.path_join("history.json"), JSON.stringify(history, "\t"))
	_write(folder.path_join("ui.json"), JSON.stringify(_ui_state(), "\t"))
	var online: bool = not str(main.adapter.get("seat_token")).is_empty()
	_write(folder.path_join("notes.txt"), reason + "\n" + ("Joined online seat: no board.state (it would show other players' hidden cards); the host can press F8 for one.\n" if online else ""))
	if DisplayServer.get_name() != "headless":
		var image: Image = get_viewport().get_texture().get_image()
		if image != null and not image.is_empty(): image.save_png(folder.path_join("screen.png"))
	var sent: bool = main.adapter.has_method("request_report") and main.adapter.request_report(absolute)
	print("BUG REPORT saved: ", absolute)
	main._show_toast("Bug report saved: " + absolute, 6.0)
	if sent and not main.adapter.report_saved.is_connected(_board_saved):
		main.adapter.report_saved.connect(_board_saved.bind(absolute), CONNECT_ONE_SHOT)
	return absolute

func _board_saved(ok: bool, message: String, absolute: String) -> void:
	if not ok: print("BUG REPORT board.state missing for ", absolute, ": ", message)

func _ui_state() -> Dictionary:
	var panel: Control = main.interaction_panel
	return {"modal": main.modal.visible, "modalPanel": (main.modal_panel.get_script().resource_path.get_file() if is_instance_valid(main.modal_panel) and main.modal_panel.get_script() != null else ""),
		"railDecision": panel.panel.is_visible_in_tree(), "tether": panel.callout.is_visible_in_tree(), "targetTether": panel.target_tether,
		"optionalGate": panel.optional_gate, "staged": main.target_staged, "targetCommitting": main.target_committing,
		"handPick": main.hand_pick_panel.visible, "handPickCommitting": main.hand_pick_committing, "boardChoice": main.board_choice.visible,
		"incomingEffect": main.incoming_effect.showing(), "openingHand": main.opening_hand.visible, "targetingAttack": main.targeting,
		"deferredActivation": main.deferred_activation, "optionalDecisions": main.optional_decisions,
		"primary": {"text": main.primary.text, "enabled": not main.primary.disabled, "visible": main.primary.is_visible_in_tree()},
		"adapterPending": str(main.adapter.get("pending")), "adapterSyncing": main.adapter.get("syncing")}

static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(text)
