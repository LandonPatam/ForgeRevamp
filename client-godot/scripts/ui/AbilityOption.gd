extends Button
const Rules = preload("res://scripts/ui/AbilityText.gd")
var description := ""
var effect_view: Control
var cost_view: Control

static func parts(label: String) -> Dictionary:
	var full := label.strip_edges()
	# Direct mana variants retain their engine option index and chosen color.
	for color in preload("res://scripts/ui/ManaCounter.gd").NAMES:
		if full.begins_with(color + " — "): full = full.substr(color.length() + 3)
	var colon := full.find(":")
	var cost := full.substr(0, colon).strip_edges() if colon >= 0 else ""
	var effect := full.substr(colon + 1).strip_edges() if colon >= 0 else full
	if effect == "Add {C}.": effect = "Add {C} (one colorless mana)."
	return {"cost": cost, "effect": effect}

func _ready() -> void:
	text = ""
	var content := MarginContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("margin_left", 16)
	content.add_theme_constant_override("margin_right", 16)
	content.add_theme_constant_override("margin_top", 10)
	content.add_theme_constant_override("margin_bottom", 10)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(column)
	var details := parts(description)
	effect_view = Rules.new()
	effect_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_view.text = details.effect
	column.add_child(effect_view)
	cost_view = Rules.new()
	cost_view.text = "Cost: " + details.cost if not details.cost.is_empty() else ""
	cost_view.font_size = 14
	cost_view.ink = Color("c0c8cf")
	cost_view.visible = not details.cost.is_empty()
	column.add_child(cost_view)
	column.minimum_size_changed.connect(func(): custom_minimum_size.y = column.get_combined_minimum_size().y + 20)
	custom_minimum_size.y = column.get_combined_minimum_size().y + 20

func _process(delta: float) -> void:
	if effect_view == null: return
	for view in [effect_view, cost_view]:
		view.glow = move_toward(view.glow, 1.0 if is_hovered() and not disabled else 0.0, delta * 5)
		view.queue_redraw()
