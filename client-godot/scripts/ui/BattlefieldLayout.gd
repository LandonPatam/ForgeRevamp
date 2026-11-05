extends RefCounted
## Table settings: distance between cards in a pile (at a 200px-wide card) and whether a
## tapped pile card turns aside, uncovering more of the cards behind it.
static var pile_step := 26.0
static var tap_aside := false

## Full-size packing: wrap when useful, then overlap only as much as needed.
static func arrange(values: Array, bounds: Vector2, card_size: Vector2, gap: float, group_duplicates: bool) -> Dictionary:
	var units: Array = groups(values, group_duplicates)
	var height := 0.0
	for unit in units:
		unit.footprint = _footprint(unit.cards, card_size)
		var ratio := card_size.x / 200.0
		unit.offset = minf(pile_step * ratio, minf(pile_reach() * ratio, maxf(0, bounds.x - unit.footprint.x) * 0.5) / maxf(1, unit.cards.size() - 1))
		unit.width = unit.footprint.x + unit.offset * (unit.cards.size() - 1)
		height = maxf(height, unit.footprint.y)
	return pack(units, bounds, card_size, gap, height)

## A pile reserves room for a sideways card and its small tap offset without moving neighbors.
static func _footprint(unit_cards: Array, card_size: Vector2) -> Vector2:
	if unit_cards.size() > 1: return Vector2(card_size.y + (card_size.x * 0.5 if tap_aside else 0.0), card_size.y)
	return Vector2(card_size.y, card_size.x) if unit_cards[0].get("tapped", false) else card_size

## Align sideways cards with the pile's bottom, exposing the upright cards' top edges.
static func pile_tap_offset(card: Dictionary, count: int, card_size: Vector2) -> Vector2:
	if count <= 1 or not card.get("tapped", false): return Vector2.ZERO
	return Vector2(card_size.x * 0.5 if tap_aside else 0.0, (card_size.y - card_size.x) * 0.5)

## Widest a pile may fan before its cards overlap more tightly.
static func pile_reach() -> float:
	return maxf(64.0, pile_step * 4.0)

## Identity of a stackable permanent: matching keys are identical visible game states, apart from
## tapping, since a tapped card turns in place within its pile.
## Empty when the card can never join a pile (hidden, face-down, attached, unnamed).
static func stack_key(card: Dictionary) -> String:
	if card.get("hidden", false) or card.get("faceDown", false) or card.has("attachedTo") or str(card.get("name", "")).is_empty():
		return ""
	return str([card.get("name", ""), card.get("typeLine", ""), card.get("counters", {}), card.get("stats", ""), card.get("sick", false), card.get("damage", 0), card.get("keywords", []), card.get("text", ""), card.get("weakSelection", 0), card.get("commander", false), card.get("token", false), card.get("chosenColors", [])])

static func groups(values: Array, group_duplicates: bool) -> Array:
	var units: Array = []
	var duplicate_groups: Dictionary = {}
	for card in values:
		var key := ""
		if group_duplicates and not card.get("separate", false):
			key = stack_key(card)
		if not key.is_empty() and duplicate_groups.has(key):
			units[duplicate_groups[key]].cards.append(card)
		else:
			if not key.is_empty(): duplicate_groups[key] = units.size()
			units.append({"cards": [card]})
	return units

static func fit_card_size(values: Array, bounds: Vector2, base: Vector2, gap: float) -> Vector2:
	var units := groups(values, true)
	if units.is_empty(): return base
	var height := 0.0
	for unit in units:
		var footprint := _footprint(unit.cards, base)
		unit.width = footprint.x + minf(pile_reach(), pile_step * (unit.cards.size() - 1))
		height = maxf(height, footprint.y)
	var best := 0.0
	for candidate in range(1, units.size() + 1):
		var columns := int(ceil(float(units.size()) / candidate))
		var rows := int(ceil(float(units.size()) / columns))
		var factor := minf(1, (bounds.y - gap * (rows - 1)) / (height * rows))
		for row_index in range(rows):
			var band := units.slice(row_index * columns, (row_index + 1) * columns)
			var width := 0.0
			for unit in band: width += unit.width
			factor = minf(factor, (bounds.x - gap * (band.size() - 1)) / width)
		best = maxf(best, factor)
	# Hover retains the large readable preview; extreme crowds can still overlap.
	return base * clampf(best, 0.5, 1.0)

static func pack(units: Array, bounds: Vector2, card_size: Vector2, gap: float, height: float) -> Dictionary:
	var positions: Dictionary = {}
	var order: Array = []
	var counts: Dictionary = {}
	if units.is_empty(): return {"positions": positions, "order": order, "counts": counts}
	var max_rows := maxi(1, 1 + int(maxf(0, bounds.y - height) / 32))
	var row_count := 1
	var best_score := -1.0
	var widest := 0.0
	for unit in units: widest = maxf(widest, unit.width)
	for candidate in range(1, mini(units.size(), max_rows) + 1):
		var columns := int(ceil(float(units.size()) / candidate))
		var actual_rows := int(ceil(float(units.size()) / columns))
		var clean_fit := actual_rows * height + gap * (actual_rows - 1) <= bounds.y + 0.1
		for row_index in range(actual_rows):
			var band := units.slice(row_index * columns, (row_index + 1) * columns)
			var width := gap * (band.size() - 1)
			for unit in band: width += unit.width
			clean_fit = clean_fit and width <= bounds.x + 0.1
		if clean_fit:
			row_count = actual_rows
			break
		var horizontal := 1.0 if columns == 1 else minf(1, maxf(0, bounds.x - widest) / (columns - 1) / widest)
		# A visible title strip plus hover is useful even when rows must overlap.
		var vertical := 1.0 if actual_rows == 1 else minf(1, maxf(0, bounds.y - height) / (actual_rows - 1) / height * 2.5)
		var score := minf(horizontal, vertical)
		if score > best_score:
			best_score = score
			row_count = actual_rows
	var per_row := int(ceil(float(units.size()) / row_count))
	row_count = int(ceil(float(units.size()) / per_row))
	var y_step := minf(height + gap, maxf(0, bounds.y - height) / maxf(1, row_count - 1))
	for row_index in range(row_count):
		var band := units.slice(row_index * per_row, (row_index + 1) * per_row)
		var cursor := 0.0
		var compression := 1.0
		for unit in band:
			unit.start = cursor
			if cursor > 0:
				compression = minf(compression, maxf(0, bounds.x - unit.width) / cursor)
			cursor += unit.width + gap
		for unit in band:
			if unit.cards.size() > 1:
				counts[unit.cards.back().id] = unit.cards.size()
			for i in range(unit.cards.size()):
				var card: Dictionary = unit.cards[i]
				var envelope := Vector2(unit.start * compression + unit.offset * i, row_index * y_step + (height - unit.footprint.y) * 0.5)
				positions[card.id] = envelope + (unit.footprint - card_size) * 0.5 + pile_tap_offset(card, unit.cards.size(), card_size)
				order.append(card.id)
	return {"positions": positions, "order": order, "counts": counts}
