extends VBoxContainer
signal item_selected(value: Dictionary)
const Entry = preload("res://scripts/ui/StackFeedEntry.gd")
var entries: Dictionary = {}
var idle: Label
var clock := 0.0

func _ready() -> void:
	add_theme_constant_override("separation", 7)
	idle = Label.new()
	idle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	idle.custom_minimum_size.y = 54
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono"])
	idle.add_theme_font_override("font", font)
	idle.add_theme_font_size_override("font_size", 12)
	idle.add_theme_color_override("font_color", preload("res://scripts/ui/TerminalStyle.gd").MUTED)
	idle.text = "> SYSTEM IDLE\n  Awaiting activity."
	add_child(idle)

func present(items: Array) -> void:
	var ids: Array = items.map(func(item): return int(item.id))
	for id in entries.keys():
		if not ids.has(id):
			remove_child(entries[id])
			entries[id].queue_free()
			entries.erase(id)
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var id := int(item.id)
		if not entries.has(id):
			var entry := Entry.new()
			entry.item_selected.connect(func(value): item_selected.emit(value))
			add_child(entry)
			entries[id] = entry
		entries[id].present(item, index)
		move_child(entries[id], index)
	idle.visible = items.is_empty()
	set_process(items.is_empty())

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	clock += delta
	idle.text = (">" if int(clock*1.5)%2 == 0 else " ") + " SYSTEM IDLE\n  Awaiting activity."
