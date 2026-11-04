extends "res://scripts/bridge/StateAdapter.gd"
## Deliberately scripted visual interactions. These are NOT legal Magic gameplay.
var state: Dictionary = {}
var next_id := 100
var crowded := false
var ask_id := 0
var phase_stops: Dictionary = {}
var return_candidate := -1

func start() -> void:
	reset()

func card(id: int, title: String, color: String, type_line: String, stats: String = "", cost: String = "", art: String = "grove") -> Dictionary:
	return {"id": id, "name": title, "color": color, "typeLine": type_line, "stats": stats,
		"manaCost": cost, "art": art, "tapped": false, "commander": false,
		"text": "Original placeholder card.\nNo rules are simulated."}

func player(id: int, title: String, life: int, color: String, initials: String) -> Dictionary:
	return {"id": id, "name": title, "life": life, "color": color, "initials": initials,
		"libraryCount": 83, "handCount": 6, "mana": {"G": 2, "U": 1}, "lost": false,
		"commanderDamage": [{"name": "Seren, Tidekeeper", "amount": 4}],
		"zones": {"Battlefield": [], "Hand": [], "Graveyard": [], "Exile": [], "Command": []}}

func reset() -> void:
	return_candidate = -1
	crowded = false
	next_id = 100
	var you := player(0, "You", 37, "G", "LK")
	var mira := player(1, "Mira", 40, "U", "MI")
	var thorne := player(2, "Thorne", 34, "R", "TH")
	you.zones.Battlefield = [card(1, "Mossheart Guardian", "G", "Creature · Elemental", "4 / 5", "3 G", "grove"),
		card(2, "Tideglass Oracle", "U", "Creature · Wizard", "2 / 3", "2 U", "island"),
		card(3, "Verdant Passage", "G", "Land", "", "", "grove"),
		card(4, "Moonlit Shoal", "U", "Land", "", "", "island"),
		card(5, "Ancient Clearing", "G", "Land", "", "", "ruins")]
	you.zones.Hand = [card(10, "Crown of the Canopy", "G", "Enchantment", "", "2 G", "grove"),
		card(11, "Astral Wayfinder", "U", "Creature · Scout", "3 / 2", "2 U", "island"),
		card(12, "Emberwake Drake", "R", "Creature · Drake", "4 / 3", "3 R", "ember"),
		card(13, "Quiet Reclamation", "G", "Sorcery", "", "1 G", "ruins"),
		card(14, "Moonlit Shoal", "U", "Land", "", "", "island")]
	you.zones.Command = [card(20, "Seren, Tidekeeper", "U", "Legendary Creature", "3 / 5", "2 G U", "island")]
	you.zones.Command[0].commander = true
	you.zones.Graveyard = [card(21, "Echoes of Spring", "G", "Sorcery", "", "G", "grove")]
	mira.zones.Battlefield = [card(30, "Mistveil Sentinel", "U", "Creature · Spirit", "2 / 4", "2 U", "island"),
		card(31, "Archivist of Tides", "U", "Creature · Wizard", "1 / 3", "1 U", "ruins"),
		card(32, "Moonlit Shoal", "U", "Land", "", "", "island"), card(33, "Glasswater Basin", "U", "Land", "", "", "island")]
	mira.zones.Battlefield[0].tapped = true
	mira.zones.Command = [card(34, "Ilyra, Dreamweaver", "U", "Legendary Creature", "2 / 6", "3 U U", "ruins")]
	thorne.zones.Battlefield = [card(40, "Ashen Ridgeback", "R", "Creature · Beast", "5 / 4", "4 R", "ember"),
		card(41, "Cinderpath Seer", "R", "Creature · Shaman", "2 / 2", "1 R", "ember"),
		card(42, "Ember Crags", "R", "Land", "", "", "ember"), card(43, "Sunken Monument", "B", "Land", "", "", "ruins")]
	thorne.zones.Command = [card(44, "Vael, Ash Sovereign", "R", "Legendary Creature", "5 / 5", "3 R R", "ember")]
	for p in [mira, thorne]:
		p.zones.Command[0].commander = true
		for i in range(p.handCount):
			p.zones.Hand.append({"id": next_id, "hidden": true})
			next_id += 1
	state = {"type": "state", "mode": "mock", "me": 0, "game": {"turn": 9, "phase": "Main 1", "activePlayer": 0, "gameOver": false},
		"players": [you, mira, thorne], "stack": [], "combat": [], "asks": [],
		"prompt": {"message": "Your main phase. Select a card to explore the table.", "okLabel": "Pass priority", "okEnabled": true},
		"log": ["Your turn · main phase", "Mira passed priority.", "Thorne drew a card."]}
	_publish()

func _publish() -> void:
	for player_value in state.players:
		for zone in player_value.zones:
			for value in player_value.zones[zone]:
				value.availableActions = {"returnToHand": player_value.id == 0 and zone == "Battlefield" and _can_return_to_hand(value.id)}
	for item in state.stack:
		item.card.availableActions = {"returnToHand": _can_return_to_hand(item.sourceId)}
	state.availableActions = {"draw": state.players[0].libraryCount > 0 and state.asks.is_empty()}
	state.players[0].handCount = state.players[0].zones.Hand.size()
	state_changed.emit(state.duplicate(true))

func _log(message: String) -> void:
	state.log.push_front(message)
	if state.log.size() > 25:
		state.log.resize(25)

func _can_return_to_hand(id: int) -> bool:
	if id != return_candidate or not state.asks.is_empty():
		return false
	if not state.stack.is_empty():
		return state.stack[0].sourceId == id
	return state.players[0].zones.Battlefield.any(func(c): return c.id == id and not c.tapped)

