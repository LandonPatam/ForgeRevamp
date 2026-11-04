shader_type canvas_item;
render_mode unshaded;

// Presentation only: TEXTURE stays the unlit, shared floppy face.
uniform float night_amount = 0.0;
uniform float center_strength = 1.0;

void fragment() {
    // Canvas COLOR already includes TEXTURE and the item's modulation.
    vec4 face = COLOR;
    if (night_amount > 0.0) {
        float near_center = clamp(center_strength, 0.0, 1.0);
        float brightness = mix(0.52, 0.90, near_center);
        float spill = exp(-UV.y * 3.8) * mix(0.045, 0.16, near_center);
        float top_rim = exp(-pow((UV.y - 0.013) / 0.009, 2.0));
        vec3 night = face.rgb * brightness;
        night += face.rgb * vec3(0.16, 0.70, 0.62) * spill;
        night += vec3(0.10, 0.16, 0.22) * top_rim * mix(0.22, 0.50, near_center);
        face.rgb = mix(face.rgb, night, night_amount);
    }
    COLOR = face;
}
