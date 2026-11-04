extends RefCounted
## One presentation policy for native engine inputs; engine flags own legality.
static func describe(state: Dictionary) -> Dictionary:
	var prompt: Dictionary = state.get("prompt", {})
	var kind: String = prompt.get("inputKind", "")
	if state.get("game", {}).get("gameOver", false) or kind in ["", "InputLockUI", "InputConfirmMulligan", "InputLondonMulligan"]: return {}
	var title := "Your decision"
	var confirm: String = prompt.get("okLabel", "Confirm")
	var help := ""
	match kind:
		"InputPassPriority":
			return {} # Priority and resolution use the existing stack rail.
		"InputSelectTargets":
			title = "Choose targets"
			confirm = "Confirm targets"
			help = "Click a highlighted card or choose a player below."
		"InputSelectStackItems":
			title = "Choose a spell or ability"
			confirm = "Confirm targets"
		"InputAttack":
			title = "Choose attackers"
			confirm = "Skip attacking" if state.get("combat", []).is_empty() else "Confirm attacks"
			help = "Click your creature, then an opponent's portrait."
		"InputBlock":
			title = "Choose blockers"
			confirm = "Confirm blocks"
			help = "Click an attacker, then your blocker. Click the blocker again to remove it."
		"InputPayMana", "InputPayManaOfCostPayment":
			title = "Pay the cost"
			help = "Use mana from your pool or activate a source on the board."
		"InputSelectEntitiesFromList", "InputSelectCardsFromList":
			title = "Proliferate" if prompt.has("selectionShortcut") else "Choose cards or players"
			confirm = "Confirm counters" if prompt.has("selectionShortcut") else "Confirm selection"
			help = "Click highlighted battlefield cards or player portraits. Confirm when finished."
		"InputSelectCardsForConvokeOrImprovise":
			title = "Choose cards to help pay"
			confirm = "Confirm payment"
		"InputConfirm":
			if not prompt.get("cancelEnabled", false): return {}
			title = "Confirm your choice"
		_:
			if kind.begins_with("InputSelect"): title = "Choose cards or players"
	if kind in ["InputSelectTargets", "InputSelectCardsFromList", "InputSelectEntitiesFromList"] and int(prompt.get("selMin", 1)) == 0 and prompt.get("chosen", []).is_empty() and prompt.get("okEnabled", false):
		confirm = "Choose none"
	return {"kind": kind, "title": title, "confirm": confirm, "help": help}
