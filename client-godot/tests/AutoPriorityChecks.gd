extends RefCounted
const Live = preload("res://scripts/bridge/LiveAdapter.gd")
class RecordingLive:
	extends "res://scripts/bridge/LiveAdapter.gd"
	var sent: Array = []
	func send_intent(intent: Dictionary) -> void:
		sent.append(intent)
		pending = "auto-test-" + str(sent.size())

func run() -> void:
	var state := {"connectionReady": true, "game": {}, "stack": [{"id": 12}], "autoPassStackId": 12, "prompt": {"inputKind": "InputPassPriority", "okEnabled": true}, "asks": [], "pendingDraws": []}
	assert(Live.can_auto_pass(state))
	assert(Live.is_automatic_stack(state), "Routine stack items are passive while Forge resolves them")
	state.takebackCast = {"id": 90}
	assert(Live.can_auto_pass(state), "A routine cast must proceed without an extra takeback confirmation")
	state.takebackCast.typeLine = "Legendary Creature — Angel"
	assert(Live.can_auto_pass(state), "A paid routine creature must continue without an extra confirmation")
	state.autoPassStackId = -1
	assert(not Live.can_auto_pass(state), "Targeted or unclassified creature casts must retain their interaction")
	state.autoPassStackId = 12
	state.takebackCast.typeLine = "Artifact"
	assert(Live.can_auto_pass(state), "Sol Ring and other routine artifacts must resolve without Continue")
	state.erase("takebackCast")
	for kind in ["InputSelectTargets", "InputPayManaOfCostPayment", "InputConfirm", "InputAttack"]:
		state.prompt.inputKind = kind
		assert(not Live.can_auto_pass(state), "Never bypass a required interaction")
		assert(not Live.is_automatic_stack(state), "A real decision must restore its stack context and controls")
	state.prompt.inputKind = "InputPassPriority"
	state.autoPassStackId = -1
	assert(not Live.can_auto_pass(state), "Unclassified effects/damage must wait")
	state.autoPassStackId = 13
	assert(not Live.can_auto_pass(state), "The permission must match the current stack top")
	state.autoPassStackId = 12
	state.asks = [{"kind": "choose"}]
	assert(not Live.can_auto_pass(state))
	state.asks.clear()
	state.pendingDraws = [42]
	assert(not Live.can_auto_pass(state))
	state.pendingDraws.clear()
	state.connectionReady = false
	assert(not Live.can_auto_pass(state))
	state.connectionReady = true
	var adapter := RecordingLive.new()
	adapter.connected = true
	adapter.syncing = false
	adapter.state = state
	adapter.state.availableActions = {}
	adapter.prepaid_target = 90
	adapter._service_auto_priority()
	assert(adapter.sent.is_empty(), "Payment and cancellation must settle before automatic priority may run")
	adapter.prepaid_target = -1
	adapter._service_auto_priority()
	assert(adapter.sent.is_empty(), "Wait briefly for the settled prompt")
	adapter.auto_priority_due = 0
	adapter._service_auto_priority()
	adapter.pending = ""
	adapter._service_auto_priority()
	assert(adapter.sent == [{"action": "ok"}], "Auto-pass once per stack item")
	adapter.pending = adapter.auto_priority_request
	adapter._receive({"protocolVersion": 2, "type": "error", "requestId": adapter.pending, "message": "State changed"})
	assert(adapter.auto_priority_sent == -1 and not adapter.state.connectionReady, "A rejected auto-pass must wait for refreshed state")
	adapter.syncing = false
	adapter.state.connectionReady = true
	adapter._service_auto_priority()
	adapter.auto_priority_due = 0
	adapter._service_auto_priority()
	assert(adapter.sent.size() == 2, "Routine priority should be reevaluated from the fresh state after rejection")
	adapter.pending = ""
	adapter.state.stack.push_front({"id": 88})
	adapter._service_auto_priority()
	assert(adapter.auto_priority_sent == -1, "An opponent response must start a fresh priority cycle")
	adapter.state.stack.pop_front()
	adapter._service_auto_priority()
	adapter.auto_priority_due = 0
	adapter._service_auto_priority()
	assert(adapter.sent.size() == 3, "The original automatic effect must continue after the response resolves")
	state.stack.clear()
	assert(not Live.can_auto_pass(state), "Never auto-advance an empty main phase")
	adapter._service_auto_priority()
	assert(adapter.auto_priority_sent == -1)
	var effect_adapter := RecordingLive.new()
	effect_adapter.connected = true
	effect_adapter.syncing = false
	effect_adapter.state = {"connectionReady": true, "game": {}, "stack": [{"id": 91}], "prompt": {"inputKind": "InputSelectTargets", "okEnabled": true}, "asks": [], "pendingDraws": []}
	effect_adapter.acknowledge_effect(91)
	assert(effect_adapter.sent.is_empty(), "Acknowledging an effect must never confirm its targeting")
	for kind in ["InputPayManaOfCostPayment", "InputConfirm", "InputAttack"]:
		effect_adapter.state.prompt.inputKind = kind
		effect_adapter._service_effect_acknowledgment()
		assert(effect_adapter.sent.is_empty(), "An acknowledgment must wait through required engine decisions")
	effect_adapter.state.prompt.inputKind = "InputPassPriority"
	effect_adapter.state.stack.push_front({"id": 92})
	effect_adapter._service_effect_acknowledgment()
	assert(effect_adapter.sent.is_empty(), "An acknowledgment must not pass for a different stack top")
	effect_adapter.state.stack.pop_front()
	effect_adapter.state.asks = [{"kind": "choose"}]
	effect_adapter._service_effect_acknowledgment()
	assert(effect_adapter.sent.is_empty())
	effect_adapter.state.asks.clear()
	effect_adapter.pending = "previous-action"
	effect_adapter._service_effect_acknowledgment()
	assert(effect_adapter.sent.is_empty(), "A click during synchronization must wait until the previous action settles")
	effect_adapter.pending = ""
	effect_adapter._service_effect_acknowledgment()
	effect_adapter._service_effect_acknowledgment()
	assert(effect_adapter.sent == [{"action": "ok"}], "The popup OK must pass priority exactly once for its acknowledged effect")
	effect_adapter.pending = ""
	effect_adapter.state.stack.clear()
	effect_adapter.acknowledge_effect(91)
	effect_adapter._service_effect_acknowledgment()
	assert(effect_adapter.sent.size() == 1 and effect_adapter.acknowledged_effects.is_empty(), "Closing an already-resolved notice must not advance the phase")
	effect_adapter.state.stack = [{"id": 94}, {"id": 93}]
	effect_adapter.state.prompt.inputKind = "InputSelectTargets"
	effect_adapter.acknowledge_effect(93)
	effect_adapter.acknowledge_effect(94)
	effect_adapter.state.prompt.inputKind = "InputPassPriority"
	effect_adapter._service_effect_acknowledgment()
	assert(effect_adapter.sent.size() == 2 and effect_adapter.acknowledged_effects == [93], "Queued acknowledgments must consume only the current top")
	effect_adapter.pending = ""
	effect_adapter.state.stack.pop_front()
	effect_adapter._service_effect_acknowledgment()
	assert(effect_adapter.sent.size() == 3 and effect_adapter.acknowledged_effects.is_empty(), "An earlier acknowledged effect must retain its priority pass after a response resolves")
	_check_resolve_all()
	print("PASS: automatic routine priority and required-choice/damage/empty-stack guards")

