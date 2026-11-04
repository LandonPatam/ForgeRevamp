extends Control
## A sideways floppy. The same rendered face is used during physical insertion.
const P = preload("res://scripts/ui/Palette.gd")
const Appearance = preload("res://scripts/app/DeckAppearance.gd")
var deck: Dictionary = {}
var images: Node
var cover: TextureRect
var selected := false
var cover_hidden := false
var face_view: SubViewport
var face_material: ShaderMaterial
var shell_color := Color("c9a34e")
var night_material: ShaderMaterial
var night_amount := 0.0
var night_center := -1.0
## Carousel disks build their 512px face viewport (and request cover artwork)
## only once they, or a loop copy of them, first become visible. With Forge's
## precons listed, most disks start off-screen.
var lazy_face := false
# Stable deck identity chooses a retro plastic color, independent of its artwork.
const COLORS := Appearance.COLORS

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell_color = Appearance.color_for(deck)
	cover = TextureRect.new()
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(cover)
	night_material = ShaderMaterial.new()
	night_material.shader = preload("res://scripts/app/DiskNightLighting.gdshader")
	images.available.connect(func(key):
		var current: Dictionary = deck.get("cover", {})
		if face_view != null and key == current.get("key", ""): _set_artwork(images.request_texture(current)))
	resized.connect(_layout)
	_layout()
	if not lazy_face: ensure_face()
	else:
		visibility_changed.connect(_ensure_visible_face)
		# The carousel places (and hides) new disks in the same frame they are added.
		_ensure_visible_face.call_deferred()

func _ensure_visible_face() -> void:
	if visible: ensure_face()

func ensure_face() -> void:
	if face_view != null: return
	face_view = SubViewport.new()
	face_view.size = Vector2i(512, 512)
	face_view.disable_3d = true
	face_view.transparent_bg = true
	face_view.gui_disable_input = true
	face_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(face_view)
	face_material = ShaderMaterial.new()
	face_material.shader = preload("res://scripts/app/FloppyDisk.gdshader")
	face_material.set_shader_parameter("shell_color", shell_color)
	var face := ColorRect.new()
	face.size = Vector2(512, 512)
	face.material = face_material
	face_view.add_child(face)
	move_child(face_view, 0)
	cover.texture = face_view.get_texture()
	var data: Dictionary = deck.get("cover", {})
	if not data.is_empty(): _set_artwork(images.request_texture(data))
	if deck.get("create", false):
		var plus := Label.new()
		plus.text = "+"
		plus.position = Vector2(205, 70)
		plus.size = Vector2(260, 370)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plus.add_theme_font_size_override("font_size", 160)
		plus.add_theme_color_override("font_color", Color("355961"))
		face_view.add_child(plus)

func update_deck(value: Dictionary) -> void:
	var previous: Dictionary = deck.get("cover", {})
	deck = value
	refresh_color()
	if face_view == null:
		queue_redraw()
		return
	var current: Dictionary = deck.get("cover", {})
	if current.get("key", "") != previous.get("key", "") or current.get("imageKey", "") != previous.get("imageKey", ""):
		face_material.set_shader_parameter("has_artwork", false)
		face_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		if not current.is_empty(): _set_artwork(images.request_texture(current))
	queue_redraw()

func refresh_color() -> void:
	var next_color: Color = Appearance.color_for(deck)
	if shell_color == next_color: return
	shell_color = next_color
	if face_material != null:
		face_material.set_shader_parameter("shell_color", shell_color)
		face_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()

func _layout() -> void:
	if cover == null: return
	pivot_offset = size * 0.5
	cover.position = Vector2.ZERO
	cover.size = size
	queue_redraw()

func _set_artwork(texture: Texture2D) -> void:
	face_material.set_shader_parameter("has_artwork", texture != null)
	if texture != null:
		face_material.set_shader_parameter("artwork", texture)
	face_view.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw() -> void:
	if cover_hidden: return
	var shadow := P.box(shell_color.darkened(0.25), shell_color.darkened(0.4), 6, 0)
	if night_amount > 0.0:
		shadow.bg_color = shadow.bg_color.darkened(night_amount * 0.55)
		shadow.border_color = shadow.border_color.darkened(night_amount * 0.55)
	shadow.shadow_color = Color(0.12, 0.16, 0.20, 0.24)
	shadow.shadow_size = 22 if selected else 12
	shadow.shadow_offset = Vector2(2, 20 if selected else 9)
	draw_style_box(shadow, Rect2(Vector2(3, 5), size - Vector2(5, 5)))

func set_selected(value: bool) -> void:
	if selected == value: return
	selected = value
	queue_redraw()

func set_night_lighting(amount: float, center_strength: float) -> void:
	var changed := night_amount != amount
	if changed:
		night_amount = amount
		queue_redraw() # Cheap 2D contact shadow; never repaint face_view.
	if night_material == null: return
	if changed: night_material.set_shader_parameter("night_amount", amount)
	if not is_equal_approx(night_center, center_strength):
		night_center = center_strength
		night_material.set_shader_parameter("center_strength", center_strength)
	var presentation: Material = night_material if amount > 0.0 else null
	if cover.material != presentation: cover.material = presentation

func cover_rect() -> Rect2:
	return cover.get_global_rect()

func hide_cover(value: bool) -> void:
	cover_hidden = value
	cover.visible = not value
	queue_redraw()
