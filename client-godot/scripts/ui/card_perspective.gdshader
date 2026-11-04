shader_type canvas_item;
render_mode unshaded;
uniform vec2 surface_size = vec2(160.0, 218.0);
uniform float tilt = 0.36;
uniform float reveal_progress : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D back_texture : source_color;
uniform vec4 back_region = vec4(0.2, 0.75, 0.2, 0.25);
varying vec4 tint;
varying vec2 uv_projected;
varying float inverse_depth;

void vertex() {
    tint = COLOR;
    vec2 center = surface_size * 0.5;
    vec2 point = VERTEX - center;
    // A camera looking down onto the card plane. UV/depth interpolation keeps art straight.
    float depth = -point.y * sin(tilt);
    float projection = 440.0 / (440.0 + depth);
    VERTEX = center + vec2(point.x, point.y * cos(tilt)) * projection;
    // Turn around the vertical center without changing the layout or hit box.
    VERTEX.x = center.x + (VERTEX.x - center.x) * max(0.015, abs(cos(reveal_progress * PI)));
    inverse_depth = projection;
    uv_projected = UV * projection;
}

void fragment() {
    vec2 card_uv = uv_projected / inverse_depth;
    vec4 face = texture(TEXTURE, card_uv);
    if (reveal_progress < 0.5) {
        // The cached face includes a transparent shadow margin; align the back
        // with the physical card inside that same margin.
        vec2 back_uv = (card_uv - vec2(0.05, 32.0 / 872.0)) / vec2(0.9, 808.0 / 872.0);
        face = texture(back_texture, back_region.xy + clamp(back_uv, vec2(0.0), vec2(1.0)) * back_region.zw);
        face.a *= step(0.0, back_uv.x) * step(back_uv.x, 1.0) * step(0.0, back_uv.y) * step(back_uv.y, 1.0);
    }
    float light = mix(1.08, 0.92, card_uv.y);
    float flip_light = mix(0.65, 1.0, abs(cos(reveal_progress * PI)));
    COLOR = vec4(face.rgb * mix(1.0, light, sin(tilt)) * flip_light, face.a) * tint;
}
