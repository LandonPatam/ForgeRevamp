extends Node3D
signal disk_entering
## Original procedural hardware, with a real viewport displayed on the monitor.
const SCREEN_SIZE := Vector2(2.48, 1.83)
const SCREEN_CENTER := Vector3(0, 1.30, 0.655)
const CRT_BULGE := 0.065
# Center the fitted slot between the SETTINGS well's right edge (-0.34)
# and the flat fascia's right edge (1.535). Z remains the feed direction.
const DRIVE_CENTER := Vector3(0.5975, -0.39, 0.83)
const DRIVE_OUTLINE: Array[Vector2] = [Vector2(1.1275, -0.32), Vector2(0.0675, -0.32), Vector2(0.0675, -0.46), Vector2(1.1275, -0.46)]
const DRIVE_FACE_Z := 0.88
const DRIVE_BEVEL_DEPTH := 0.0335
const DRIVE_INSET := 0.036
const DRIVE_EDGE_RADIUS := 0.010
const DRIVE_INNER_RADIUS := 0.004
const DRIVE_THROAT_Z := 0.715
const DRIVE_WALL_DEPTH := DRIVE_FACE_Z - DRIVE_BEVEL_DEPTH - DRIVE_THROAT_Z + 0.045
const DRIVE_ROTATION := Quaternion(-0.5, -0.5, -0.5, 0.5)
var camera: Camera3D
var screen: MeshInstance3D
var screen_material: ShaderMaterial
var crt_material: ShaderMaterial
var zoom_material: ShaderMaterial
var disk: Node3D
var disk_face: MeshInstance3D
var disk_body: MeshInstance3D
var led: MeshInstance3D
var drive_door: Node3D
var drive_bevel_angle := 0.0
var home_transform: Transform3D
var animation: Tween
var channel_animation: Tween
var working := false
var drive_log_active := false
var drive_format_active := false
var label_erase := 0.0
var drive_activity := 0.0
var drive_pulses := 0
var launch_generation := 0
var surface_materials: Dictionary = {}
var surface_grain: NoiseTexture2D
var surface_mottle: NoiseTexture2D
var surface_roughness: NoiseTexture2D
const PLAY_CENTER := Vector3(-1.04, -0.39, 0.858)
const SETTINGS_CENTER := Vector3(-0.49, -0.39, 0.858)
const KEY_HEIGHT := 0.235
const KEY_DEPTH := 0.052
const KEY_TRAVEL := 0.028
const KEY_MIN_PRESS_SECONDS := 0.06
const CASE_PLASTIC := Color("aeb3b6")
const KEY_PLASTIC := CASE_PLASTIC
const KEY_INK := Color("414141")
const KEY_LED := Color("65e0d5")
var settings_key: Node3D
var settings_icon: MeshInstance3D
var play_key: Node3D
var play_legend: Label3D
var play_arrow: MeshInstance3D
var play_cap: MeshInstance3D
var settings_cap: MeshInstance3D
var play_activity_led: MeshInstance3D
var play_cap_material: StandardMaterial3D
var settings_cap_material: StandardMaterial3D
var play_hover := false
var settings_hover := false
var play_hover_animation: Tween
var settings_hover_animation: Tween
var settings_animation: Tween
var play_held := false
var settings_held := false
var play_feedback_pending := false
var settings_feedback_pending := false
var play_down_at := 0
var settings_down_at := 0
var play_animation: Tween
var play_enabled := false
var room_environment: Environment
var room_key: DirectionalLight3D
var room_fill: OmniLight3D
var monitor_light: OmniLight3D
var night_rim: DirectionalLight3D
var room_floor: MeshInstance3D
var night_floor_material: ShaderMaterial
var room_darkness := 0.0
var disk_day_material: StandardMaterial3D
var disk_night_material: ShaderMaterial
var floor_material: StandardMaterial3D

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	room_environment = settings
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("d9dfe2")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d7d9dc")
	settings.ambient_light_energy = 0.62
	environment.environment = settings
	add_child(environment)
	var key := DirectionalLight3D.new()
	room_key = key
	key.rotation_degrees = Vector3(-48, -32, 0)
	key.light_energy = 0.65
	key.shadow_enabled = false
	add_child(key)
	var fill := OmniLight3D.new()
	room_fill = fill
	fill.position = Vector3(-4, 3, 5)
	fill.light_energy = 0.35
	fill.omni_range = 12
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	room_floor = floor_mesh
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -1.09
	floor_mesh.material_override = _material(settings.background_color, 0.9, true)
	floor_material = floor_mesh.material_override
	add_child(floor_mesh)
	# Daylight retains its original unshaded material. At night the same floor
	# receives real spill, crossfading its emission/albedo with the room switch.
	night_floor_material = ShaderMaterial.new()
	var floor_shader := Shader.new()
	floor_shader.code = """shader_type spatial;
render_mode ambient_light_disabled, specular_disabled;
uniform float night_amount = 0.0;
uniform vec4 day_color : source_color = vec4(0.85098, 0.87451, 0.88627, 1.0);
uniform vec4 night_base : source_color = vec4(0.06667, 0.09020, 0.09804, 1.0);
void fragment() {
    ALBEDO = vec3(0.055, 0.070, 0.075) * night_amount;
    EMISSION = mix(day_color.rgb, night_base.rgb, night_amount);
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
void light() {
    // The distant floor matches the environment; only local spill adds light.
    // Directional/ambient illumination must not reveal a horizon during zoom.
    if (!LIGHT_IS_DIRECTIONAL) {
        DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR;
    }
}"""
	night_floor_material.shader = floor_shader
	var shadow := MeshInstance3D.new()
	var shadow_plane := PlaneMesh.new()
	shadow_plane.size = Vector2(4.5, 2.8)
	shadow.mesh = shadow_plane
	shadow.position = Vector3(0.12, -1.075, 0.12)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.13, 0.23, 0.28, 0.42))
	gradient.set_color(1, Color(0.13, 0.23, 0.28, 0))
	var shadow_texture := GradientTexture2D.new()
	shadow_texture.gradient = gradient
	shadow_texture.fill = GradientTexture2D.FILL_RADIAL
	shadow_texture.fill_from = Vector2(0.5, 0.5)
	shadow_texture.fill_to = Vector2(1, 0.5)
	var shadow_material := _material(Color.WHITE, 1, true)
	shadow_material.albedo_texture = shadow_texture
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.material_override = shadow_material
	add_child(shadow)
	_build_case()
	screen = MeshInstance3D.new()
	screen.mesh = _crt_mesh()
	screen.position = SCREEN_CENTER
	# A slight glass treatment fades away completely during the fullscreen zoom.
	var display_source := """uniform sampler2D display_texture : source_color, filter_linear;
uniform float clean_view = 0.0;
uniform float night_amount = 0.0;
uniform float physical_glass = 0.0;
uniform float projection_blend = 0.0;
uniform sampler2D channel_texture : source_color, filter_linear;
uniform float channel_progress = -1.0;
uniform float reveal_progress = -1.0;
uniform bool grid_preview = false;
void vertex() {
    vec2 q = UV * 2.0 - 1.0;
    VERTEX.z += 0.065 * max(1.0 - clean_view, physical_glass) * (1.0 - q.x * q.x) * (1.0 - q.y * q.y);
}
float signal_noise(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void fragment() {
#ifdef EXPANDING_DISPLAY
    ALPHA = 1.0;
#endif
    float curvature = max(1.0 - clean_view, physical_glass);
    float radius = 0.065 * curvature;
    vec2 tube_uv = UV - vec2(0.5);
    vec2 bowed_uv = tube_uv * (vec2(1.0) + vec2(0.018 * pow(tube_uv.y * 2.0, 2.0), 0.032 * pow(tube_uv.x * 2.0, 2.0)) * curvature);
    vec2 q = abs(bowed_uv) - vec2(0.5 - radius);
    float distance_to_edge = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    if (distance_to_edge > 0.0) { discard; }
    vec2 display_uv = mix(UV, SCREEN_UV, projection_blend);
    vec3 color = texture(display_texture, display_uv).rgb;
    // Viewport textures have no mipmaps. Integrate the grid over this screen
    // pixel's footprint instead of letting subpixel lines vanish in bands.
    if (grid_preview && clean_view < 0.999) {
        vec2 dx = dFdx(display_uv);
        vec2 dy = dFdy(display_uv);
        vec3 filtered = vec3(0.0);
        for (int y = 0; y < 4; y++) {
            for (int x = 0; x < 4; x++) {
                vec2 offset = (vec2(float(x), float(y)) + 0.5) / 4.0 - 0.5;
                filtered += texture(display_texture, clamp(display_uv + dx * offset.x + dy * offset.y, vec2(0.0), vec2(1.0))).rgb;
            }
        }
        color = mix(filtered / 16.0, color, smoothstep(0.85, 1.0, clean_view));
    }
    if (reveal_progress >= 0.0) {
        float p = reveal_progress;
        vec2 cell = floor(UV * vec2(42.0, 30.0));
        float arrival = UV.y * 0.69 + signal_noise(cell) * 0.17;
        float visible_cell = smoothstep(arrival, arrival + 0.14, p * 1.12);
        vec2 coarse_uv = (floor(UV * vec2(84.0, 60.0)) + 0.5) / vec2(84.0, 60.0);
        vec2 forming_uv = mix(coarse_uv, UV, smoothstep(0.35, 0.92, p));
        // Quantizing thin grid lines produces large false blocks. Reveal the
        // filtered, continuous grid while retaining the phosphor arrival sweep.
        vec3 forming_board = grid_preview ? color : texture(display_texture, forming_uv).rgb;
        vec3 phosphor = vec3(0.008, 0.022, 0.021);
        color = mix(phosphor, forming_board, visible_cell);
        color += vec3(0.11, 0.36, 0.32) * visible_cell * (1.0 - visible_cell);
        float sweep = exp(-pow((UV.y - (p * 1.25 - 0.08)) / 0.012, 2.0));
        color += vec3(0.10, 0.30, 0.27) * sweep * sin(p * 3.14159265);
    }
    if (channel_progress >= 0.0) {
        float p = channel_progress;
        float envelope = sin(p * 3.14159265);
        float tracking = exp(-pow((UV.y - (-0.15 + p * 1.3)) / 0.055, 2.0));
        vec2 tuned_uv = display_uv;
        tuned_uv.x += (sin(UV.y * 94.0 + p * 130.0) * 0.008 + tracking * 0.045) * envelope;
        tuned_uv.y = fract(UV.y + sin(p * 13.0) * 0.045 * envelope);
        vec3 old_channel = texture(display_texture, clamp(tuned_uv, vec2(0.0), vec2(1.0))).rgb;
        vec3 new_channel = texture(channel_texture, clamp(tuned_uv, vec2(0.0), vec2(1.0))).rgb;
        color = mix(old_channel, new_channel, smoothstep(0.40, 0.62, p));
        float snow = signal_noise(floor(UV * vec2(520.0, 380.0)) + floor(p * 38.0));
        color = mix(color, vec3(snow) * vec3(0.65, 0.90, 0.86), envelope * (0.30 + tracking * 0.24));
        color += vec3(0.10, 0.22, 0.20) * tracking * envelope;
    }
    if (!grid_preview && clean_view < 0.999 && channel_progress < 0.0 && reveal_progress < 0.0) {
        vec2 pixel = 1.5 / vec2(textureSize(display_texture, 0));
        vec3 phosphor = (texture(display_texture, display_uv + vec2(pixel.x, 0.0)).rgb
                      + texture(display_texture, display_uv - vec2(pixel.x, 0.0)).rgb
                      + texture(display_texture, display_uv + vec2(0.0, pixel.y)).rgb
                      + texture(display_texture, display_uv - vec2(0.0, pixel.y)).rgb) * 0.25;
        color += max(phosphor - vec3(0.035), vec3(0.0)) * 0.10 * (1.0 - clean_view);
    }
    float scan = 1.0 - 0.045 * (0.5 + 0.5 * sin(UV.y * 360.0 * 3.14159));
    float vignette = 1.0 - 0.14 * length((UV - vec2(0.5)) * 1.4);
    float edge = smoothstep(0.0, 0.035, -distance_to_edge);
	vec3 glass = mix(vec3(0.035, 0.055, 0.055), color * scan * vignette, edge);
    float reflection = pow(max(0.0, 1.0 - length((UV - vec2(0.28, 0.08)) * vec2(0.8, 2.2))), 7.0) * 0.065;
    reflection += exp(-pow((UV.y - (0.10 + 0.09 * pow(UV.x - 0.45, 2.0))) / 0.028, 2.0)) * 0.012;
    ALBEDO = mix(glass + reflection, color, clean_view);
    EMISSION = color * edge * night_amount * 0.10 * (1.0 - clean_view);
}"""
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\n" + display_source
	screen_material = ShaderMaterial.new()
	screen_material.shader = shader
	crt_material = screen_material
	# During expansion the display must cover the bezel smoothly. Render it
	# after opaque hardware, without depth clipping; keep normal CRT depth at rest.
	var expanding_shader := Shader.new()
	expanding_shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;\n#define EXPANDING_DISPLAY\n" + display_source
	zoom_material = ShaderMaterial.new()
	zoom_material.shader = expanding_shader
	zoom_material.render_priority = 1
	screen.material_override = screen_material
	add_child(screen)
	monitor_light = OmniLight3D.new()
	monitor_light.position = SCREEN_CENTER + Vector3(0, -0.20, 1.0)
	monitor_light.light_color = Color("72dfcf")
	monitor_light.light_energy = 0.0
	monitor_light.omni_range = 4.0
	monitor_light.omni_attenuation = 1.6
	monitor_light.shadow_enabled = false
	add_child(monitor_light)
	night_rim = DirectionalLight3D.new()
	night_rim.rotation_degrees = Vector3(-38, 150, 0)
	night_rim.light_color = Color("879cbe")
	night_rim.light_energy = 0.0
	night_rim.shadow_enabled = false
	add_child(night_rim)
	_build_drive()
	_build_play_button()
	_build_settings_button()
	disk = Node3D.new()
	add_child(disk)
	disk_body = MeshInstance3D.new()
	disk_body.mesh = _floppy_body()
	disk.add_child(disk_body)
	disk_face = MeshInstance3D.new()
	var face := QuadMesh.new()
	face.size = Vector2.ONE
	disk_face.mesh = face
	disk_face.position.z = 0.022
	disk.add_child(disk_face)
	disk.hide()
	camera = Camera3D.new()
	# A longer lens keeps the front close to square while revealing the top deck.
	camera.position = Vector3(0.18, 4.8, 20.5)
	camera.fov = 16.5
	camera.near = 0.05
	add_child(camera)
	camera.look_at(Vector3(0, 0.02, 0))
	camera.make_current()
	home_transform = camera.transform

