extends VBoxContainer
const P = preload("res://scripts/ui/Palette.gd")
var compact := false
var heading: Label
var detail: Label
var progress: ProgressBar
var elapsed: Label
var steps: Array[Label] = []
var started := 0
var failed := false

func _ready() -> void:
	started = Time.get_ticks_msec()
	add_theme_constant_override("separation", 16 if not compact else 10)
	heading = Label.new()
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 25 if not compact else 20)
	add_child(heading)
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", P.MUTED)
	add_child(detail)
	progress = ProgressBar.new()
	progress.indeterminate = true
	progress.show_percentage = false
	progress.custom_minimum_size.y = 10
	progress.add_theme_stylebox_override("background", P.box(Color("303236"), Color("494e53"), 5, 0))
	progress.add_theme_stylebox_override("fill", P.box(Color("127d99"), Color.TRANSPARENT, 5, 0))
	add_child(progress)
	if not compact:
		for text in ["Load Forge and card database", "Build the card catalog", "Open your saved decks"]:
			var step := Label.new()
			step.text = text
			step.add_theme_font_size_override("font_size", 15)
			steps.append(step)
			add_child(step)
	elapsed = Label.new()
	elapsed.add_theme_font_size_override("font_size", 13)
	elapsed.add_theme_color_override("font_color", P.MUTED)
	add_child(elapsed)
	present("Starting Forge", "Preparing the game library. This can take a minute.", "starting")

func present(title: String, message: String, stage: String) -> void:
	heading.text = title
	detail.text = message
	failed = stage == "failed"
	heading.modulate = Color("ff9b91") if failed else Color.WHITE
	progress.visible = not failed
	var active: int = {"starting": -1, "cards": 0, "catalog": 1, "connecting": 2, "ready": 2}.get(stage, -1)
	for i in range(steps.size()):
		var text: String = ["Load Forge and card database", "Build the card catalog", "Open your saved decks"][i]
		steps[i].text = ("✓  " if i < active else ("›  " if i == active else "    ")) + text
		steps[i].modulate = P.MINT if i < active else (Color.WHITE if i == active else Color("929ca3"))

func _process(_delta: float) -> void:
	if elapsed == null or failed or not is_visible_in_tree(): return
	var seconds := int((Time.get_ticks_msec() - started) / 1000)
	elapsed.text = "Elapsed: %d:%02d" % [seconds / 60, seconds % 60]