## Table setting "Auto-resolve the stack": passes any stack item, never a decision.
func _check_resolve_all() -> void:
	var held := {"connectionReady": true, "game": {}, "stack": [{"id": 70}], "autoPassStackId": -1, "prompt": {"inputKind": "InputPassPriority", "okEnabled": true}, "asks": [], "pendingDraws": []}
	assert(Live.can_resolve_all(held) and not Live.can_auto_pass(held))
	var adapter := RecordingLive.new()
	adapter.connected = true
	adapter.syncing = false
	adapter.state = held
	adapter._service_auto_priority()
	adapter.auto_priority_due = 0
	adapter._service_auto_priority()
	assert(adapter.sent.is_empty(), "With the setting off, a held stack item keeps its response window")
	adapter.auto_resolve_all = true
	adapter._service_auto_priority()
	adapter.auto_priority_due = 0
	adapter._service_auto_priority()
	assert(adapter.sent == [{"action": "ok"}], "With the setting on, any stack item passes priority once")
	adapter.pending = ""
	adapter._service_auto_priority()
	assert(adapter.sent.size() == 1, "Never pass the same stack item twice")
	for blocked in [{"asks": [{"kind": "choose"}]}, {"pendingDraws": [5]}, {"takebackCast": {"id": 9}}, {"stack": []}, {"prompt": {"inputKind": "InputSelectTargets", "okEnabled": true}}, {"prompt": {"inputKind": "InputPayManaOfCostPayment", "okEnabled": false}}]:
		var state := held.duplicate(true)
		state.merge(blocked, true)
		assert(not Live.can_resolve_all(state), "Auto-resolve never answers a decision, draw, own undo window or empty stack: %s" % [blocked])