func _build_play_button() -> void:
	_build_key_well(PLAY_CENTER, Vector2(0.52, KEY_HEIGHT), "Play")
	play_key = Node3D.new()
	play_key.name = "PlayKey"
	play_key.position = PLAY_CENTER
	add_child(play_key)
	play_cap = _molded_keycap(Vector2(0.52, KEY_HEIGHT), play_key)
	play_cap_material = play_cap.material_override
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(tool, Vector3(-0.187, -0.036, 0.0266), Vector3(-0.122, 0, 0.0266), Vector3(-0.187, 0.036, 0.0266))
	tool.generate_normals()
	play_arrow = MeshInstance3D.new()
	play_arrow.mesh = tool.commit()
	play_arrow.material_override = _material(KEY_INK, 0.98)
	play_key.add_child(play_arrow)
	play_legend = Label3D.new()
	play_legend.text = "P L A Y"
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Arial Narrow", "Roboto Condensed", "Liberation Sans Narrow", "Arial"])
	font.font_stretch = 75
	font.font_weight = 600
	play_legend.font = font
	play_legend.font_size = 64
	play_legend.pixel_size = 0.00078
	play_legend.outline_size = 0
	play_legend.modulate = KEY_INK
	play_legend.shaded = true
	play_legend.position = Vector3(0.055, -0.003, 0.0268)
	play_key.add_child(play_legend)
	play_activity_led = _box(Vector3(0.018, 0.018, 0.003), Vector3(0.215, 0.073, 0.027), Color("263035"), 0.008, play_key)
	play_activity_led.material_override = _material(Color("263035"), 0.95, true)
	set_play_enabled(false)

