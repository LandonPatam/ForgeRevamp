extends RefCounted

func run(ui: Control, rendered: bool = false) -> void:
	var order: Array = ui.hand_order.duplicate()
	var synthetic: bool = ui.synthetic_hover
	ui.synthetic_hover = true
	# Reverse the fan without recreating nodes: creation order now disagrees
	# with visual order, as it does after inserting a new draw to the left.
	ui.hand_order.reverse()
	ui._layout_hand()
	await ui.get_tree().create_timer(0.25).timeout
	ui._sync_hand_copies()
	var visible: Array = ui._ordered_hand().filter(func(card): return ui.cards[card.id].visible)
	assert(visible.size() >= 2)
	var target: Control = ui.cards[visible.back().id]
	var neighbor: Control = ui.cards[visible[visible.size() - 2].id]
	target._on_enter()
	await ui.get_tree().create_timer(0.12).timeout
	ui._sync_hand_copies()
	var previous := -1
	for card in ui._ordered_hand():
		var view: Control = ui.cards[card.id]
		assert(view.get_index() > previous, "Hand input order must follow the fan after reordering")
		previous = view.get_index()
		var copy: Control = ui.hand_copies[card.id]
		assert(copy.get_index() > previous, "The lifted face must receive input above its own source")
		previous = copy.get_index()
	var point: Vector2 = target.get_global_transform() * Vector2(22, 65)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	press.global_position = point
	if rendered:
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		ui.get_viewport().push_input(motion)
		ui.get_viewport().push_input(press)
	else:
		ui._hand_copy_input(press, target)
	assert(target.press_pending and not neighbor.press_pending, "Pressing the hovered face must capture that card, never its left neighbor")
	target._process(0.2)
	assert(ui.dragged_source == target and target.drag_active, "Holding the hovered card must drag the same card")
	target._finish_press(true)
	assert(target.data.zone == "Hand" and ui.dragged_source == null, "Canceling the regression gesture must preserve the hand")
	ui.hand_order = order
	ui.synthetic_hover = synthetic
	ui._layout_hand()
	ui._sync_hand_copies()
	await ui.get_tree().process_frame
	print("PASS: reordered hand hit testing, lifted-face press and matching drag capture")
