extends Control
## Table animation director. Plays public happenings over the already-updated board:
## attack and block declarations, combat strikes, damage impacts and cards leaving the
## battlefield. Presentation only: it never answers Forge, never holds a decision back and
## never replays a session's earlier events (the first snapshot only primes what was seen).
## Each snapshot's new happenings form one beat; beats queue briefly and speed up instead of
## falling behind.
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")
const Mana = preload("res://scripts/ui/ManaCounter.gd")

## Duration factor from Table settings: 0 = animations off, 0.6 Fast, 1 Normal, 1.35 Cinematic.
static var speed := 1.0
const SPEEDS := [0.0, 0.6, 1.0, 1.35]
const SPEED_NAMES := ["Off", "Fast", "Normal", "Cinematic"]
const HIT := Color("ff5a4a")
const POISON := Color("8fe36b")
const TEAL := Color("65e0d5")
const VIOLET := Color("b48cff")
const GLYPHS := "#%&$@*+=/\\|01<>[]{}"
## A queued beat never waits longer than this; later beats overlap and run faster instead.
const MAX_BACKLOG := 0.9
## Performance caps: past these, cosmetic particles are dropped (numbers and exits never are).
const MAX_ITEMS := 360
const MAX_GLYPHS := 220
## Three or more permanents leaving in one beat read as a sweep across the table.
const SWEEP_MIN := 3
const SWEEP_SECONDS := 0.6

var card_view: Callable      ## id -> CardView on the table, or null
var portrait_view: Callable  ## seat -> PlayerAvatar, or null
var zone_point: Callable     ## (seat, zone) -> global point a departing card travels to
var stack_point: Callable    ## stack item id -> global point of its stack feed entry, or INF
var mana_point: Callable     ## mana key (W U B R G C) -> global point of your pool button, or INF

var primed := false
var last_fx_id := 0
var known_attackers: Dictionary = {}
var known_blocks: Dictionary = {}
var ghosts: Dictionary = {}          ## id -> {view, zone, seat}, kept alive until their beat ends
var pending_departures: Array = []   ## ghost ids that joined since the last beat was built
var offset_tweens: Dictionary = {}   ## view instance id -> Tween driving its fx_offset
var items: Array = []                ## transient drawn effects: numbers, flashes, rings, glyphs
var next_free := 0.0
## Stack items as last seen: id -> {targets: [{kind, id}], color, point, controller, source,
## seen}. Resolve and counter events arrive after an item left the snapshot, so they use this.
var stack_cache: Dictionary = {}
## Live lock-on brackets for what the stack is aiming at: [{kind, id, color}].
var lock_targets: Array = []
var player_engine: Dictionary = {}  ## engine player id -> seat
## The previous snapshot, reduced to what board-life effects compare: card id -> {seat, zone,
## counters, power, toughness, tapped}, seat -> life, and your mana pool.
var previous_cards: Dictionary = {}
var previous_life: Dictionary = {}
var previous_mana: Dictionary = {}
## The last labels shown (damage numbers, counters, life), newest last: for checks and reports.
var shown_labels: Array = []
var played: Dictionary = {}
## Worst cost of this director's own work in microseconds, for performance checks.
var cost := {"draw": 0, "present": 0}
## Turn banner: the last turn/active seat shown, so reconnects and snapshots never repeat it.
var banner_key := ""
var turn_name: Callable  ## seat -> display name
var banner_point: Callable  ## -> global top-center point for the turn banner
var table_rect: Callable  ## -> global rect of the table itself (not the rail)
var flash_box := StyleBoxFlat.new()
var clock := 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)

static func enabled() -> bool:
	return speed > 0.0

## Forget everything: a new session, a cleared table or a parked match never replays old beats.
func reset() -> void:
	for id in ghosts.keys():
		if is_instance_valid(ghosts[id].view): ghosts[id].view.queue_free()
	ghosts.clear()
	pending_departures.clear()
	items.clear()
	known_attackers.clear()
	known_blocks.clear()
	offset_tweens.clear()
	stack_cache.clear()
	lock_targets.clear()
	previous_cards.clear()
	previous_life.clear()
	previous_mana.clear()
	banner_key = ""
	primed = false
	last_fx_id = 0
	next_free = 0.0
	queue_redraw()

## A battlefield card left the table. Returns true when the director keeps the view alive to
## play its exit; the caller has already forgotten it, so it is never clickable again.
func depart(view: Control, zone: String, seat: int) -> bool:
	if not primed or not enabled() or not is_instance_valid(view) or not view.is_inside_tree():
		return false
	var id := int(view.data.get("id", -1))
	if id < 0 or ghosts.has(id): return false
	if view.animation != null: view.animation.kill()
	if view.hover_active:
		view.hover_active = false
		view.unhovered.emit()
	view.visual.show()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_process(false)
	view.set_process_input(false)
	view.reparent(self, true)
	ghosts[id] = {"view": view, "zone": zone, "seat": seat}
	pending_departures.append(id)
	return true

func view_for(id: int) -> Control:
	if ghosts.has(id) and is_instance_valid(ghosts[id].view): return ghosts[id].view
	var view = card_view.call(id) if card_view.is_valid() else null
	return view if is_instance_valid(view) and view.is_visible_in_tree() else null

## Called after each snapshot's layout, so card positions are current.
func present(snapshot: Dictionary) -> void:
	var began := Time.get_ticks_usec()
	_present(snapshot)
	cost.present = maxi(cost.present, Time.get_ticks_usec() - began)

func _present(snapshot: Dictionary) -> void:
	var fx: Array = snapshot.get("fx", [])
	var newest := last_fx_id
	for event in fx: newest = maxi(newest, int(event.get("id", 0)))
	var prompt_kind: String = snapshot.get("prompt", {}).get("inputKind", "")
	var attacks: Array = []
	var blocks: Array = []
	var attackers_now := {}
	var blocks_now := {}
	for combat in snapshot.get("combat", []):
		var attacker := int(combat.get("attacker", -1))
		# The attacking seat's own picks are final only once Forge leaves its attack input.
		if prompt_kind != "InputAttack":
			attackers_now[attacker] = true
			if primed and not known_attackers.has(attacker): attacks.append(combat)
		if prompt_kind != "InputBlock":
			for blocker in combat.get("blockers", []):
				var key := "%d>%d" % [int(blocker), attacker]
				blocks_now[key] = true
				if primed and not known_blocks.has(key): blocks.append([int(blocker), attacker])
	if prompt_kind != "InputAttack": known_attackers = attackers_now
	if prompt_kind != "InputBlock": known_blocks = blocks_now
	var fresh: Array = fx.filter(func(event): return int(event.get("id", 0)) > last_fx_id) if primed else []
	last_fx_id = newest
	player_engine.clear()
	for seat in range(snapshot.get("players", []).size()):
		player_engine[int(snapshot.players[seat].get("engineId", seat))] = seat
	var stack: Array = snapshot.get("stack", [])
	var casts: Array = stack.filter(func(item): return primed and not stack_cache.has(int(item.id)))
	var changes: Dictionary = _board_changes(snapshot) if primed else {}
	var turn_key := "%s/%s" % [snapshot.get("game", {}).get("turn", ""), snapshot.get("game", {}).get("activePlayer", "")]
	var new_turn := primed and banner_key != "" and turn_key != banner_key
	banner_key = turn_key
	_remember_board(snapshot)
	_remember_stack(stack)
	if not primed:
		primed = true
		return
	if not enabled():
		lock_targets.clear()
		_release_departures()
		queue_redraw()
		return
	_aim_locks(stack)
	if new_turn and speed >= 1.0: _turn_banner(snapshot)
	if attacks.is_empty() and blocks.is_empty() and fresh.is_empty() and pending_departures.is_empty() and casts.is_empty() and changes.is_empty():
		return
	_play_beat(snapshot, attacks, blocks, fresh, casts, changes)