func set_play_enabled(value: bool) -> void:
	play_enabled = value
	if play_cap_material == null: return
	if not play_held and (play_animation == null or not play_animation.is_running()):
		play_cap_material.albedo_color = _key_rest_color(true)

func _build_settings_button() -> void:
	_build_key_well(SETTINGS_CENTER, Vector2(0.26, KEY_HEIGHT), "Settings")
	settings_key = Node3D.new()
	settings_key.name = "SettingsKey"
	settings_key.position = SETTINGS_CENTER
	add_child(settings_key)
	settings_cap = _molded_keycap(Vector2(0.26, KEY_HEIGHT), settings_key)
	settings_cap_material = settings_cap.material_override
	var outline: Array[Vector2] = []
	for tooth in range(6):
		for point in [Vector2(-0.5, 0.049), Vector2(-0.34, 0.049), Vector2(-0.32, 0.070), Vector2(0.32, 0.070), Vector2(0.34, 0.049)]:
			var angle: float = (tooth + point.x) * TAU / 6.0
			outline.append(Vector2(cos(angle), sin(angle)) * point.y)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(outline.size()):
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		var inner_a := a.normalized() * 0.023
		var inner_b := b.normalized() * 0.023
		_tri(tool, Vector3(a.x, a.y, 0.0266), Vector3(b.x, b.y, 0.0266), Vector3(inner_b.x, inner_b.y, 0.0266))
		_tri(tool, Vector3(a.x, a.y, 0.0266), Vector3(inner_b.x, inner_b.y, 0.0266), Vector3(inner_a.x, inner_a.y, 0.0266))
	tool.generate_normals()
	settings_icon = MeshInstance3D.new()
	settings_icon.mesh = tool.commit()
	settings_icon.material_override = _material(KEY_INK, 0.98)
	settings_key.add_child(settings_icon)

func _molded_keycap(dimensions: Vector2, parent: Node3D) -> MeshInstance3D:
	# Straight walls, a narrow 45-degree chamfer, and a flat matte top.
	var profiles := [
		_contour(dimensions - Vector2.ONE * 0.008, Vector2.ZERO, 0.006, -KEY_DEPTH * 0.5),
		_contour(dimensions, Vector2.ZERO, 0.012, -0.020),
		_contour(dimensions, Vector2.ZERO, 0.012, 0.020),
		_contour(dimensions - Vector2.ONE * 0.012, Vector2.ZERO, 0.006, KEY_DEPTH * 0.5)]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for layer in range(profiles.size() - 1):
		for index in range(profiles[layer].size()):
			var next: int = (index + 1) % profiles[layer].size()
			_tri(tool, profiles[layer][index], profiles[layer][next], profiles[layer + 1][next])
			_tri(tool, profiles[layer][index], profiles[layer + 1][next], profiles[layer + 1][index])
	for index in range(profiles[0].size()):
		var next: int = (index + 1) % profiles[0].size()
		_tri(tool, Vector3(0, 0, -KEY_DEPTH * 0.5), profiles[0][next], profiles[0][index])
		_tri(tool, Vector3(0, 0, KEY_DEPTH * 0.5), profiles[3][index], profiles[3][next])
	tool.generate_normals()
	var cap := MeshInstance3D.new()
	cap.name = "MoldedKeycap"
	cap.mesh = tool.commit()
	var material := _case_material().duplicate() as StandardMaterial3D
	cap.material_override = material
	parent.add_child(cap)
	return cap

func _build_key_well(center: Vector3, dimensions: Vector2, tag: String) -> void:
	var point := Vector2(center.x, center.y)
	var outer := dimensions + Vector2.ONE * 0.040
	var opening := dimensions + Vector2.ONE * 0.028
	_ring(_contour(outer, point, 0.001, 0.88), _contour(outer, point, 0.016, 0.88), _case_material())
	_loft([_contour(outer, point, 0.016, 0.88), _contour(opening, point, 0.014, 0.869)], _case_material())
	_loft([_contour(opening, point, 0.014, 0.869), _contour(opening, point, 0.014, 0.799)], _surface_material(Color("343735"), 0.98, 0.06))
	var backing := _box(Vector3(opening.x, opening.y, 0.008), Vector3(center.x, center.y, 0.795), Color("202526"), 0.012)
	backing.name = tag + "PocketBacking"
	backing.material_override = _material(Color("202526"), 0.98)
	# A baked contact gradient keeps the narrow seam shaded in the GL renderer.
	# It respects depth: the proud cap occludes it, while the gap stays dark.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profiles := [_contour(outer, point, 0.016, 0.8804), _contour(dimensions + Vector2.ONE * 0.024, point, 0.014, 0.8804), _contour(dimensions + Vector2.ONE * 0.003, point, 0.012, 0.8804)]
	var opacity := [0.0, 0.32, 0.68]
	for layer in range(2):
		for index in range(profiles[layer].size()):
			var next: int = (index + 1) % profiles[layer].size()
			for corner in [Vector2i(layer, index), Vector2i(layer, next), Vector2i(layer + 1, next), Vector2i(layer, index), Vector2i(layer + 1, next), Vector2i(layer + 1, index)]:
				tool.set_color(Color(0.03, 0.035, 0.035, opacity[corner.x]))
				tool.add_vertex(profiles[corner.x][corner.y])
	tool.generate_normals()
	var contact := MeshInstance3D.new()
	contact.name = tag + "ContactShadow"
	contact.mesh = tool.commit()
	var shadow := _material(Color.WHITE, 1.0, true)
	shadow.vertex_color_use_as_albedo = true
	shadow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	contact.material_override = shadow
	contact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(contact)

func _key_rest_color(is_play: bool) -> Color:
	var hot := play_hover and play_enabled if is_play else settings_hover
	return KEY_PLASTIC.lightened(0.025) if hot else KEY_PLASTIC.darkened(0.025 if is_play and not play_enabled else 0.0)

func set_key_hover(is_play: bool, hot: bool) -> void:
	if not hot and (play_held if is_play else settings_held): end_key_press(is_play, true)
	if is_play:
		play_hover = hot
		if play_held: return
		if play_animation != null and play_animation.is_running(): return
		if play_hover_animation != null: play_hover_animation.kill()
		play_hover_animation = create_tween()
		play_hover_animation.tween_property(play_cap_material, "albedo_color", _key_rest_color(true), 0.08)
	else:
		settings_hover = hot
		if settings_held: return
		if settings_animation != null and settings_animation.is_running(): return
		if settings_hover_animation != null: settings_hover_animation.kill()
		settings_hover_animation = create_tween()
		settings_hover_animation.tween_property(settings_cap_material, "albedo_color", _key_rest_color(false), 0.08)