func send_intent(intent: Dictionary) -> void:
	var you: Dictionary = state.players[0]
	match intent.get("action", ""):
		"phase_stops":
			phase_stops = intent.get("stops", {}).duplicate(true)
		"reset":
			reset()
			return
		"tap":
			return_candidate = -1
			for c in you.zones.Battlefield:
				if c.id == intent.id:
					c.tapped = not c.tapped
					_log(("Tapped " if c.tapped else "Untapped ") + c.name + " · demo")
		"play":
			for c in you.zones.Hand:
				if c.id == intent.id:
					return_candidate = c.id
					you.zones.Hand.erase(c)
					if c.typeLine == "Land":
						you.zones.Battlefield.append(c)
						_log(c.name + " entered the battlefield · demo")
					else:
						state.stack.push_front({"id": c.id, "sourceId": c.id, "text": c.name, "card": c})
						_log(c.name + " put on the stack · demo")
					break
		"return_to_hand":
			var id: int = intent.get("id", -1)
			if not _can_return_to_hand(id):
				return
			var restored: Dictionary = {}
			if not state.stack.is_empty() and state.stack[0].sourceId == id:
				restored = state.stack.pop_front().card
			else:
				for c in you.zones.Battlefield:
					if c.id == id:
						restored = c
						you.zones.Battlefield.erase(c)
						break
			if restored.is_empty():
				return
			restored.tapped = false
			you.zones.Hand.append(restored)
			return_candidate = -1
			_log(restored.name + " returned to hand / unused mock play")
		"advance":
			if not state.stack.is_empty():
				var item: Dictionary = state.stack.pop_front()
				if item.sourceId != return_candidate:
					return_candidate = -1
				if item.card.typeLine == "Sorcery":
					return_candidate = -1
					you.zones.Graveyard.append(item.card)
				else:
					you.zones.Battlefield.append(item.card)
				_log(item.text + " resolved · demo")
			else:
				return_candidate = -1
				_advance_to_stop()

		"draw":
			if you.libraryCount <= 0 or not state.asks.is_empty():
				return
			return_candidate = -1
			you.zones.Hand.append(card(next_id, "Wildwood Envoy", "G", "Creature · Druid", "2 / 2", "1 G", "grove"))
			next_id += 1
			you.libraryCount -= 1
			_log("Drew an original placeholder card · demo")
		"attack":
			if state.game.phase != "Declare attackers" or state.game.activePlayer != 0 or int(intent.get("target", -1)) < 1 or int(intent.get("target", -1)) >= state.players.size():
				return
			for c in you.zones.Battlefield:
				if c.id == intent.id and c.typeLine.contains("Creature") and not c.tapped:
					return_candidate = -1
					c.tapped = true
					state.combat.append({"attacker": c.id, "defenderId": intent.target, "defenderKind": "player", "blockers": []})
					for p in state.players:
						if p.id == intent.target:
							p.life -= 3
							_log(c.name + " → " + p.name + ": 3 damage · visual demo")
		"crowd":
			return_candidate = -1
			crowded = not crowded
			if crowded:
				for i in range(14):
					you.zones.Battlefield.append(card(500 + i, "Sapling " + str(i + 1), "G", "Token Creature", "1 / 1", "", "grove"))
			else:
				you.zones.Battlefield = you.zones.Battlefield.filter(func(c): return c.id < 500)
			_log("Crowded board " + ("enabled" if crowded else "cleared") + " · cards arrange within the field")
		"prompt":
			return_candidate = -1
			_open_prompt(intent.kind)
		"answer":
			state.asks.clear()
			_log("Demo choice recorded: " + str(intent.get("value", "acknowledged")))
	_publish()

func _advance_to_stop() -> void:
	# Only presentation stops are skipped; crossed steps still receive their mock bookkeeping.
	var phases := ["Untap", "Upkeep", "Draw", "Main 1", "Begin combat", "Declare attackers", "Declare blockers", "First strike damage", "Combat damage", "End combat", "Main 2", "End step", "Cleanup"]
	for _crossed in range(phases.size()):
		var i := phases.find(state.game.phase)
		state.game.phase = phases[(i + 1) % phases.size()]
		if i == phases.size() - 1:
			state.game.turn += 1
			for c in state.players[0].zones.Battlefield:
				c.tapped = false
			state.combat.clear()
		if phase_stops.get(state.game.activePlayer, {}).get(state.game.phase, state.game.phase in ["Main 1", "Declare attackers", "Declare blockers", "Main 2"]):
			_log("Advanced to " + state.game.phase + " / demo")
			return
	_log("All stops off / advanced one demo turn")

func _open_prompt(kind: String) -> void:
	ask_id += 1
	var ask := {"id": ask_id, "kind": kind, "title": "Choose a path", "message": "Mock decision · try the generic fallback.",
		"min": 1, "max": 2, "options": [{"label": "Draw a card"}, {"label": "Create a Sapling"}, {"label": "Gain 3 life"}]}
	match kind:
		"order":
			ask.title = "Order your triggers"
			ask.message = "Select all three in the order they should appear."
			ask.min = 3
			ask.max = 3
		"distribute":
			ask.title = "Distribute counters"
			ask.message = "Assign 5 counters across these recipients."
			ask.amount = 5
			ask.atLeastOne = false
		"input":
			ask.title = "Name a card"
			ask.message = "Enter a name. Escape cancels this mock input."
			ask.initial = ""
			ask.numeric = false
		"message":
			ask.title = "A moment of clarity"
			ask.message = "This generic message can always be acknowledged. No Forge game is connected."
	state.asks = [ask]