func _board_cards(snapshot: Dictionary) -> Dictionary:
	var result := {}
	for seat in range(snapshot.get("players", []).size()):
		var zones: Dictionary = snapshot.players[seat].get("zones", {})
		for zone in zones:
			for card in zones[zone]:
				result[int(card.id)] = {"seat": seat, "zone": zone, "counters": card.get("counters", {}).duplicate(), "power": card.get("power", null), "toughness": card.get("toughness", null),
					"tapped": card.get("tapped", false), "token": card.get("token", false), "land": str(card.get("typeLine", "")).contains("Land")}
	return result

func _remember_board(snapshot: Dictionary) -> void:
	previous_cards = _board_cards(snapshot)
	previous_life.clear()
	for seat in range(snapshot.get("players", []).size()): previous_life[seat] = int(snapshot.players[seat].get("life", 0))
	previous_mana = snapshot.players[0].get("mana", {}).duplicate() if not snapshot.get("players", []).is_empty() else {}

## What changed on the board since the previous snapshot: permanents that entered (and from
## where), counter and power/toughness changes, life changes and your mana. Empty when nothing did.
func _board_changes(snapshot: Dictionary) -> Dictionary:
	if previous_cards.is_empty() or snapshot.get("players", []).is_empty(): return {}
	var now := _board_cards(snapshot)
	var entered: Array = []
	var counters: Array = []
	var stats: Array = []
	var tapped_lands: Array = []
	for id in now:
		var card: Dictionary = now[id]
		if card.zone != "Battlefield": continue
		var before: Dictionary = previous_cards.get(id, {})
		if before.is_empty() or before.zone != "Battlefield":
			entered.append({"id": id, "seat": card.seat, "token": card.token, "land": card.land, "from": before.get("zone", ""), "fromSeat": int(before.get("seat", card.seat))})
			continue
		if card.seat == 0 and card.land and card.tapped and not before.tapped: tapped_lands.append(id)
		var deltas := {}
		for key in card.counters.keys() + before.counters.keys():
			var delta := int(card.counters.get(key, 0)) - int(before.counters.get(key, 0))
			if delta != 0: deltas[key] = delta
		if not deltas.is_empty():
			counters.append({"id": id, "deltas": deltas})
		elif card.power != null and before.power != null and (card.power != before.power or card.toughness != before.toughness):
			stats.append({"id": id, "power": int(card.power) - int(before.power), "toughness": int(card.toughness) - int(before.toughness)})
	var life: Array = []
	for seat in range(snapshot.players.size()):
		var delta := int(snapshot.players[seat].get("life", 0)) - int(previous_life.get(seat, snapshot.players[seat].get("life", 0)))
		if delta != 0: life.append({"seat": seat, "delta": delta})
	var mana := {}
	var pool: Dictionary = snapshot.players[0].get("mana", {})
	for key in Mana.KEYS:
		var delta := int(pool.get(key, 0)) - int(previous_mana.get(key, 0))
		if delta != 0: mana[key] = delta
	var result := {}
	if not entered.is_empty(): result.entered = entered
	if not counters.is_empty(): result.counters = counters
	if not stats.is_empty(): result.stats = stats
	if not life.is_empty(): result.life = life
	if not mana.is_empty() or not tapped_lands.is_empty(): result.mana = {"pool": mana, "lands": tapped_lands}
	return result

## Card color of a stack item from its mana cost: one color, a blend for gold, gray for none.
static func spell_color(item: Dictionary) -> Color:
	var cost: String = str(item.get("card", {}).get("manaCost", ""))
	var palette := {"W": Color("fff1c4"), "U": Color("5aa9ff"), "B": Color("b07cff"), "R": Color("ff6a3d"), "G": Color("6fe07a")}
	var found: Array = []
	for letter in ["W", "U", "B", "R", "G"]:
		if cost.contains(letter): found.append(palette[letter])
	if found.is_empty(): return Color("c9d6d6")
	var mixed: Color = found[0]
	for index in range(1, found.size()): mixed = mixed.lerp(found[index], 1.0 / (index + 1))
	return mixed

func _remember_stack(stack: Array) -> void:
	var now := _now()
	var live := {}
	for item in stack:
		var id := int(item.id)
		live[id] = true
		var entry: Dictionary = stack_cache.get(id, {})
		entry.targets = item.get("targets", []).map(func(target): return {"kind": str(target.get("kind", "")), "id": int(target.get("id", -1))})
		entry.color = spell_color(item)
		entry.controller = int(item.get("controller", -1))
		entry.source = int(item.get("sourceId", -1))
		var point: Vector2 = stack_point.call(id) if stack_point.is_valid() else Vector2.INF
		if point.is_finite(): entry.point = point
		entry.seen = now
		stack_cache[id] = entry
	for id in stack_cache.keys():
		if not live.has(id) and now - float(stack_cache[id].seen) > 6.0: stack_cache.erase(id)

func _aim_locks(stack: Array) -> void:
	lock_targets.clear()
	for item in stack:
		for target in item.get("targets", []):
			lock_targets.append({"kind": str(target.get("kind", "")), "id": int(target.get("id", -1)), "color": spell_color(item)})
	if not lock_targets.is_empty(): set_process(true)
	queue_redraw()

## Where a stack target is on screen: a card on the table or a player's portrait.
func _stack_target_point(target: Dictionary) -> Vector2:
	if target.kind == "player":
		var avatar = portrait_view.call(int(player_engine.get(int(target.id), -1))) if portrait_view.is_valid() else null
		return avatar.get_global_rect().get_center() if is_instance_valid(avatar) else Vector2.INF
	if target.kind == "card":
		var view := view_for(int(target.id))
		return _center(view) if view != null else Vector2.INF
	return Vector2.INF