func begin_key_press(is_play: bool) -> void:
	if (play_held if is_play else settings_held): return
	var key := play_key if is_play else settings_key
	var rest := PLAY_CENTER if is_play else SETTINGS_CENTER
	var material := play_cap_material if is_play else settings_cap_material
	var old := play_animation if is_play else settings_animation
	var hover := play_hover_animation if is_play else settings_hover_animation
	if old != null: old.kill()
	if hover != null: hover.kill()
	if is_play:
		play_held = true
		play_feedback_pending = true
		play_down_at = Time.get_ticks_msec()
		_play_led(true)
	else:
		settings_held = true
		settings_feedback_pending = true
		settings_down_at = Time.get_ticks_msec()
	var press := create_tween().set_parallel(true)
	press.tween_property(key, "position:z", rest.z - KEY_TRAVEL, 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	press.tween_property(material, "albedo_color", KEY_PLASTIC.darkened(0.15), 0.06)
	if is_play: play_animation = press
	else: settings_animation = press

func end_key_press(is_play: bool, canceled: bool = false) -> void:
	if not (play_held if is_play else settings_held): return
	var key := play_key if is_play else settings_key
	var rest := PLAY_CENTER if is_play else SETTINGS_CENTER
	var material := play_cap_material if is_play else settings_cap_material
	var old := play_animation if is_play else settings_animation
	var elapsed := (Time.get_ticks_msec() - (play_down_at if is_play else settings_down_at)) / 1000.0
	if old != null: old.kill()
	if is_play:
		play_held = false
		if canceled: play_feedback_pending = false
	else:
		settings_held = false
		if canceled: settings_feedback_pending = false
	var release := create_tween()
	# A quick tap must reach full travel before rebounding. Long holds release
	# immediately; a pointer drag off the key cancels without completing a press.
	var remaining_down := 0.0 if canceled else maxf(0.0, 0.06 - elapsed)
	if remaining_down > 0.0:
		release.tween_property(key, "position:z", rest.z - KEY_TRAVEL, remaining_down).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		release.parallel().tween_property(material, "albedo_color", KEY_PLASTIC.darkened(0.15), remaining_down)
	var dwell := 0.0 if canceled else maxf(0.0, KEY_MIN_PRESS_SECONDS - elapsed - remaining_down)
	if dwell > 0.0: release.tween_interval(dwell)
	release.tween_property(key, "position:z", rest.z, 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	release.parallel().tween_property(material, "albedo_color", _key_rest_color(is_play), 0.10)
	if is_play: play_animation = release
	else: settings_animation = release
	while release.is_running(): await get_tree().process_frame
	if release != (play_animation if is_play else settings_animation): return
	material.albedo_color = _key_rest_color(is_play)
	if is_play: _play_led(false)

func wait_for_key_feedback(is_play: bool) -> void:
	# Mouse-up can replace the downstroke with a new release tween. Follow
	# the current tween rather than returning when the old one is killed.
	while true:
		var feedback := play_animation if is_play else settings_animation
		if feedback == null or not feedback.is_running(): break
		await get_tree().process_frame
	# Present the raised cap before camera movement or synchronous setup work.
	if DisplayServer.get_name() == "headless": await get_tree().process_frame
	else: await RenderingServer.frame_post_draw

func _play_led(lit: bool) -> void:
	var material := play_activity_led.material_override as StandardMaterial3D
	material.albedo_color = KEY_LED if lit else Color("263035")
	material.emission_enabled = lit
	material.emission = KEY_LED
	material.emission_energy_multiplier = 0.12

func settings_button_rect() -> Rect2:
	return _key_rect(SETTINGS_CENTER, Vector2(0.26, KEY_HEIGHT))

func play_button_rect() -> Rect2:
	return _key_rect(PLAY_CENTER, Vector2(0.52, KEY_HEIGHT))

func _key_rect(center: Vector3, dimensions: Vector2) -> Rect2:
	var bounds := Rect2(camera.unproject_position(center), Vector2.ZERO)
	for x in [-dimensions.x * 0.5, dimensions.x * 0.5]:
		for y in [-dimensions.y * 0.5, dimensions.y * 0.5]:
			bounds = bounds.expand(camera.unproject_position(center + Vector3(x, y, KEY_DEPTH * 0.5)))
	return bounds.grow(3)

func click_settings() -> void:
	if not settings_feedback_pending: begin_key_press(false)
	settings_feedback_pending = false
	if settings_held: end_key_press(false)
	await wait_for_key_feedback(false)

func click_play() -> void:
	if not play_feedback_pending: begin_key_press(true)
	play_feedback_pending = false
	if play_held: end_key_press(true)
	await wait_for_key_feedback(true)

func _build_case() -> void:
	var plastic := _case_material()
	# The rear shell stops behind the CRT. The front is an actual open fascia,
	# rather than dark boxes stacked on the front of a solid cube.
	var shell := _box(Vector3(3.26, 3.66, 1.66), Vector3(0, 0.77, -0.35), Color("bbc7ca"), 0.09)
	shell.material_override = _surface_material(Color("a7adb1"), 0.88, 0.20)
	var front_outer := _contour(Vector2(3.07, 2.49), Vector2(0, 1.245), 0.065, 0.88, 0.001)
	var opening := _contour(Vector2(2.80, 2.13), Vector2(0, 1.25), 0.035, 0.88)
	_ring(front_outer, opening, plastic)
	# One molded reveal with a broad lower chamfer and a deep upper hood.
	# Tiny rolled transitions soften the edges without adding concentric frames.
	_loft([
		opening,
		_contour(Vector2(2.788, 2.118), Vector2(0, 1.25), 0.037, 0.873),
		_contour(Vector2(2.59, 1.97), Vector2(0, 1.30), 0.075, 0.636),
		_contour(Vector2(2.56, 1.94), Vector2(0, 1.30), 0.085, 0.606)
	], _case_material(), true)
	var gasket_outer := _contour(Vector2(2.56, 1.94), Vector2(0, 1.30), 0.085, 0.608)
	var gasket_inner := _contour(SCREEN_SIZE, Vector2(SCREEN_CENTER.x, SCREEN_CENTER.y), 0.12, 0.65)
	_ring(gasket_outer, gasket_inner, _surface_material(Color("172024"), 0.97, 0.12))
	# Back the curved tube's slightly bowed outline with darkness, so the rear
	# casing cannot show as a bright seam between the glass and rubber surround.
	_box(Vector3(SCREEN_SIZE.x + 0.06, SCREEN_SIZE.y + 0.06, 0.02), Vector3(SCREEN_CENTER.x, SCREEN_CENTER.y, 0.62), Color("101619"), 0.12)
	# The lower fascia surrounds one continuous slot.
	var bottom_outer := _contour(Vector2(3.07, 0.97), Vector2(0, -0.485), 0.001, 0.88, 0.065)
	var band := Rect2(-1.34, -0.55, 2.66, 0.32)
	_ring(bottom_outer, _contour(band.size, band.get_center(), 0.001, 0.88), plastic)
	var openings := [Rect2(Vector2(PLAY_CENTER.x - 0.28, PLAY_CENTER.y - 0.1375), Vector2(0.56, 0.275)), Rect2(Vector2(SETTINGS_CENTER.x - 0.15, SETTINGS_CENTER.y - 0.1375), Vector2(0.30, 0.275)), Rect2(0.0675, -0.46, 1.06, 0.14)]
	var cursor := band.position.x
	for hole in openings:
		_fascia_patch(Rect2(cursor, band.position.y, hole.position.x - cursor, band.size.y), plastic)
		_fascia_patch(Rect2(hole.position.x, band.position.y, hole.size.x, hole.position.y - band.position.y), plastic)
		_fascia_patch(Rect2(hole.position.x, hole.end.y, hole.size.x, band.end.y - hole.end.y), plastic)
		cursor = hole.end.x
	_fascia_patch(Rect2(cursor, band.position.y, band.end.x - cursor, band.size.y), plastic)
	_beveled_recess(DRIVE_OUTLINE, DRIVE_FACE_Z, DRIVE_BEVEL_DEPTH, DRIVE_INSET, DRIVE_EDGE_RADIUS, DRIVE_INNER_RADIUS, DRIVE_WALL_DEPTH, "Drive")
	# Broad continuous bevel around the whole fascia, with a rolled shoulder.
	# Several connected profiles let the corners catch light without sharp facets.
	_loft([
		_contour(Vector2(3.26, 3.66), Vector2(0, 0.77), 0.105, 0.40),
		_contour(Vector2(3.26, 3.66), Vector2(0, 0.77), 0.105, 0.70),
		_contour(Vector2(3.245, 3.635), Vector2(0, 0.77), 0.10, 0.765),
		_contour(Vector2(3.20, 3.58), Vector2(0, 0.77), 0.09, 0.817),
		_contour(Vector2(3.12, 3.50), Vector2(0, 0.76), 0.075, 0.865),
		_contour(Vector2(3.085, 3.475), Vector2(0, 0.76), 0.068, 0.878),
		_contour(Vector2(3.07, 3.46), Vector2(0, 0.76), 0.065, 0.88)
	], _surface_material(Color("bfc3c5"), 0.76, 0.12), true)
	var plinth := _box(Vector3(3.05, 0.075, 1.38), Vector3(0, -1.045, -0.30), Color("9caaaf"), 0.024)
	plinth.material_override = _surface_material(Color("969ea4"), 0.92, 0.28)
	# Raised back/top deck and moulded handle grooves, visible from above.
	var top := _box(Vector3(3.08, 0.055, 1.20), Vector3(0, 2.595, -0.39), Color("c2cdd0"), 0.055)
	top.material_override = _surface_material(Color("c0c5c7"), 0.85, 0.20)
	for x in [-1.36, -0.98, 0.98, 1.36]:
		_box(Vector3(0.017, 0.009, 0.40), Vector3(x, 2.627, -0.39), Color("8e9fa6"), 0.003)
	for side in [-1, 1]:
		for i in range(7):
			_box(Vector3(0.009, 0.026, 0.56), Vector3(side * 1.631, 2.30 - i * 0.072, -0.47), Color("7c8d95"), 0.003)

func _fascia_patch(rect: Rect2, material: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(rect.position.x, rect.position.y, 0.88)
	var b := Vector3(rect.end.x, rect.position.y, 0.88)
	var c := Vector3(rect.end.x, rect.end.y, 0.88)
	var d := Vector3(rect.position.x, rect.end.y, 0.88)
	_tri(tool, a, b, c)
	_tri(tool, a, c, d)
	tool.generate_normals()
	var patch := MeshInstance3D.new()
	patch.mesh = tool.commit()
	patch.material_override = material
	add_child(patch)

func _recess_contour(outline: Array[Vector2], inset: float, depth: float, radius: float = 0.008) -> Array[Vector3]:
	# Intersect parallel inset edges at each corner: one consistent draft,
		# including the mitered ends.
	var points := PackedVector2Array()
	for index in range(outline.size()):
		var incoming := (outline[index] - outline[posmod(index - 1, outline.size())]).normalized()
		var outgoing := (outline[(index + 1) % outline.size()] - outline[index]).normalized()
		var a := Vector2(-incoming.y, incoming.x)
		var b := Vector2(-outgoing.y, outgoing.x)
		points.append(outline[index] + (a + b) * inset / (1.0 + a.dot(b)))
	var result: Array[Vector3] = []
	for index in range(points.size()):
		var corner := points[index]
		var enter := corner + (points[posmod(index - 1, points.size())] - corner).normalized() * radius
		var leave := corner + (points[(index + 1) % points.size()] - corner).normalized() * radius
		for step in range(3):
			var t := step / 2.0
			var point := enter * pow(1.0 - t, 2) + corner * 2.0 * t * (1.0 - t) + leave * t * t
			result.append(Vector3(point.x, point.y, depth))
	return result

func _beveled_recess(outline: Array[Vector2], face_z: float, depth: float, inset: float, outer_radius: float, inner_radius: float, wall_depth: float, tag: String) -> MeshInstance3D:
	# Solve the straight draft between two circular edge rolls while retaining
	# both original endpoints. Three segments per roll, with analytic normals.
	var low := 0.0
	var high := PI * 0.5
	for iteration in range(32):
		var angle := (low + high) * 0.5
		var rolled_x := outer_radius * sin(angle) + inner_radius * (1.0 - sin(angle))
		var rolled_z := outer_radius * (1.0 - cos(angle)) + inner_radius * cos(angle)
		if (depth - rolled_z) * cos(angle) > (inset - rolled_x) * sin(angle): low = angle
		else: high = angle
	var angle := (low + high) * 0.5
	if tag == "Drive": drive_bevel_angle = angle
	var sections: Array[Vector3] = [] # inset, depth behind face, tangent angle
	for step in range(4):
		var turn := angle * step / 3.0
		sections.append(Vector3(outer_radius * sin(turn), outer_radius * (1.0 - cos(turn)), turn))
	var end_x := inset - inner_radius * (1.0 - sin(angle))
	var end_z := depth - inner_radius * cos(angle)
	for step in range(4):
		var turn := lerpf(angle, PI * 0.5, step / 3.0)
		sections.append(Vector3(end_x + inner_radius * (sin(turn) - sin(angle)), end_z + inner_radius * (cos(angle) - cos(turn)), turn))
	sections.append(Vector3(inset, depth + wall_depth, PI * 0.5))
	var contours: Array = []
	for section in sections: contours.append(_recess_contour(outline, section.x, face_z - section.y))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for layer in range(sections.size() - 1):
		for index in range(contours[layer].size()):
			var next: int = (index + 1) % contours[layer].size()
			for corner in [Vector2i(layer, index), Vector2i(layer, next), Vector2i(layer + 1, next), Vector2i(layer, index), Vector2i(layer + 1, next), Vector2i(layer + 1, index)]:
				var ring: Array[Vector3] = contours[corner.x]
				var tangent: Vector3 = (ring[(corner.y + 1) % ring.size()] - ring[posmod(corner.y - 1, ring.size())]).normalized()
				var inward := Vector3(-tangent.y, tangent.x, 0)
				var section: Vector3 = sections[corner.x]
				tool.set_normal(inward * sin(section.z) + Vector3.BACK * cos(section.z))
				var occlusion := lerpf(1.0, 0.48, clampf(section.y / depth, 0.0, 1.0))
				if corner.x == sections.size() - 1: occlusion = 0.23
				# Lower walls receive less ambient fill; the deeper perimeter stays
				# shaded without SSAO or a separate transparent overlay.
				var facing := lerpf(0.82, 1.0, (1.0 - inward.y) * 0.5)
				var tone := lerpf(1.0, facing, sin(section.z)) * occlusion
				tool.set_color(Color(tone, tone, tone))
				tool.add_vertex(ring[corner.y])
	var instance := MeshInstance3D.new()
	instance.name = tag + "MoldedRecess"
	instance.mesh = tool.commit()
	var material := _case_material().duplicate() as StandardMaterial3D
	material.vertex_color_use_as_albedo = true
	instance.material_override = material
	add_child(instance)
	# Fill the tiny flat corner shoulders in the fascia plane, meeting the
	# rolled outline exactly rather than leaving triangular corner gaps.
	_loft([_recess_contour(outline, 0, face_z, 0), contours[0]], _case_material())
	return instance

func _build_drive() -> void:
	# A dark perimeter seam, short straight throat, and a separate recessed
	# flap replace the flat black backing. All hardware clears the feed axis.
	_box(Vector3(1.02, 0.10, 0.012), Vector3(DRIVE_CENTER.x, -0.39, 0.650), Color("171d1f"), 0.003)
	drive_door = Node3D.new()
	drive_door.name = "DriveFlap"
	add_child(drive_door)
	var flap := _box(Vector3(0.976, 0.060, 0.008), Vector3(DRIVE_CENTER.x, -0.39, 0.788), Color("3b4346"), 0.003, drive_door)
	flap.material_override = _surface_material(Color("3b4346"), 0.73, 0.08)
	_box(Vector3(0.960, 0.002, 0.001), Vector3(DRIVE_CENTER.x, -0.368, 0.7925), Color("252e31"), 0.001, drive_door)
	led = _box(Vector3(0.012, 0.012, 0.006), Vector3(1.335, DRIVE_CENTER.y, 0.884), Color("263035"), 0.004)
	led.material_override = _material(Color("46585e"), 0.8, true)

func _case_material() -> StandardMaterial3D:
	return _surface_material(CASE_PLASTIC, 0.84, 0.20)

func _surface_material(color: Color, roughness: float, grain: float, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f/%.2f" % [color.to_html(), roughness, grain, metallic]
	if surface_materials.has(key): return surface_materials[key]
	if surface_grain == null:
		# Shared deterministic textures: micro relief, broad tonal variation and
		# roughness. Triplanar mapping keeps their scale continuous across bevels.
		surface_grain = _noise_texture(37, 0.50)
		surface_grain.as_normal_map = true
		surface_grain.bump_strength = 0.14
		surface_mottle = _noise_texture(83, 0.013)
		var tones := Gradient.new()
		tones.set_color(0, Color(0.988, 0.988, 0.988))
		tones.set_color(1, Color.WHITE)
		surface_mottle.color_ramp = tones
		surface_roughness = _noise_texture(117, 0.035)
		var roughness_range := Gradient.new()
		roughness_range.set_color(0, Color(0.96, 0.96, 0.96))
		roughness_range.set_color(1, Color.WHITE)
		surface_roughness.color_ramp = roughness_range
	var material := _material(color, roughness)
	material.albedo_texture = surface_mottle
	material.normal_enabled = true
	material.normal_texture = surface_grain
	material.normal_scale = grain
	material.roughness_texture = surface_roughness
	material.metallic = metallic
	material.metallic_specular = 0.28 if metallic == 0 else 0.5
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	surface_materials[key] = material
	return material

func _noise_texture(seed_value: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	return texture

func _contour(dimensions: Vector2, center: Vector2, radius: float, depth: float, bottom_radius: float = -1) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var half := dimensions * 0.5
	for corner in range(4):
		var curve := bottom_radius if corner >= 2 and bottom_radius >= 0 else radius
		var origin := center + Vector2((half.x - curve) * (1 if corner in [0, 3] else -1), (half.y - curve) * (1 if corner in [0, 1] else -1))
		for step in range(9):
			var angle := (corner * 0.5 + float(step) / 16.0) * PI
			var point := origin + Vector2(cos(angle), sin(angle)) * curve
			points.append(Vector3(point.x, point.y, depth))
	return points

func _ring(outer: Array[Vector3], inner: Array[Vector3], material: Material) -> void:
	_loft([outer, inner], material)

func _loft(contours: Array, material: Material, smooth: bool = false) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(0 if smooth else -1)
	for layer in range(contours.size() - 1):
		var outer: Array[Vector3] = contours[layer]
		var inner: Array[Vector3] = contours[layer + 1]
		for i in range(outer.size()):
			var next := (i + 1) % outer.size()
			_tri(tool, outer[i], outer[next], inner[next])
			_tri(tool, outer[i], inner[next], inner[i])
	tool.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = tool.commit()
	instance.material_override = material
	add_child(instance)

func _material(color: Color, roughness: float = 0.6, unshaded: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _crt_mesh() -> ArrayMesh:
	# Subdivisions let the shared shader bow the glass, then flatten it smoothly
	# as clean_view reaches one for an exact fullscreen handoff.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(28):
		for column in range(40):
			for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				var uv: Vector2 = (Vector2(column, row) + corner) / Vector2(40, 28)
				tool.set_uv(uv)
				tool.set_normal(Vector3.BACK)
				tool.add_vertex(Vector3((uv.x - 0.5) * SCREEN_SIZE.x, (0.5 - uv.y) * SCREEN_SIZE.y, 0))
	return tool.commit()

func screen_point(uv: Vector2) -> Vector3:
	var clean: float = screen_material.get_shader_parameter("clean_view")
	var physical: float = screen_material.get_shader_parameter("physical_glass")
	var q := uv * 2.0 - Vector2.ONE
	var bulge := CRT_BULGE * maxf(1.0 - clean, physical) * (1.0 - q.x * q.x) * (1.0 - q.y * q.y)
	return SCREEN_CENTER + Vector3((uv.x - 0.5) * SCREEN_SIZE.x * screen.scale.x, (0.5 - uv.y) * SCREEN_SIZE.y, bulge)

func _floppy_body() -> ArrayMesh:
	# Closed thin shell with the same clipped upper-left corner as the face.
	var outline := PackedVector2Array([
		Vector2(-0.493, 0.408), Vector2(-0.408, 0.493), Vector2(0.47, 0.493),
		Vector2(0.493, 0.47), Vector2(0.493, -0.47), Vector2(0.47, -0.493),
		Vector2(-0.47, -0.493), Vector2(-0.493, -0.47)])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	for index in range(outline.size()):
		var next := (index + 1) % outline.size()
		var a := Vector3(outline[index].x, outline[index].y, -0.02)
		var b := Vector3(outline[next].x, outline[next].y, -0.02)
		_tri(tool, a, b, b + Vector3(0, 0, 0.04))
		_tri(tool, a, b + Vector3(0, 0, 0.04), a + Vector3(0, 0, 0.04))
	var indices := Geometry2D.triangulate_polygon(outline)
	for triangle in range(0, indices.size(), 3):
		var a := Vector3(outline[indices[triangle]].x, outline[indices[triangle]].y, -0.02)
		var b := Vector3(outline[indices[triangle + 1]].x, outline[indices[triangle + 1]].y, -0.02)
		var c := Vector3(outline[indices[triangle + 2]].x, outline[indices[triangle + 2]].y, -0.02)
		_tri(tool, a, b, c)
		_tri(tool, c + Vector3(0, 0, 0.04), b + Vector3(0, 0, 0.04), a + Vector3(0, 0, 0.04))
	tool.generate_normals()
	return tool.commit()

func _box(dimensions: Vector3, location: Vector3, color: Color, bevel: float, parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = _rounded_box(dimensions, bevel)
	instance.material_override = _material(color)
	instance.position = location
	(parent if parent != null else self).add_child(instance)
	return instance

func _rounded_box(dimensions: Vector3, radius: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := dimensions * 0.5
	var bevel := minf(radius * 0.45, half.z * 0.45)
	var rings: Array = []
	for layer in [Vector2(-half.z, bevel), Vector2(-half.z + bevel, 0), Vector2(half.z - bevel, 0), Vector2(half.z, bevel)]:
		var ring: Array[Vector3] = []
		var corner_radius := maxf(0.001, minf(radius - layer.y, minf(half.x, half.y) - layer.y))
		for corner in range(4):
			var center := Vector2((half.x - layer.y - corner_radius) * (1 if corner in [0, 3] else -1), (half.y - layer.y - corner_radius) * (1 if corner in [0, 1] else -1))
			for step in range(7):
				var angle := (corner * 0.5 + float(step) / 12.0) * PI
				var point := center + Vector2(cos(angle), sin(angle)) * corner_radius
				ring.append(Vector3(point.x, point.y, layer.x))
		rings.append(ring)
	for layer in range(3):
		for i in range(rings[layer].size()):
			var next: int = (i + 1) % rings[layer].size()
			_tri(tool, rings[layer][i], rings[layer][next], rings[layer + 1][next])
			_tri(tool, rings[layer][i], rings[layer + 1][next], rings[layer + 1][i])
	tool.set_smooth_group(-1)
	for i in range(rings[0].size()):
		var next: int = (i + 1) % rings[0].size()
		_tri(tool, Vector3(0, 0, -half.z), rings[0][next], rings[0][i])
		_tri(tool, Vector3(0, 0, half.z), rings[3][i], rings[3][next])
	tool.generate_normals()
	return tool.commit()

func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)

func set_display(texture: Texture2D) -> void:
	screen_material.set_shader_parameter("display_texture", texture)
	screen_material.set_shader_parameter("grid_preview", false)

func screen_uv(point: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(point)
	var ray := camera.project_ray_normal(point)
	if absf(ray.z) < 0.00001: return Vector2(-1, -1)
	var depth := SCREEN_CENTER.z
	var uv := Vector2.ZERO
	for iteration in range(7):
		var hit := origin + ray * ((depth - origin.z) / ray.z)
		uv = Vector2((hit.x - SCREEN_CENTER.x) / (SCREEN_SIZE.x * screen.scale.x) + 0.5, 0.5 - (hit.y - SCREEN_CENTER.y) / SCREEN_SIZE.y)
		if uv.x < 0 or uv.y < 0 or uv.x > 1 or uv.y > 1: return Vector2(-1, -1)
		depth = screen_point(uv).z
	return uv

func insert_deck(texture: Texture2D, cover: Rect2, tilt: float = 0.0, color: Color = Color("c9a34e"), formatting: bool = false) -> bool:
	launch_generation += 1
	var generation := launch_generation
	working = true
	set_disk_face(texture, color)
	if formatting:
		disk_face.material_override = disk_night_material
	var point := cover.get_center()
	# Start at the depth that projects a real .92-unit disk to its carousel size.
	# The object can then travel toward the drive without changing physical size.
	var depth := 0.92 * get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(camera.fov * 0.5)) * maxf(1.0, cover.size.x))
	var origin := camera.project_position(point, depth)
	disk.position = origin
	disk.quaternion = camera.quaternion * Quaternion(Vector3.BACK, -tilt)
	disk.scale = Vector3.ONE * 0.92
	disk.show()
	animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	animation.set_parallel(true)
	# Finish the lift/rotation clear of the fascia, then feed straight along
	# the locked drive axis. Total approach and disk_entering timing stay 1s.
	animation.tween_property(disk, "position", DRIVE_CENTER + Vector3(0, 0, 1.04), 0.70)
	animation.tween_property(disk, "quaternion", DRIVE_ROTATION, 0.70)
	if formatting:
		animation.tween_method(_set_label_erase, 0.0, 4.0, 0.52).set_delay(0.04).set_trans(Tween.TRANS_LINEAR)
	animation.chain().tween_property(disk, "position", DRIVE_CENTER + Vector3(0, 0, 0.72), 0.30).set_trans(Tween.TRANS_SINE)
	animation.chain().tween_callback(func(): disk_entering.emit())
	animation.chain().tween_property(disk, "position:z", -0.25, 0.95).set_trans(Tween.TRANS_SINE)
	var running := animation
	while running.is_running(): await get_tree().process_frame
	if generation != launch_generation: return false
	disk.hide()
	_sync_drive_door()
	return true

func _set_label_erase(value: float) -> void:
	label_erase = value
	if disk_night_material != null: disk_night_material.set_shader_parameter("erase_label", value)

func set_disk_face(texture: Texture2D, color: Color) -> void:
	label_erase = 0.0
	var material := _material(Color.WHITE if texture != null else Color("45636d"), 0.7, true)
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disk_day_material = material
	disk_night_material = ShaderMaterial.new()
	disk_night_material.shader = preload("res://scripts/app/InsertionNightLighting.gdshader")
	disk_night_material.set_shader_parameter("has_texture", texture != null)
	disk_night_material.set_shader_parameter("face_color", Color.WHITE if texture != null else Color("45636d"))
	if texture != null: disk_night_material.set_shader_parameter("face_texture", texture)
	disk_face.material_override = disk_night_material if room_darkness > 0.0 else disk_day_material
	disk_body.material_override = _surface_material(color, 0.82, 0.20)

func zoom_into(texture: Texture2D, viewport_size: Vector2, tune_to: Texture2D = null) -> void:
	screen_material = zoom_material
	screen.material_override = screen_material
	screen_material.set_shader_parameter("clean_view", 0.0)
	screen_material.set_shader_parameter("channel_progress", -1.0)
	screen_material.set_shader_parameter("reveal_progress", -1.0)
	screen_material.set_shader_parameter("physical_glass", 0.0)
	screen_material.set_shader_parameter("projection_blend", 0.0)
	set_display(texture)
	screen_material.set_shader_parameter("grid_preview", tune_to == null)
	var height := SCREEN_SIZE.y
	var target_distance := height / (2.0 * tan(deg_to_rad(camera.fov * 0.5)))
	var target_position := SCREEN_CENTER + Vector3(0, 0, target_distance)
	animation = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if tune_to != null else Tween.EASE_IN_OUT)
	animation.tween_property(camera, "position", target_position, 1.1)
	animation.tween_property(camera, "quaternion", Quaternion.IDENTITY, 1.1)
	animation.tween_property(screen, "scale:x", height * viewport_size.x / viewport_size.y / SCREEN_SIZE.x, 1.1)
	animation.tween_method(func(value): screen_material.set_shader_parameter("clean_view", value), 0.0, 1.0, 1.1)
	# The channel coroutine runs alongside the camera tween, on this same
	# expanding-screen material, and finishes before the fullscreen handoff.
	if tune_to != null: change_channel(tune_to, 0.16)
	await animation.finished

func zoom_into_settings(texture: Texture2D, viewport_size: Vector2, tune_to: Texture2D) -> void:
	# Keep the glass locked to the actual bezel. Only the camera moves;
	# screen-space sampling makes the final overscan match the fullscreen UI.
	screen.scale = Vector3.ONE
	screen_material = crt_material
	screen.material_override = screen_material
	set_display(texture)
	screen_material.set_shader_parameter("clean_view", 0.0)
	screen_material.set_shader_parameter("physical_glass", 0.0)
	screen_material.set_shader_parameter("projection_blend", 0.0)
	screen_material.set_shader_parameter("reveal_progress", -1.0)
	var distance := _settings_distance(viewport_size)
	animation = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(camera, "position", SCREEN_CENTER + Vector3(0, 0, distance), 1.1)
	animation.tween_property(camera, "quaternion", Quaternion.IDENTITY, 1.1)
	animation.tween_method(func(value): screen_material.set_shader_parameter("projection_blend", value), 0.0, 1.0, 0.25).set_delay(0.85)
	animation.tween_method(func(value): screen_material.set_shader_parameter("clean_view", value), 0.0, 1.0, 0.30).set_delay(0.80)
	change_channel(tune_to, 0.16)
	await animation.finished

func _settings_distance(viewport_size: Vector2) -> float:
	var tangent := tan(deg_to_rad(camera.fov * 0.5))
	var horizontal := SCREEN_SIZE.x / (2.0 * tangent * viewport_size.x / viewport_size.y)
	var vertical := SCREEN_SIZE.y / (2.0 * tangent)
	return minf(horizontal, vertical) / 1.08

func prepare_settings_zoom_out(texture: Texture2D, viewport_size: Vector2) -> void:
	screen.scale = Vector3.ONE
	screen_material = crt_material
	screen.material_override = screen_material
	set_display(texture)
	screen_material.set_shader_parameter("clean_view", 1.0)
	screen_material.set_shader_parameter("physical_glass", 0.0)
	screen_material.set_shader_parameter("projection_blend", 1.0)
	screen_material.set_shader_parameter("channel_progress", -1.0)
	screen_material.set_shader_parameter("reveal_progress", -1.0)
	camera.position = SCREEN_CENTER + Vector3(0, 0, _settings_distance(viewport_size))
	camera.quaternion = Quaternion.IDENTITY

func zoom_out_settings(texture: Texture2D, viewport_size: Vector2, tune_to: Texture2D) -> void:
	prepare_settings_zoom_out(texture, viewport_size)
	animation = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	animation.tween_property(camera, "position", home_transform.origin, 0.95)
	animation.tween_property(camera, "quaternion", home_transform.basis.get_rotation_quaternion(), 0.95)
	animation.tween_method(func(value): screen_material.set_shader_parameter("projection_blend", value), 1.0, 0.0, 0.28)
	animation.tween_method(func(value): screen_material.set_shader_parameter("clean_view", value), 1.0, 0.0, 0.38)
	change_channel(tune_to, 0.12)
	await animation.finished
	screen_material.set_shader_parameter("channel_progress", -1.0)
	set_display(tune_to)

func reset_view() -> void:
	launch_generation += 1
	if animation != null and animation.is_running(): animation.kill()
	if channel_animation != null and channel_animation.is_running(): channel_animation.kill()
	if play_animation != null: play_animation.kill()
	if settings_animation != null: settings_animation.kill()
	if play_hover_animation != null: play_hover_animation.kill()
	if settings_hover_animation != null: settings_hover_animation.kill()
	play_hover = false
	settings_hover = false
	play_held = false
	settings_held = false
	play_feedback_pending = false
	settings_feedback_pending = false
	play_key.position = PLAY_CENTER
	settings_key.position = SETTINGS_CENTER
	play_cap_material.albedo_color = _key_rest_color(true)
	settings_cap_material.albedo_color = _key_rest_color(false)
	_play_led(false)
	working = false
	drive_log_active = false
	drive_format_active = false
	drive_activity = 0.0
	_set_label_erase(0.0)
	disk.hide()
	_sync_drive_door()
	camera.transform = home_transform
	screen.scale = Vector3.ONE
	screen_material = crt_material
	screen.material_override = screen_material
	screen_material.set_shader_parameter("clean_view", 0.0)
	screen_material.set_shader_parameter("channel_progress", -1.0)
	screen_material.set_shader_parameter("reveal_progress", -1.0)
	screen_material.set_shader_parameter("physical_glass", 0.0)
	screen_material.set_shader_parameter("projection_blend", 0.0)

func change_channel(texture: Texture2D, delay: float = 0.0) -> void:
	var generation := launch_generation
	screen_material.set_shader_parameter("channel_texture", texture)
	screen_material.set_shader_parameter("channel_progress", 0.0)
	if channel_animation != null: channel_animation.kill()
	channel_animation = create_tween()
	if delay > 0.0: channel_animation.tween_interval(delay)
	channel_animation.tween_method(func(value): screen_material.set_shader_parameter("channel_progress", value), 0.0, 1.0, 0.70)
	var running := channel_animation
	while running.is_running(): await get_tree().process_frame
	if generation != launch_generation: return
	set_display(texture)
	screen_material.set_shader_parameter("channel_progress", -1.0)

func materialize_board(texture: Texture2D) -> void:
	screen_material = crt_material
	screen.material_override = screen_material
	set_display(texture)
	screen_material.set_shader_parameter("grid_preview", true)
	screen_material.set_shader_parameter("clean_view", 0.0)
	screen_material.set_shader_parameter("channel_progress", -1.0)
	screen_material.set_shader_parameter("reveal_progress", 0.0)
	animation = create_tween()
	animation.tween_method(func(value): screen_material.set_shader_parameter("reveal_progress", value), 0.0, 1.0, 1.1)
	animation.tween_interval(0.18)
	await animation.finished
	screen_material.set_shader_parameter("reveal_progress", -1.0)

func prepare_startup_pullback(texture: Texture2D, viewport_size: Vector2) -> void:
	# Keep the physical tube and its depth-tested casing fixed throughout.
	# Start close enough to overscan the glass; screen-space sampling provides
	# the exact fullscreen image until it settles into the tube's own UVs.
	screen.scale = Vector3.ONE
	screen_material = crt_material
	screen.material_override = screen_material
	set_display(texture)
	screen_material.set_shader_parameter("clean_view", 1.0)
	screen_material.set_shader_parameter("physical_glass", 1.0)
	screen_material.set_shader_parameter("projection_blend", 1.0)
	screen_material.set_shader_parameter("channel_progress", -1.0)
	screen_material.set_shader_parameter("reveal_progress", -1.0)
	var aspect := viewport_size.x / viewport_size.y
	var distance_x := SCREEN_SIZE.x / (2.0 * tan(deg_to_rad(camera.fov * 0.5)) * aspect)
	var distance_y := SCREEN_SIZE.y / (2.0 * tan(deg_to_rad(camera.fov * 0.5)))
	camera.position = SCREEN_CENTER + Vector3(0, 0, minf(distance_x, distance_y) / 1.08)
	camera.quaternion = Quaternion.IDENTITY

func pullback_startup() -> void:
	animation = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	animation.tween_property(camera, "position", home_transform.origin, 1.65)
	animation.tween_property(camera, "quaternion", home_transform.basis.get_rotation_quaternion(), 1.65)
	animation.tween_method(func(value): screen_material.set_shader_parameter("projection_blend", value), 1.0, 0.0, 0.50)
	animation.tween_method(func(value): screen_material.set_shader_parameter("clean_view", value), 1.0, 0.0, 0.75)
	await animation.finished
	screen_material.set_shader_parameter("physical_glass", 0.0)
	screen_material.set_shader_parameter("projection_blend", 0.0)

func prepare_zoom_out(texture: Texture2D, viewport_size: Vector2) -> void:
	screen_material = zoom_material
	screen.material_override = screen_material
	set_display(texture)
	screen_material.set_shader_parameter("clean_view", 1.0)
	screen_material.set_shader_parameter("channel_progress", -1.0)
	screen_material.set_shader_parameter("reveal_progress", -1.0)
	screen.scale.x = SCREEN_SIZE.y * viewport_size.x / viewport_size.y / SCREEN_SIZE.x
	camera.position = SCREEN_CENTER + Vector3(0, 0, SCREEN_SIZE.y / (2.0 * tan(deg_to_rad(camera.fov * 0.5))))
	camera.quaternion = Quaternion.IDENTITY

func zoom_out(texture: Texture2D, viewport_size: Vector2, duration: float = 0.95, tune_to: Texture2D = null) -> void:
	prepare_zoom_out(texture, viewport_size)
	animation = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if tune_to != null else Tween.EASE_IN_OUT)
	animation.tween_property(camera, "position", home_transform.origin, duration)
	animation.tween_property(camera, "quaternion", home_transform.basis.get_rotation_quaternion(), duration)
	animation.tween_property(screen, "scale:x", 1.0, duration)
	animation.tween_method(func(value): screen_material.set_shader_parameter("clean_view", value), 1.0, 0.0, duration)
	if tune_to != null: change_channel(tune_to, 0.12)
	await animation.finished
	screen_material = crt_material
	screen.material_override = screen_material
	screen_material.set_shader_parameter("clean_view", 0.0)
	screen_material.set_shader_parameter("channel_progress", -1.0)
	set_display(tune_to if tune_to != null else texture)

func eject_deck(cover: Rect2, tilt: float, disconnect_texture: Texture2D = null) -> void:
	working = true
	disk.position = Vector3(DRIVE_CENTER.x, DRIVE_CENTER.y, -0.25)
	disk.quaternion = DRIVE_ROTATION
	disk.scale = Vector3.ONE * 0.92
	disk.show()
	# Lose the signal as the session disk starts clearing the drive contacts.
	# Its independent tween overlaps the physical ejection without pausing it.
	if disconnect_texture != null: change_channel(disconnect_texture, 0.28)
	var depth := 0.92 * get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(camera.fov * 0.5)) * maxf(1.0, cover.size.x))
	var destination := camera.project_position(cover.get_center(), depth)
	animation = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	animation.tween_property(disk, "position:z", DRIVE_CENTER.z + 0.72, 0.65)
	animation.set_parallel(true)
	animation.chain().tween_property(disk, "position", destination, 0.95)
	animation.tween_property(disk, "quaternion", camera.quaternion * Quaternion(Vector3.BACK, -tilt), 0.95)
	await animation.finished
	disk.hide()
	_sync_drive_door()
	working = false

func _sync_drive_door() -> void:
	if drive_door == null: return
	# Open before either edge reaches the flap; close once the disk is fully
	# past it. The same physical representation covers play, resume, erase and
	# both ejections, with no timers or additional animation ownership.
	var crosses := disk != null and disk.visible and absf(disk.position.y - DRIVE_CENTER.y) < 0.06 and (disk.quaternion * Vector3.BACK).dot(Vector3.UP) > 0.9 and disk.position.z - 0.48 < 0.96 and disk.position.z + 0.48 > 0.64
	drive_door.visible = not crosses

func set_room_darkness(amount: float) -> void:
	room_darkness = amount
	room_environment.background_color = Color("d9dfe2").lerp(Color("111719"), amount)
	floor_material.albedo_color = room_environment.background_color
	room_floor.material_override = night_floor_material if amount > 0.0 else floor_material
	night_floor_material.set_shader_parameter("night_amount", amount)
	room_environment.ambient_light_color = Color("d7d9dc").lerp(Color("9aa9ad"), amount)
	room_environment.ambient_light_energy = lerpf(0.62, 0.09, amount)
	room_key.light_energy = lerpf(0.65, 0.08, amount)
	room_fill.light_energy = lerpf(0.35, 0.015, amount)
	monitor_light.light_energy = amount * 2.8
	night_rim.light_energy = amount * 0.18
	crt_material.set_shader_parameter("night_amount", amount)
	zoom_material.set_shader_parameter("night_amount", amount)
	if disk_night_material != null:
		disk_night_material.set_shader_parameter("night_amount", amount)
		disk_face.material_override = disk_night_material if amount > 0.0 or label_erase > 0.0 else disk_day_material

func pulse_drive() -> void:
	drive_activity = 0.20
	drive_pulses += 1

func _process(delta: float) -> void:
	_sync_drive_door()
	if disk_night_material != null and disk.visible and room_darkness > 0.0:
		disk_night_material.set_shader_parameter("night_amount", room_darkness)
		disk_night_material.set_shader_parameter("approach", 1.0 - smoothstep(1.0, 4.0, disk.position.distance_to(DRIVE_CENTER)))
	drive_activity = maxf(0, drive_activity - delta)
	if led != null:
		var material := led.material_override as StandardMaterial3D
		var lit := drive_activity > 0 and sin(drive_activity * 140) > -0.25 if drive_log_active else working and sin(Time.get_ticks_msec() * 0.014) > 0
		var activity_color := Color("ffb44f") if drive_format_active else Color("84e3ce")
		material.albedo_color = activity_color if lit else (Color("80572d") if drive_format_active else Color("46585e"))
		material.emission_enabled = lit
		material.emission = activity_color
		material.emission_energy_multiplier = 0.35
