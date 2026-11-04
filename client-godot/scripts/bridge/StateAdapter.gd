extends RefCounted
## Transport boundary: scenes consume snapshots and submit intents here.
## LiveAdapter translates contextual selections to docs/protocol.md; Forge owns legality.
## Snapshot availableActions.draw authorizes the library draw gesture (absent = false).
## Card availableActions.returnToHand is adapter-owned (absent = false).
## return_to_hand {id} requests an authorized undo, never a direct UI zone mutation.
## Live implementations must use Forge permissions/undo and session/revision validation.
signal state_changed(snapshot: Dictionary)
signal status_changed(message: String)
signal feedback(message: String)
signal action_rejected(id: int)
signal session_reset
signal session_ended(message: String)

func poll(_delta: float) -> void:
	pass

func start() -> void:
	pass

func send_intent(_intent: Dictionary) -> void:
	push_error("StateAdapter.send_intent must be implemented")