func _stack_origin(id: int) -> Vector2:
	var live: Vector2 = stack_point.call(id) if stack_point.is_valid() else Vector2.INF
	if live.is_finite(): return live
	var entry: Dictionary = stack_cache.get(id, {})
	if entry.has("point"): return entry.point
	var avatar = portrait_view.call(int(player_engine.get(int(entry.get("controller", -1)), -1))) if portrait_view.is_valid() else null
	return avatar.get_global_rect().get_center() if is_instance_valid(avatar) else Vector2.INF

func _release_departures() -> void:
	for id in pending_departures:
		if ghosts.has(id):
			if is_instance_valid(ghosts[id].view): ghosts[id].view.queue_free()
			ghosts.erase(id)
	pending_departures.clear()

## Every drawn effect goes through here; `played` counts kinds for checks and reports.
func _add(item: Dictionary) -> void:
	if items.size() >= MAX_ITEMS and item.kind in ["glyph", "ring", "spark", "mana"]: return
	items.append(item)
	played[item.kind] = int(played.get(item.kind, 0)) + 1

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _play_beat(snapshot: Dictionary, attacks: Array, blocks: Array, fresh: Array, casts: Array = [], changes: Dictionary = {}) -> void:
	var now := _now()
	var start := maxf(now, next_free)
	var pace := speed
	if start - now > MAX_BACKLOG:
		# Bots act faster than the table can show: overlap and hurry rather than lag behind.
		start = now + 0.05
		pace = speed * 0.5
	var at := start - now
	var length := 0.0
	for combat in attacks:
		var view := view_for(int(combat.attacker))
		var aim := _defender_point(combat)
		if view != null and aim.is_finite():
			_lunge(view, aim, at, 30.0, 0.16 * pace, 0.24 * pace, false)
			length = maxf(length, 0.42 * pace)
	for pair in blocks:
		var blocker := view_for(pair[0])
		var attacker := view_for(pair[1])
		if blocker != null and attacker != null:
			_lunge(blocker, _center(attacker), at, 24.0, 0.14 * pace, 0.22 * pace, false)
			_pulse_ring(_center(blocker), at + 0.12 * pace, TEAL, 0.32 * pace)
			length = maxf(length, 0.4 * pace)
	for item in casts:
		var id := int(item.id)
		var seat := int(player_engine.get(int(item.get("controller", -1)), -1))
		var origin := Vector2.INF
		var source := view_for(int(item.get("sourceId", -1)))
		if item.get("ability", false) and source != null: origin = _center(source)
		elif seat > 0 and portrait_view.is_valid() and is_instance_valid(portrait_view.call(seat)): origin = portrait_view.call(seat).get_global_rect().get_center()
		if not origin.is_finite(): continue # Your own spells already fly from your hand.
		_cast_spark(origin, id, at, spell_color(item), 0.34 * pace)
		length = maxf(length, 0.4 * pace)
	var impact_at := at
	var flight := 0.0
	for event in fresh:
		var kind: String = event.get("kind", "")
		if kind not in ["resolve", "fizzled", "countered"]: continue
		var id := int(event.get("stackId", -1))
		var entry: Dictionary = stack_cache.get(id, {})
		var origin := _stack_origin(id)
		if not origin.is_finite(): continue
		if kind == "countered":
			_shatter(origin, at, pace)
			length = maxf(length, 0.6 * pace)
			continue
		for target in entry.get("targets", []):
			var aim := _stack_target_point(target)
			if not aim.is_finite(): continue
			var color: Color = Color("8d9a9a") if kind == "fizzled" else entry.get("color", Color.WHITE)
			_projectile(origin, aim, at, color, 0.3 * pace, kind == "fizzled")
			flight = 0.3 * pace
	if flight > 0.0:
		impact_at = at + flight
		length = maxf(length, flight + 0.2 * pace)
	var struck := {}
	for event in fresh:
		if event.get("kind", "") != "damage" or not event.get("combat", false): continue
		var source := int(event.sourceId)
		if struck.has(source): continue
		var view := view_for(source)
		var aim := _target_point(event)
		if view == null or not aim.is_finite(): continue
		struck[source] = true
		_lunge(view, aim, at, 96.0, 0.13 * pace, 0.26 * pace, true)
		impact_at = maxf(impact_at, at + 0.21 * pace)
	var hits := 0
	for event in fresh:
		if event.get("kind", "") != "damage": continue
		if _impact(event, impact_at, pace): hits += 1
	var leave_at := impact_at + (0.3 * pace if hits > 0 else 0.0)
	if hits > 0: length = maxf(length, impact_at - at + 0.3 * pace)
	var leaving: Array = pending_departures.filter(func(id): return ghosts.has(id) and is_instance_valid(ghosts[id].view))
	if leaving.size() >= SWEEP_MIN:
		# A board wipe: a scan line crosses the table from the caster's side and each permanent
		# breaks apart as it passes, instead of everything vanishing at once.
		var area: Rect2 = table_rect.call() if table_rect.is_valid() else get_global_rect()
		var from_x := _sweep_origin(fresh, area)
		var to_x := area.end.x if from_x < area.get_center().x else area.position.x
		_add({"kind": "sweep", "from": from_x, "to": to_x, "top": area.position.y, "bottom": area.end.y, "start": clock + leave_at, "life": SWEEP_SECONDS * pace, "color": HIT})
		set_process(true)
		for id in leaving:
			var x := _center(ghosts[id].view).x
			var reach := clampf(absf(x - from_x) / maxf(1.0, absf(to_x - from_x)), 0.0, 1.0)
			_leave(id, leave_at + reach * SWEEP_SECONDS * pace, pace)
		length = maxf(length, leave_at - at + (SWEEP_SECONDS + 0.62) * pace)
	else:
		for id in leaving:
			_leave(id, leave_at, pace)
			length = maxf(length, leave_at - at + 0.62 * pace)
	pending_departures.clear()
	if not changes.is_empty():
		length = maxf(length, _board_life(changes, fresh, casts, at, impact_at, pace))
	next_free = now + at + length * 0.85

