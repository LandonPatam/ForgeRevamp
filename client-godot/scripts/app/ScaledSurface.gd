extends SubViewportContainer
## Render the selected UI scale at the window's native resolution. The viewport owns
## logical coordinates and input conversion, including its embedded dialogs.
var ui_scale: float = preload("res://scripts/app/DisplayPreferences.gd").current():
	set(value):
		ui_scale = clampf(value, 1.0, 2.0)
		if viewport != null: sync_size()
var viewport: SubViewport
var input_top := 0.0
var full_input := false
# Zooms borrow this texture before the UI itself is visible. Ordinary hidden
# editors/parked games can stop drawing without changing their logic/networking.
var render_when_hidden := false:
	set(value):
		render_when_hidden = value
		_sync_rendering()

func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.gui_embed_subwindows = true
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	resized.connect(sync_size)

func _ready() -> void:
	visibility_changed.connect(_sync_rendering)
	sync_size()
	_sync_rendering()

func _sync_rendering() -> void:
	if viewport == null: return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if render_when_hidden or is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func sync_size() -> void:
	viewport.size_2d_override = Vector2i((size / ui_scale).floor()).max(Vector2i.ONE)
	for child in viewport.get_children():
		if child is Control: _fit_content(child)

func _fit_content(control: Control) -> void:
	# Full-rect anchors plus a deferred size can retain negative offsets when
	# native allocation and logical sizing arrive in different resize frames.
	# Own the root size explicitly; its descendants retain normal Control layout.
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE)
	control.size = Vector2(viewport.size_2d_override)

func attach(control: Control) -> void:
	sync_size()
	_fit_content(control)
	viewport.add_child(control)

func set_workspace_top(value: float) -> void:
	input_top = value

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not is_visible_in_tree(): return
	var focus := viewport.gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit) or not focus.is_visible_in_tree(): return
	# The outer viewport can retain carousel focus while this viewport edits text.
	# Deliver keys before the outer GUI can use them for deck navigation.
	viewport.push_input(event, true)
	get_viewport().set_input_as_handled()

func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point) and (full_input or point.y >= input_top)
