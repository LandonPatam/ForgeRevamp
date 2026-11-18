extends Control
## Table animation director. Plays public happenings over the already-updated board:
## attack and block declarations, combat strikes, damage impacts and cards leaving the
## battlefield. Presentation only: it never answers Forge, never holds a decision back and
## never replays a session's earlier events (the first snapshot only primes what was seen).
## Each snapshot's new happenings form one beat; beats queue briefly and speed up instead of
## falling behind.
const Terminal = preload("res://scripts/ui/TerminalStyle.gd")

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

var card_view: Callable      ## id -> CardView on the table, or null
var portrait_view: Callable  ## seat -> PlayerAvatar, or null
var zone_point: Callable     ## (seat, zone) -> global point a departing card travels to

var primed := false
var last_fx_id := 0
var known_attackers: Dictionary = {}
var known_blocks: Dictionary = {}
var ghosts: Dictionary = {}          ## id -> {view, zone, seat}, kept alive until their beat ends
var pending_departures: Array = []   ## ghost ids that joined since the last beat was built
var offset_tweens: Dictionary = {}   ## view instance id -> Tween driving its fx_offset
var items: Array = []                ## transient drawn effects: numbers, flashes, rings, glyphs
var next_free := 0.0
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
	if not primed:
		primed = true
		return
	if not enabled():
		_release_departures()
		return
	if attacks.is_empty() and blocks.is_empty() and fresh.is_empty() and pending_departures.is_empty():
		return
	_play_beat(snapshot, attacks, blocks, fresh)

func _release_departures() -> void:
	for id in pending_departures:
		if ghosts.has(id):
			if is_instance_valid(ghosts[id].view): ghosts[id].view.queue_free()
			ghosts.erase(id)
	pending_departures.clear()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _play_beat(snapshot: Dictionary, attacks: Array, blocks: Array, fresh: Array) -> void:
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
	var impact_at := at
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
		impact_at = at + 0.21 * pace
	var hits := 0
	for event in fresh:
		if event.get("kind", "") != "damage": continue
		if _impact(event, impact_at, pace): hits += 1
	var leave_at := impact_at + (0.3 * pace if hits > 0 else 0.0)
	if hits > 0: length = maxf(length, impact_at - at + 0.3 * pace)
	for id in pending_departures:
		if ghosts.has(id):
			_leave(id, leave_at, pace)
			length = maxf(length, leave_at - at + 0.62 * pace)
	pending_departures.clear()
	next_free = now + at + length * 0.85

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
	_shake(view, "fx_offset", delay, 0.24 * pace, 6.0)
	_flash(view, delay, color, 0.3 * pace)
	var label := text
	if event.get("deathtouch", false): label += " DEATHTOUCH"
	_number(label, _center(view) + Vector2(0, -view.size.y * 0.18), delay, color, 30, pace)
	return true

func _shake(target: Object, property: String, delay: float, length: float, strength: float) -> void:
	var tween: Tween = _offset_tween(target) if property == "fx_offset" else target.create_tween()
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

func _flash(view: Control, delay: float, color: Color, length: float) -> void:
	items.append({"kind": "flash", "view": view, "start": clock + delay, "life": length, "color": color})
	set_process(true)

func _pulse_ring(at: Vector2, delay: float, color: Color, length: float) -> void:
	items.append({"kind": "ring", "at": at, "start": clock + delay, "life": length, "color": color})
	set_process(true)

func _number(text: String, at: Vector2, delay: float, color: Color, font_size: int, pace: float) -> void:
	items.append({"kind": "number", "text": text, "at": at, "start": clock + delay, "life": 0.95 * maxf(pace, 0.6), "color": color, "size": font_size})
	set_process(true)

func _burst(at: Vector2, area: Vector2, color: Color, drift: Vector2, count: int, pace: float) -> void:
	for i in range(count):
		var spot := at + Vector2(rng.randf_range(-0.4, 0.4) * area.x, rng.randf_range(-0.45, 0.45) * area.y)
		items.append({"kind": "glyph", "at": spot, "drift": drift * rng.randf_range(0.55, 1.0) + Vector2(rng.randf_range(-24, 24), rng.randf_range(-30, 10)),
			"text": GLYPHS[rng.randi_range(0, GLYPHS.length() - 1)], "start": clock + rng.randf() * 0.08, "life": rng.randf_range(0.45, 0.7) * maxf(pace, 0.6), "color": color})
	set_process(true)

func _process(delta: float) -> void:
	clock += delta
	items = items.filter(func(item): return clock < item.start + item.life)
	queue_redraw()
	if items.is_empty(): set_process(false)

func _draw() -> void:
	var to_local := get_global_transform().affine_inverse()
	var font := Terminal.font()
	for item in items:
		var t: float = (clock - item.start) / item.life
		if t < 0.0: continue
		match item.kind:
			"flash":
				var view: Control = item.view
				if not is_instance_valid(view): continue
				var tint: Color = item.color
				tint.a = 0.55 * (1.0 - t)
				draw_set_transform_matrix(to_local * view.get_global_transform() * Transform2D(0, view.fx_offset.rotated(-view.rotation)))
				var box := StyleBoxFlat.new()
				box.bg_color = tint
				box.set_corner_radius_all(int(maxf(4.0, view.size.x * 0.06)))
				box.anti_aliasing = true
				draw_style_box(box, Rect2(Vector2.ZERO, view.size))
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
				draw_string_outline(font, spot, item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now, 6, shade)
				draw_string(font, spot, item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_now, ink)
			"glyph":
				var ease_in := t * t
				var glyph: Color = item.color
				glyph.a = 1.0 - t
				draw_string(font, to_local * (item.at + item.drift * ease_in), item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, glyph)
