shader_type spatial;
render_mode blend_mix, cull_back, specular_disabled;

uniform sampler2D face_texture : source_color, filter_linear;
uniform bool has_texture = false;
uniform vec4 face_color : source_color = vec4(1.0);
uniform float night_amount = 0.0;
uniform float approach = 0.0;
// Local presentation only: never write into the shared floppy viewport.
uniform float erase_label = 0.0;

void fragment() {
    vec4 face = has_texture ? texture(face_texture, UV) : face_color;
    for (int row = 0; row < 4; row++) {
        float y = (row == 3 ? 410.0 : 276.0 + float(row) * 34.0) / 512.0;
        float amount = clamp(erase_label - float(row), 0.0, 1.0);
        float x = (UV.x * 512.0 - 210.0) / 254.0;
        float stroke = 1.0 - smoothstep(1.2, 3.0, abs(UV.y * 512.0 - y * 512.0 - sin(UV.x * 160.0) * 1.6));
        if (amount > 0.0 && x >= 0.0 && x <= amount) face.rgb = mix(face.rgb, vec3(0.14, 0.20, 0.21), stroke * 0.9);
    }
    float lit = night_amount * approach;
    // Match the selected 2D disk while far from the PC, then let the same
    // raw face receive the real monitor light as it enters the spill field.
    vec3 presented = face.rgb * mix(1.0, 0.80, night_amount);
    presented += face.rgb * vec3(0.02, 0.08, 0.07) * exp(-UV.y * 3.8) * night_amount;
    ALBEDO = face.rgb * lit;
    EMISSION = presented * (1.0 - lit);
    ROUGHNESS = 0.94;
    ALPHA = face.a;
}
