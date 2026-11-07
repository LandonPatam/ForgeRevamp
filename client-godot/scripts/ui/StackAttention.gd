extends Control
## Draw above dialog dimming, without intercepting any card or dialog input.
const P = preload("res://scripts/ui/Palette.gd")
var stack: Control
var decision: Control
var recipient_decision: Control
var attention := false
var capture_phase := -1.0

static func needs_choice(state: Dictionary) -> bool:
	if state.get("stack", []).is_empty() or not state.get("connectionReady", true) or state.get("game", {}).get("gameOver", false):
		return false
	var asks: Array = state.get("asks", [])
	if not asks.is_empty():
		return asks[0].get("kind", "") in ["choose", "order", "distribute", "input"]
	var prompt: Dictionary = state.get("prompt", {})
	var kind: String = prompt.get("inputKind", "")
	if kind.begins_with("InputSelect"):
		return not prompt.get("okEnabled", false) or prompt.get("chosen", []).is_empty()
	if kind.begins_with("InputPayMana"):
		return not prompt.get("okEnabled", false)
	if kind == "InputConfirm":
		return prompt.get("cancelEnabled", false)
	if kind == "InputPassPriority":
		# The stack is waiting on this player to resolve or respond, unless it passes itself.
		var top_id := int(state.stack[0].get("id", -1))
		if state.get("autoResolveAll", false) and state.get("takebackCast", {}).is_empty(): return false
		return prompt.get("okEnabled", false) and int(state.get("autoPassStackId", -1)) != top_id and state.get("takebackCast", {}).is_empty() and state.get("pendingDraws", []).is_empty()
	return false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 105
	set_process(false)

func present(state: Dictionary) -> void:
	attention = needs_choice(state)
	set_process(attention)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func attention_target() -> Control:
	if is_instance_valid(recipient_decision) and recipient_decision.visible: return recipient_decision.panel
	return decision.panel if is_instance_valid(decision) and decision.uses_stack_rail() else stack

func _draw() -> void:
	var target: Control = attention_target()
	if not attention or not is_instance_valid(target) or not target.is_visible_in_tree():
		return
	var rect := Rect2(get_global_transform().affine_inverse() * target.global_position, target.size).grow(5)
	if target.get_parent() is ScrollContainer:
		var viewport_rect: Rect2 = target.get_parent().get_global_rect()
		viewport_rect.position = get_global_transform().affine_inverse() * viewport_rect.position
		rect = rect.intersection(viewport_rect)
	# A steady accent outline remains between pulses; never blink the stack away.
	var pulse := (sin(Time.get_ticks_msec() * TAU / 1100.0) + 1.0) * 0.5 if capture_phase < 0 else capture_phase
	var accent := preload("res://scripts/ui/TerminalStyle.gd").ACCENT
	# Soft outer rings make the waiting stack obvious from across the table.
	for ring in range(6, 0, -1):
		var halo := P.box(Color.TRANSPARENT, Color(accent, (0.04 + pulse * 0.10) * (1.0 - ring / 7.0)), 10 + ring * 2, 0)
		halo.set_border_width_all(4)
		draw_style_box(halo, rect.grow(4 + ring * 3))
	var glow := P.box(Color.TRANSPARENT, Color(accent, 0.18 + pulse * 0.30), 10, 0)
	glow.set_border_width_all(7)
	draw_style_box(glow, rect.grow(3))
	var outline := P.box(Color.TRANSPARENT, Color(accent, 0.6 + pulse * 0.4), 7, 0)
	outline.set_border_width_all(3)
	draw_style_box(outline, rect)