## Phase 3: the board coming alive. Returns how long its effects run.
func _board_life(changes: Dictionary, fresh: Array, casts: Array, at: float, impact_at: float, pace: float) -> float:
	var length := 0.0
	# The card whose resolution caused this beat, for tokens and counters it made.
	# Only when exactly one item resolved and it is not itself entering the table.
	var cause: Control = null
	var resolved: Array = fresh.filter(func(event): return event.get("kind", "") == "resolve")
	var entering: Array = changes.get("entered", []).map(func(entry): return int(entry.id))
	if resolved.size() == 1:
		var source := int(stack_cache.get(int(resolved[0].stackId), {}).get("source", -1))
		if not entering.has(source): cause = view_for(source)
	var token_index := 0
	for entry in changes.get("entered", []):
		var view := view_for(int(entry.id))
		if view == null: continue
		if entry.token:
			var delay := at + minf(0.6, token_index * 0.04) * pace
			token_index += 1
			_print_token(view, delay, pace, cause)
			length = maxf(length, delay - at + 0.5 * pace)
			continue
		if int(entry.seat) == 0 and entry.from in ["Hand", "Stack", ""]: continue # Your own plays already travel.
		var origin := _entry_origin(entry)
		if not origin.is_finite(): continue
		if int(entry.seat) != 0 and not entry.land:
			_showcase(view, origin, at, pace)
			length = maxf(length, 0.9 * pace)
		else:
			_slide_in(view, origin, at, 0.32 * pace)
			length = maxf(length, 0.36 * pace)
	var damaged := {}
	for event in fresh:
		if event.get("kind", "") == "damage" and event.get("targetKind", "") == "card": damaged[int(event.targetId)] = true
	for entry in changes.get("counters", []):
		var view := view_for(int(entry.id))
		if view == null: continue
		var parts: Array = []
		var gained := false
		for key in entry.deltas:
			var delta: int = entry.deltas[key]
			if delta < 0 and str(key).to_upper() in ["LOYALTY", "DEFENSE"] and damaged.has(int(entry.id)): continue # Combat damage already showed it.
			parts.append(counter_label(str(key), delta))
			gained = gained or delta > 0
		if parts.is_empty(): continue
		var color := TEAL if gained else HIT
		if cause != null and cause != view: _link(_center(cause), _center(view), impact_at, color, 0.35 * pace)
		_pulse_ring(_center(view), impact_at, color, 0.3 * pace)
		_number(", ".join(parts), _center(view) + Vector2(0, view.size.y * 0.25), impact_at, color, 18, pace, true)
		length = maxf(length, impact_at - at + 0.9 * pace)
	# Three or more cards changing alike is an anthem or a sweeper: one quiet pulse each, no numbers.
	var groups := {}
	for entry in changes.get("stats", []):
		var key := "%d/%d" % [entry.power, entry.toughness]
		if not groups.has(key): groups[key] = []
		groups[key].append(entry)
	for key in groups:
		var members: Array = groups[key]
		for index in range(members.size()):
			var entry: Dictionary = members[index]
			var view := view_for(int(entry.id))
			if view == null: continue
			var up: bool = entry.power + entry.toughness >= 0
			var color := POISON if up else HIT
			if members.size() >= 3:
				_pulse_ring(_center(view), impact_at + index * 0.03 * pace, color, 0.32 * pace)
			else:
				_pulse_ring(_center(view), impact_at, color, 0.3 * pace)
				_number("%s%d/%s%d" % ["+" if entry.power >= 0 else "-", absi(entry.power), "+" if entry.toughness >= 0 else "-", absi(entry.toughness)], _center(view) + Vector2(view.size.x * 0.22, view.size.y * 0.3), impact_at, color, 20, pace, true)
		length = maxf(length, impact_at - at + 0.9 * pace)
	_life_changes(changes.get("life", []), fresh, impact_at, pace)
	if changes.has("life"): length = maxf(length, impact_at - at + 0.9 * pace)
	if changes.has("mana") and speed >= 1.0:
		length = maxf(length, _mana_flow(changes.mana, casts, at, pace))
	return length

## The sweep starts on the side of whoever resolved the wipe (their portrait), else the left.
func _sweep_origin(fresh: Array, area: Rect2) -> float:
	for event in fresh:
		if event.get("kind", "") != "resolve": continue
		var seat := int(player_engine.get(int(stack_cache.get(int(event.stackId), {}).get("controller", -1)), -1))
		var avatar = portrait_view.call(seat) if seat >= 0 and portrait_view.is_valid() else null
		if is_instance_valid(avatar):
			return area.position.x if avatar.get_global_rect().get_center().x < area.get_center().x else area.end.x
	return area.position.x

## A new turn: a terminal strip slides across the top of the table naming whose turn it is, and
## the active portrait pulses once. It sits above the opponents' fields, never over a decision.
func _turn_banner(snapshot: Dictionary) -> void:
	var seat := int(snapshot.get("game", {}).get("activePlayer", -1))
	var name: String = turn_name.call(seat) if turn_name.is_valid() else ""
	if name.is_empty() and seat >= 0 and seat < snapshot.get("players", []).size(): name = str(snapshot.players[seat].get("name", ""))
	var text := "TURN %s  —  %s" % [str(snapshot.get("game", {}).get("turn", "")), ("YOUR TURN" if seat == 0 else name.to_upper())]
	_add({"kind": "banner", "text": text, "start": clock, "life": 1.5 * speed, "color": VIOLET})
	var avatar = portrait_view.call(seat) if portrait_view.is_valid() else null
	if is_instance_valid(avatar): _pulse_ring(avatar.get_global_rect().get_center(), 0.15, VIOLET, 0.45 * speed)
	set_process(true)

## Where an entering permanent comes from: the stack entry it resolved from, the zone icon it
## left (graveyard, exile, command zone), or its controller's portrait for a hidden hand.
func _entry_origin(entry: Dictionary) -> Vector2:
	for id in stack_cache:
		if int(stack_cache[id].get("source", -1)) == int(entry.id) and stack_cache[id].has("point"): return stack_cache[id].point
	if entry.from in ["Graveyard", "Exile", "Command", "Library"] and zone_point.is_valid():
		var point: Vector2 = zone_point.call(int(entry.fromSeat), str(entry.from))
		if point.is_finite(): return point
	var avatar = portrait_view.call(int(entry.seat)) if portrait_view.is_valid() else null
	return avatar.get_global_rect().get_center() if is_instance_valid(avatar) else Vector2.INF

