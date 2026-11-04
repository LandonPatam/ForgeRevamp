extends Control
## A repeated carousel slot shares its source's rendered face, not a new viewport.
const P = preload("res://scripts/ui/Palette.gd")
var source: Control
var deck_index := 0
var cycle := 0
var night_material: ShaderMaterial
var night_amount := 0.0
var night_center := -1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = source.size
	pivot_offset = size * 0.5
	night_material = ShaderMaterial.new()
	night_material.shader = preload("res://scripts/app/DiskNightLighting.gdshader")
	visibility_changed.connect(_ensure_source_face)
	_ensure_source_face.call_deferred()

func _ensure_source_face() -> void:
	if visible and is_instance_valid(source) and source.has_method("ensure_face"):
		source.ensure_face()
		queue_redraw()

func set_night_lighting(amount: float, center_strength: float) -> void:
	var changed := night_amount != amount
	night_amount = amount
	if night_material == null: return
	if changed: night_material.set_shader_parameter("night_amount", amount)
	if not is_equal_approx(night_center, center_strength):
		night_center = center_strength
		night_material.set_shader_parameter("center_strength", center_strength)
	var presentation: Material = night_material if amount > 0.0 else null
	if material != presentation: material = presentation

func _draw() -> void:
	if not is_instance_valid(source): return
	var shadow := P.box(source.shell_color.darkened(0.25), source.shell_color.darkened(0.4), 6, 0)
	shadow.shadow_color = Color(0.12, 0.16, 0.20, 0.24)
	shadow.shadow_size = 22 if source.selected else 12
	shadow.shadow_offset = Vector2(2, 20 if source.selected else 9)
	draw_style_box(shadow, Rect2(Vector2(3, 5), size - Vector2(5, 5)))
	if source.cover.texture != null: draw_texture_rect(source.cover.texture, Rect2(Vector2.ZERO, size), false)
