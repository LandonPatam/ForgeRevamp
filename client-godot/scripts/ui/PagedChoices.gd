extends VBoxContainer
## Keep complete choices accessible without scrollbars or clipped interactions.
var grid: GridContainer
var page := 0
var page_size := 6
var navigation: HBoxContainer
var previous: Button
var next: Button
var caption: Label
var filter_text := ""

func _ready() -> void:
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)
	navigation = HBoxContainer.new()
	navigation.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(navigation)
	previous = Button.new()
	previous.text = "Previous"
	previous.pressed.connect(func(): page -= 1; refresh())
	navigation.add_child(previous)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.custom_minimum_size.x = 130
	navigation.add_child(caption)
	next = Button.new()
	next.text = "Next"
	next.pressed.connect(func(): page += 1; refresh())
	navigation.add_child(next)
	grid.child_entered_tree.connect(func(_child): refresh.call_deferred())
	grid.child_exiting_tree.connect(func(_child): refresh.call_deferred())

func configure(columns: int, count: int) -> void:
	grid.columns = maxi(1, columns)
	page_size = maxi(1, count)
	refresh()

## Narrows the pages to children whose "search" meta contains the text.
func set_filter(text: String) -> void:
	filter_text = text.strip_edges().to_lower()
	page = 0
	refresh()

func matches() -> Array:
	return grid.get_children().filter(func(child): return filter_text.is_empty() or str(child.get_meta("search", "")).contains(filter_text))

func refresh() -> void:
	if not is_inside_tree(): return
	var matching := matches()
	var count := matching.size()
	var pages := maxi(1, ceili(float(count) / page_size))
	page = clampi(page, 0, pages - 1)
	# Assign only the final visibility. Hiding then re-showing every choice
	# needlessly invalidates container sizing on every layout refresh.
	var shown := {}
	for index in range(count):
		if index / page_size == page: shown[matching[index]] = true
	for child in grid.get_children(): child.visible = shown.has(child)
	navigation.visible = pages > 1 or count == 0
	previous.disabled = page == 0
	next.disabled = page == pages - 1
	caption.text = "No matches" if count == 0 else "Page %d / %d" % [page + 1, pages]
