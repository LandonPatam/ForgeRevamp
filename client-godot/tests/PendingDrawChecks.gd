extends RefCounted
class DelayedDraw:
	extends "res://scripts/bridge/StateAdapter.gd"
	var on_send: Callable
	var sent: Array = []
	func send_intent(intent: Dictionary) -> void:
		sent.append(intent)
		on_send.call()

func run(ui: Control, directory: String = "") -> void:
	var saved: Dictionary = ui.snapshot.duplicate(true)
	var original_adapter = ui.adapter
	var delayed := DelayedDraw.new()
	ui.adapter = delayed
	var fixture: Dictionary = saved.duplicate(true)
	fixture.mode = "live"
	fixture.connectionReady = true
	fixture.availableActions.draw = true
	ui._apply_state(fixture)
	var pending: Dictionary = fixture.duplicate(true)
	pending.connectionReady = false
	pending.availableActions.draw = false
	delayed.on_send = func(): ui._apply_state(pending)
	var target := Vector2(ui.hand_root.global_position.x + ui.hand_root.size.x * 0.5, ui.size.y - 40)
	ui._drag_library(target)
	assert(delayed.sent.size() == 1 and delayed.sent[0].action == "draw")
	assert(ui.library_draw_pending and ui.library_ghost.visible and ui.hand_gap_index >= 0)
	var gap: int = ui.hand_gap_index
	ui._apply_state(pending)
	await ui.get_tree().create_timer(0.12).timeout
	assert(ui.library_ghost.visible and ui.hand_gap_index == gap and ui.pending_hand_origin == target, "Network delay must not hide the held card or collapse its gap")
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("library-awaiting-draw.png"))
	var drawn: Dictionary = fixture.players[0].zones.Hand[0].duplicate(true)
	drawn.id = 9902
	fixture.players[0].zones.Hand.append(drawn)
	fixture.players[0].handCount += 1
	fixture.players[0].libraryCount -= 1
	fixture.availableActions.draw = false
	ui._apply_state(fixture)
	assert(not ui.library_draw_pending and not ui.library_ghost.visible and ui.hand_gap_index == -1)
	var card: Control = ui.cards[drawn.id]
	assert(card.drop_pointer.is_finite(), "The revealed card must not instantly re-hover under the stationary drop pointer")
	assert((card.global_position + card.size * 0.5).distance_to(target) < 0.1, "The actual card must replace the held back at the same position")
	var animation: Tween = card.animation
	var flip: Tween = card.reveal_animation
	assert(flip != null and is_zero_approx(card.reveal_progress), "An accepted draw starts face down at its drop position")
	flip.pause()
	ui._apply_state(fixture)
	assert(card.animation == animation, "Repeated acknowledgements must not restart the draw animation")
	assert(card.reveal_animation == flip and is_zero_approx(card.reveal_progress), "Repeated snapshots must not restart or reveal the flip early")
	flip.custom_step(card.REVEAL_SECONDS * 0.25)
	assert(card.reveal_progress > 0 and card.reveal_progress < 0.5)
	assert(is_equal_approx(float(card.visual.material.get_shader_parameter("reveal_progress")), card.reveal_progress))
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("library-flip-back.png"))
	flip.custom_step(card.REVEAL_SECONDS * 0.25)
	assert(is_equal_approx(card.reveal_progress, 0.5), "The card turns edge-on halfway through the flip")
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("library-flip-edge.png"))
	flip.custom_step(card.REVEAL_SECONDS * 0.25)
	assert(card.reveal_progress > 0.5 and card.reveal_progress < 1.0)
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("library-flip-face.png"))
	flip.custom_step(card.REVEAL_SECONDS * 0.25 + 0.01)
	assert(is_equal_approx(card.reveal_progress, 1.0) and card.scale.is_equal_approx(Vector2.ONE), "Flip finishes face up without changing the card's layout size")
	if not directory.is_empty():
		await ui._save_frame(directory.path_join("library-revealed-draw.png"))
	fixture.availableActions.draw = true
	ui._apply_state(fixture)
	ui._drag_library(target)
	ui._notify("Draw rejected (test)")
	assert(not ui.library_draw_pending and not ui.library_ghost.visible and ui.hand_gap_index == -1 and ui.pending_hand_slot == -1, "Rejected draws must clean up their presentation")
	ui.adapter = original_adapter
	ui._apply_state(saved)
	ui.toast.hide()
	await ui.get_tree().process_frame
	ui.toast.show()
	ui.toast.modulate.a = 0
	print("PASS: asynchronous library draw, back-to-face flip, snapshot continuity, insertion gap and rejected-draw cleanup")