## Lands and your own returns: the card slides in from where it came along an arc.
func _slide_in(view: Control, origin: Vector2, delay: float, length: float) -> void:
	var start := origin - _center(view)
	view.fx_offset = start
	var bend := start * 0.5 + Vector2(0, -minf(80.0, start.length() * 0.25))
	var tween := _offset_tween(view)
	if delay > 0.0: tween.tween_interval(delay)
	tween.tween_method(func(t: float): view.fx_offset = _bezier(start, bend, Vector2.ZERO, t), 0.0, 1.0, maxf(length, 0.05)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## An opponent's play: it comes out of where it was cast, shows large for a moment so you can
## read it, then settles into its place.
func _showcase(view: Control, origin: Vector2, delay: float, pace: float) -> void:
	view.fx_alpha = 0.0
	var life := 0.9 * pace
	_add({"kind": "showcase", "view": view, "from": origin, "start": clock + delay, "life": life})
	var reveal := view.create_tween()
	reveal.tween_interval(delay + life)
	reveal.tween_callback(func(): view.fx_alpha = 1.0)
	set_process(true)

## A token prints itself in like a terminal: outline first, then its face line by line.
func _print_token(view: Control, delay: float, pace: float, cause: Control) -> void:
	view.fx_alpha = 0.0
	var life := 0.45 * pace
	_add({"kind": "print", "view": view, "start": clock + delay, "life": life})
	var reveal := view.create_tween()
	reveal.tween_interval(delay + life)
	reveal.tween_callback(func(): view.fx_alpha = 1.0)
	if cause != null and cause != view:
		_link(_center(cause), _center(view), delay, TEAL, 0.35 * pace)
		_pulse_ring(_center(cause), delay, TEAL, 0.3 * pace)
	set_process(true)

func _link(from: Vector2, to: Vector2, delay: float, color: Color, length: float) -> void:
	_add({"kind": "bolt", "from": from, "to": to, "bend": (from + to) * 0.5 + Vector2(0, -40), "start": clock + delay, "life": length, "color": color, "fizzle": true})
	set_process(true)

## Life that changed without damage: gains rise in teal, losses in violet, and a drain draws a
## line from each player who lost to each who gained.
func _life_changes(life: Array, fresh: Array, delay: float, pace: float) -> void:
	var damage := {}
	for event in fresh:
		if event.get("kind", "") == "damage" and event.get("targetKind", "") == "player" and not event.get("infect", false):
			damage[int(event.get("targetSeat", -1))] = int(damage.get(int(event.get("targetSeat", -1)), 0)) + int(event.amount)
	var gained: Array = []
	var lost: Array = []
	for entry in life:
		var rest: int = entry.delta + int(damage.get(int(entry.seat), 0))
		if rest == 0: continue
		var avatar = portrait_view.call(int(entry.seat)) if portrait_view.is_valid() else null
		if not is_instance_valid(avatar): continue
		var rect: Rect2 = avatar.get_global_rect()
		var color := TEAL if rest > 0 else VIOLET
		_number(("+%d" if rest > 0 else "-%d") % absi(rest), rect.get_center() + Vector2(-rect.size.x * 0.5 - 6, -6), delay, color, 30, pace)
		_pulse_ring(rect.get_center(), delay, color, 0.3 * pace)
		(gained if rest > 0 else lost).append(rect.get_center())
	for from in lost:
		for to in gained: _link(from, to, maxf(0.0, delay - 0.3 * pace), VIOLET, 0.3 * pace)

## Your mana: a symbol flies from each land you tapped to its pool slot, or straight into the
## spell you are casting when it was spent at once; spent pool mana flies into that spell.
func _mana_flow(mana: Dictionary, casts: Array, at: float, pace: float) -> float:
	var target := Vector2.INF
	for item in casts:
		if int(player_engine.get(int(item.get("controller", -1)), -1)) == 0 and stack_point.is_valid():
			target = stack_point.call(int(item.id))
	var gains: Dictionary = {}
	for key in mana.pool:
		if int(mana.pool[key]) > 0: gains[key] = int(mana.pool[key])
	var index := 0
	for id in mana.lands:
		var land := view_for(int(id))
		if land == null: continue
		var key := ""
		for candidate in gains:
			if gains[candidate] > 0:
				key = candidate
				gains[candidate] -= 1
				break
		var goal: Vector2 = mana_point.call(key) if key != "" and mana_point.is_valid() else target
		if not goal.is_finite(): continue
		_mana_symbol(_center(land), goal, key, at + index * 0.05 * pace, 0.4 * pace)
		index += 1
	if target.is_finite():
		for key in mana.pool:
			var spent := -int(mana.pool[key])
			for count in range(mini(spent, 5)):
				var from: Vector2 = mana_point.call(key) if mana_point.is_valid() else Vector2.INF
				if not from.is_finite(): break
				_mana_symbol(from, target, key, at + index * 0.05 * pace, 0.4 * pace)
				index += 1
	return 0.45 * pace + index * 0.05 * pace

func _mana_symbol(from: Vector2, to: Vector2, key: String, delay: float, length: float) -> void:
	_add({"kind": "mana", "from": from, "to": to, "bend": (from + to) * 0.5 + Vector2(0, -60), "key": key, "start": clock + delay, "life": length})
	set_process(true)

func _center(view: Control) -> Vector2:
	return view.get_global_transform() * (view.size * 0.5)

func _defender_point(combat: Dictionary) -> Vector2:
	if int(combat.get("defenderId", -1)) >= 0 and portrait_view.is_valid():
		var avatar = portrait_view.call(int(combat.defenderId))
		if is_instance_valid(avatar): return avatar.get_global_rect().get_center()
	var planeswalker := view_for(int(combat.get("defenderCardId", -1)))
	return _center(planeswalker) if planeswalker != null else Vector2.INF

func _target_point(event: Dictionary) -> Vector2:
	if event.get("targetKind", "") == "player":
		var avatar = portrait_view.call(int(event.get("targetSeat", -1))) if portrait_view.is_valid() else null
		return avatar.get_global_rect().get_center() if is_instance_valid(avatar) else Vector2.INF
	var view := view_for(int(event.targetId))
	return _center(view) if view != null else Vector2.INF

## Strike toward a point along a shallow arc and spring back: wind up, lunge, recoil.
func _lunge(view: Control, aim: Vector2, delay: float, reach: float, out_time: float, back_time: float, wind_up: bool) -> void:
	var travel := aim - _center(view)
	if travel.length() < 1.0: return
	var direction := travel.normalized()
	var tip := direction * minf(reach, travel.length() * 0.45)
	var bend := direction.orthogonal() * tip.length() * 0.18
	var tween := _offset_tween(view)
	if delay > 0.0: tween.tween_interval(delay)
	if wind_up:
		tween.tween_property(view, "fx_offset", -direction * 8.0, out_time * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var from: Vector2 = -direction * 8.0 if wind_up else Vector2.ZERO
	tween.tween_method(func(t: float): view.fx_offset = _bezier(from, tip * 0.5 + bend, tip, t), 0.0, 1.0, out_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(view, "fx_offset", Vector2.ZERO, back_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _offset_tween(view: Control) -> Tween:
	var key := view.get_instance_id()
	if offset_tweens.has(key) and offset_tweens[key] is Tween and offset_tweens[key].is_valid():
		offset_tweens[key].kill()
	var tween := view.create_tween()
	offset_tweens[key] = tween
	tween.finished.connect(func():
		if offset_tweens.get(key) == tween: offset_tweens.erase(key))
	return tween

func _bezier(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	return a * pow(1.0 - t, 2) + control * 2.0 * (1.0 - t) * t + b * t * t

## One damage event lands: the target shakes and flashes, a number rises off it.
func _impact(event: Dictionary, delay: float, pace: float) -> bool:
	var color := POISON if event.get("infect", false) else HIT
	var text := "-%d" % int(event.amount)
	if event.get("targetKind", "") == "player":
		var avatar = portrait_view.call(int(event.get("targetSeat", -1))) if portrait_view.is_valid() else null
		if not is_instance_valid(avatar): return false
		var rect: Rect2 = avatar.get_global_rect()
		_shake(avatar, "shake", delay, 0.3 * pace, 7.0)
		_pulse_ring(rect.get_center(), delay, color, 0.34 * pace)
		_number(text, rect.get_center() + Vector2(-rect.size.x * 0.5 - 6, -6), delay, color, 34, pace)
		return true
	var view := view_for(int(event.targetId))
	if view == null: return false
	_shake(view, "fx_shake", delay, 0.24 * pace, 6.0)
	_flash(view, delay, color, 0.3 * pace)
	var label := text
	if event.get("deathtouch", false): label += " DEATHTOUCH"
	_number(label, _center(view) + Vector2(0, -view.size.y * 0.18), delay, color, 30, pace)
	return true

func _shake(target: Object, property: String, delay: float, length: float, strength: float) -> void:
	var tween: Tween = target.create_tween()
	if delay > 0.0: tween.tween_interval(delay)
	var seed_x := rng.randf() * TAU
	tween.tween_method(func(t: float):
		var fall := pow(1.0 - t, 2)
		target.set(property, Vector2(sin(seed_x + t * 46.0) * strength, cos(seed_x + t * 31.0) * strength * 0.35) * fall), 0.0, 1.0, maxf(length, 0.05))
	tween.tween_callback(func(): target.set(property, Vector2.ZERO))

## A card leaves the table: death breaks it into terminal glyphs that fall into its graveyard,
## exile washes it out, bounce and tuck carry it to where it went.
func _leave(id: int, delay: float, pace: float) -> void:
	var ghost: Dictionary = ghosts[id]
	var view: Control = ghost.view
	if not is_instance_valid(view):
		ghosts.erase(id)
		return
	var goal: Vector2 = zone_point.call(int(ghost.seat), str(ghost.zone)) if zone_point.is_valid() else Vector2.INF
	var start := _center(view)
	var tween := view.create_tween()
	if delay > 0.0: tween.tween_interval(delay)
	match str(ghost.zone):
		"Exile":
			tween.tween_property(view, "modulate", Color(2.4, 2.4, 2.4, 1.0), 0.16 * pace).set_ease(Tween.EASE_OUT)
			tween.tween_callback(func(): _burst(start, view.size, Color.WHITE, Vector2(0, -60), 10, pace))
			tween.tween_property(view, "modulate:a", 0.0, 0.26 * pace).set_ease(Tween.EASE_IN)
		"Graveyard", "":
			var glitch := func(t: float):
				var step := floori(t * 7.0)
				view.fx_offset = Vector2((float(step % 3) - 1.0) * 5.0 * (1.0 - t), 0)
				view.modulate = Color(1.0, 0.55, 0.5, 1.0) if step % 2 == 0 else Color(0.6, 1.1, 1.05, 1.0)
			tween.tween_method(glitch, 0.0, 1.0, 0.2 * pace)
			var drift: Vector2 = (goal - start) if goal.is_finite() else Vector2(0, 80)
			tween.tween_callback(func(): _burst(start, view.size, HIT.lerp(TEAL, 0.35), drift, 16, pace))
			if goal.is_finite():
				_fly(tween, view, start, goal, 0.34 * pace)
			else:
				tween.tween_property(view, "modulate:a", 0.0, 0.22 * pace).set_ease(Tween.EASE_IN)
		_:
			if goal.is_finite():
				_fly(tween, view, start, goal, 0.42 * pace)
			else:
				tween.tween_property(view, "modulate:a", 0.0, 0.24 * pace).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		ghosts.erase(id)
		view.queue_free())

## Travel along an arc toward a zone, shrinking and fading as it arrives.
func _fly(tween: Tween, view: Control, start: Vector2, goal: Vector2, length: float) -> void:
	var lift := Vector2(0, -minf(140.0, start.distance_to(goal) * 0.3))
	var control := (start + goal) * 0.5 + lift
	var origin := view.position
	var to_local := get_global_transform().affine_inverse()
	tween.tween_method(func(t: float):
		var point := _bezier(start, control, goal, t)
		view.fx_offset = Vector2.ZERO
		view.position = origin + to_local.basis_xform(point - start)
		view.scale = Vector2.ONE * lerpf(1.0, 0.32, t)
		view.modulate.a = 1.0 - maxf(0.0, t - 0.55) / 0.45, 0.0, 1.0, maxf(length, 0.05)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

## A spell or ability going onto the stack: a spark from its caster or source into its entry.
func _cast_spark(origin: Vector2, stack_id: int, delay: float, color: Color, length: float) -> void:
	_add({"kind": "spark", "from": origin, "stack": stack_id, "start": clock + delay, "life": length, "color": color})
	set_process(true)

## A resolving spell's effect travelling from its stack entry to one target, styled by color.
func _projectile(origin: Vector2, aim: Vector2, delay: float, color: Color, length: float, fizzle: bool) -> void:
	var lift := Vector2(0, -minf(160.0, origin.distance_to(aim) * 0.28))
	_add({"kind": "bolt", "from": origin, "to": aim, "bend": (origin + aim) * 0.5 + lift, "start": clock + delay, "life": length, "color": color, "fizzle": fizzle})
	if fizzle:
		_number("FIZZLE", aim + Vector2(0, -10), delay + length, color, 20, 1.0, true)
	else:
		_pulse_ring(aim, delay + length, color, 0.3)
	set_process(true)

## A countered spell: its stack entry is struck through and breaks into glyphs.
func _shatter(at: Vector2, delay: float, pace: float) -> void:
	_add({"kind": "strike", "at": at, "start": clock + delay, "life": 0.5 * maxf(pace, 0.6), "color": HIT})
	get_tree().create_timer(maxf(delay + 0.12 * pace, 0.01)).timeout.connect(func(): _burst(at, Vector2(200, 40), HIT, Vector2(0, 60), 14, pace))
	_number("COUNTERED", at + Vector2(0, -6), delay, HIT, 20, pace, true)

func _flash(view: Control, delay: float, color: Color, length: float) -> void:
	_add({"kind": "flash", "view": view, "start": clock + delay, "life": length, "color": color})
	set_process(true)

func _pulse_ring(at: Vector2, delay: float, color: Color, length: float) -> void:
	_add({"kind": "ring", "at": at, "start": clock + delay, "life": length, "color": color})
	set_process(true)

## A counter change in the words printed on cards, matching the card's own badge: "+1/+1",
## "+1/+1 ×2", "-1/-1", "Loyalty +2"; a removed counter reads "+1/+1 −1".
static func counter_label(key: String, delta: int) -> String:
	var name: String = preload("res://scripts/ui/CardFace.gd").counter_label(key)
	if name.begins_with("+") or name.begins_with("-"):
		if delta > 0: return name + (" ×%d" % delta if delta > 1 else "")
		return "%s −%d" % [name, -delta]
	return "%s %s%d" % [name, "+" if delta > 0 else "−", absi(delta)]

func _number(text: String, at: Vector2, delay: float, color: Color, font_size: int, pace: float, plate := false) -> void:
	shown_labels.append(text)
	if shown_labels.size() > 24: shown_labels.pop_front()
	_add({"kind": "number", "text": text, "at": at, "start": clock + delay, "life": 0.95 * maxf(pace, 0.6), "color": color, "size": font_size, "plate": plate})
	set_process(true)

func _burst(at: Vector2, area: Vector2, color: Color, drift: Vector2, count: int, pace: float) -> void:
	var glyphs: int = items.reduce(func(total, item): return total + (1 if item.kind == "glyph" else 0), 0)
	count = mini(count, maxi(0, MAX_GLYPHS - glyphs))
	for i in range(count):
		var spot := at + Vector2(rng.randf_range(-0.4, 0.4) * area.x, rng.randf_range(-0.45, 0.45) * area.y)
		_add({"kind": "glyph", "at": spot, "drift": drift * rng.randf_range(0.55, 1.0) + Vector2(rng.randf_range(-24, 24), rng.randf_range(-30, 10)),
			"text": GLYPHS[rng.randi_range(0, GLYPHS.length() - 1)], "start": clock + rng.randf() * 0.08, "life": rng.randf_range(0.45, 0.7) * maxf(pace, 0.6), "color": color})
	set_process(true)

func _process(delta: float) -> void:
	clock += delta
	items = items.filter(func(item): return clock < item.start + item.life)
	queue_redraw()
	if items.is_empty() and lock_targets.is_empty(): set_process(false)

func _draw() -> void:
	var began := Time.get_ticks_usec()
	_draw_effects()
	cost.draw = maxi(cost.draw, Time.get_ticks_usec() - began)

func _draw_effects() -> void:
	var to_local := get_global_transform().affine_inverse()
	var font := Terminal.font()
	for lock in lock_targets:
		_draw_lock(lock, to_local)
	for item in items:
		var t: float = (clock - item.start) / item.life
		if t < 0.0: continue
		match item.kind:
			"flash":
				var view: Control = item.view
				if not is_instance_valid(view): continue
				var tint: Color = item.color
				tint.a = 0.55 * (1.0 - t)
				draw_set_transform_matrix(to_local * view.get_global_transform() * Transform2D(0, (view.fx_offset + view.fx_shake).rotated(-view.rotation)))
				flash_box.bg_color = tint
				flash_box.set_corner_radius_all(int(maxf(4.0, view.size.x * 0.06)))
				flash_box.anti_aliasing = true
				draw_style_box(flash_box, Rect2(Vector2.ZERO, view.size))
				draw_set_transform_matrix(Transform2D.IDENTITY)
			"ring":
				var ring: Color = item.color
				ring.a = 0.8 * (1.0 - t)
				draw_arc(to_local * item.at, lerpf(10.0, 58.0, 1.0 - pow(1.0 - t, 3)), 0, TAU, 40, ring, 3.0, true)
			"number":
				var rise := 1.0 - pow(1.0 - t, 3)
				var ink: Color = item.color
				ink.a = 1.0 if t < 0.6 else 1.0 - (t - 0.6) / 0.4
				var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - t * 6.0)
				var size_now := int(item.size * pop)
				var width := font.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now).x
				var spot: Vector2 = to_local * (item.at + Vector2(0, -46.0 * rise)) - Vector2(width * 0.5, 0)
				var shade := Color(0.02, 0.03, 0.03, ink.a * 0.85)
				if item.get("plate", false):
					# Words get an opaque terminal plate so they never sit on other text.
					var plate := Rect2(spot + Vector2(-10, -size_now * 0.9), Vector2(width + 20, size_now * 1.3))
					draw_rect(plate, Color(0.04, 0.06, 0.06, ink.a))
					draw_rect(plate, Color(ink, ink.a * 0.8), false, 1.5)
				draw_string_outline(font, spot, item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now, 6, shade)
				draw_string(font, spot, item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now, ink)
			"spark":
				var goal: Vector2 = stack_point.call(item.stack) if stack_point.is_valid() else Vector2.INF
				if not goal.is_finite(): goal = item.get("goal", item.from)
				item.goal = goal
				var bend: Vector2 = (item.from + goal) * 0.5 + Vector2(0, -80)
				_draw_trail(item.from, bend, goal, 1.0 - pow(1.0 - t, 3), item.color, to_local, 4.0)
				if t > 0.85:
					var ring: Color = item.color
					ring.a = (1.0 - t) / 0.15
					draw_arc(to_local * goal, 8.0 + 30.0 * (t - 0.85) / 0.15, 0, TAU, 32, ring, 2.0, true)
			"bolt":
				var travel := t * t
				_draw_trail(item.from, item.bend, item.to, travel, item.color, to_local, 3.0 if item.fizzle else 6.0)
				if not item.fizzle and item.color.r > 0.9 and item.color.g < 0.6:
					# Red: sparks fall off the head.
					var head := _bezier(item.from, item.bend, item.to, travel)
					for index in range(4):
						var spark := head + Vector2(sin(clock * 37.0 + index * 2.1), cos(clock * 29.0 + index * 1.7)) * 9.0
						draw_circle(to_local * spark, 2.0, Color(1.0, 0.85, 0.4, 0.9))
			"showcase":
				var view: Control = item.view
				if not is_instance_valid(view) or not view.is_inside_tree(): continue
				var face: Vector2 = view.visual.size
				var goal := _center(view)
				var area := get_global_rect()
				var big := 1.7
				var hold := goal + (area.get_center() - goal) * 0.35
				hold.x = clampf(hold.x, area.position.x + face.x * big * 0.5 + 16, area.end.x - face.x * big * 0.5 - 16)
				hold.y = clampf(hold.y, area.position.y + face.y * big * 0.5 + 16, area.end.y - face.y * big * 0.5 - 16)
				var spot := hold
				var k := big
				if t < 0.22:
					var u := 1.0 - pow(1.0 - t / 0.22, 3)
					spot = _bezier(item.from, (item.from + hold) * 0.5 + Vector2(0, -60), hold, u)
					k = lerpf(0.35, big, u)
				elif t > 0.62:
					var u := (t - 0.62) / 0.38
					u = u * u * (3.0 - 2.0 * u)
					spot = hold.lerp(goal, u)
					k = lerpf(big, 1.0, u)
				draw_texture_rect(view.surface.get_texture(), Rect2(to_local * spot - face * k * 0.5, face * k), false)
			"print":
				var view: Control = item.view
				if not is_instance_valid(view) or not view.is_inside_tree(): continue
				var face: Vector2 = view.visual.size
				var corner: Vector2 = to_local * _center(view) - face * 0.5
				var outline := TEAL
				outline.a = minf(1.0, t * 4.0) * (1.0 - maxf(0.0, t - 0.8) / 0.2)
				draw_rect(Rect2(corner, face).grow(-face.x * 0.05), outline, false, 1.5)
				var shown := clampf((t - 0.15) / 0.85, 0.0, 1.0)
				var source: Vector2 = Vector2(view.surface.size)
				if shown > 0.0:
					draw_texture_rect_region(view.surface.get_texture(), Rect2(corner, Vector2(face.x, face.y * shown)), Rect2(Vector2.ZERO, Vector2(source.x, source.y * shown)))
					var scan := TEAL
					scan.a = 0.9 * (1.0 - shown * 0.5)
					draw_line(corner + Vector2(face.x * 0.05, face.y * shown), corner + Vector2(face.x * 0.95, face.y * shown), scan, 2.0, true)
			"mana":
				var u := 1.0 - pow(1.0 - t, 2)
				var at_point: Vector2 = to_local * _bezier(item.from, item.bend, item.to, u)
				var slot := Mana.KEYS.find(item.key)
				var fill: Color = Mana.FILLS[slot] if slot >= 0 else Color("d0c6bb")
				var fade := 1.0 - maxf(0.0, t - 0.8) / 0.2
				draw_circle(at_point, 11.0, Color(0.05, 0.07, 0.07, 0.85 * fade))
				var glyph := String.chr(Mana.GLYPHS[slot]) if slot >= 0 else String.chr(Mana.GLYPHS[5])
				draw_string(Mana.ICON_FONT, at_point + Vector2(-9, 7), glyph, HORIZONTAL_ALIGNMENT_CENTER, 18, 18, Color(fill, fade))
			"sweep":
				# Linear, like each permanent's exit timing, so cards break as the line reaches them.
				var x: float = lerpf(item.from, item.to, t)
				var top: Vector2 = to_local * Vector2(x, item.top)
				var bottom: Vector2 = to_local * Vector2(x, item.bottom)
				var edge: Color = item.color
				var direction := signf(item.to - item.from)
				var fade := 1.0 - maxf(0.0, t - 0.85) / 0.15
				for band in range(8):
					var trail := edge
					trail.a = 0.26 * (1.0 - band / 8.0) * fade
					draw_line(top - Vector2(direction * band * 9.0, 0), bottom - Vector2(direction * band * 9.0, 0), trail, 9.0)
				edge.a = fade
				draw_line(top, bottom, edge.lerp(Color.WHITE, 0.5), 4.0, true)
			"banner":
				var area := get_global_rect()
				var size_now := 22
				var width := font.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now).x + 48.0
				var slide := 1.0 - pow(1.0 - minf(1.0, t / 0.2), 3)
				var leave := maxf(0.0, (t - 0.82) / 0.18)
				leave = leave * leave
				# Centered on the open strip just below the table divider: clear of the opponents'
				# panels, the pass notice above the divider, and every decision.
				var anchor: Vector2 = banner_point.call() if banner_point.is_valid() else Vector2(area.get_center().x, area.position.y + 22.0)
				var rest := anchor.x - width * 0.5
				var x: float = lerpf(area.position.x - width, rest, slide) + leave * (area.end.x - rest)
				var strip := Rect2(to_local * Vector2(x, anchor.y), Vector2(width, 40))
				var alpha := 1.0 - leave
				draw_rect(strip, Color(0.04, 0.05, 0.07, 0.92 * alpha))
				draw_rect(Rect2(strip.position, Vector2(4, strip.size.y)), Color(item.color, alpha))
				draw_rect(strip, Color(item.color, 0.7 * alpha), false, 1.5)
				draw_string(font, strip.position + Vector2(24, 28), item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now, Color(item.color.lerp(Color.WHITE, 0.3), alpha))
			"strike":
				var cut: Color = item.color
				cut.a = 1.0 - t
				var reach := minf(1.0, t * 4.0)
				var left: Vector2 = to_local * (item.at + Vector2(-110, 0))
				draw_line(left, left + Vector2(220 * reach, 0), cut, 3.0, true)
			"glyph":
				var ease_in := t * t
				var glyph: Color = item.color
				glyph.a = 1.0 - t
				draw_string(font, to_local * (item.at + item.drift * ease_in), item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, glyph)

## A comet along a quadratic arc up to `travel` (0..1): fading tail, bright head with a halo.
func _draw_trail(a: Vector2, bend: Vector2, b: Vector2, travel: float, color: Color, to_local: Transform2D, width: float) -> void:
	if travel <= 0.0: return
	var tail := maxf(0.0, travel - 0.3)
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	for index in range(13):
		var u := lerpf(tail, travel, index / 12.0)
		points.append(to_local * _bezier(a, bend, b, u))
		var c := color
		c.a = float(index) / 12.0
		colors.append(c)
	draw_polyline_colors(points, colors, width, true)
	var head: Vector2 = points[points.size() - 1]
	var halo := color
	halo.a = 0.25
	draw_circle(head, width * 2.2, halo)
	draw_circle(head, width * 0.9, color.lerp(Color.WHITE, 0.6))

## Corner brackets on something a stack item is aiming at, pulsing in the spell's color.
func _draw_lock(lock: Dictionary, to_local: Transform2D) -> void:
	var rect := Rect2()
	var placed := Transform2D.IDENTITY
	if lock.kind == "player":
		var avatar = portrait_view.call(int(player_engine.get(int(lock.id), -1))) if portrait_view.is_valid() else null
		if not is_instance_valid(avatar) or not avatar.is_visible_in_tree(): return
		rect = Rect2(Vector2.ZERO, avatar.size)
		placed = to_local * avatar.get_global_transform()
	elif lock.kind == "card":
		var view := view_for(int(lock.id))
		if view == null: return
		rect = Rect2(Vector2.ZERO, view.size)
		placed = to_local * view.get_global_transform()
	else:
		return
	var color: Color = lock.color
	color.a = 0.55 + 0.35 * sin(clock * 5.0)
	var box := rect.grow(6.0 + 2.0 * sin(clock * 5.0))
	var arm := minf(box.size.x, box.size.y) * 0.22
	draw_set_transform_matrix(placed)
	for corner in [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]:
		var sx := 1.0 if corner.x <= box.get_center().x else -1.0
		var sy := 1.0 if corner.y <= box.get_center().y else -1.0
		draw_line(corner, corner + Vector2(arm * sx, 0), color, 3.0, true)
		draw_line(corner, corner + Vector2(0, arm * sy), color, 3.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)
