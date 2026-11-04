shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float darkness = 0.0;
uniform float home_visibility = 1.0;
uniform vec4 monitor_rect = vec4(0.35, 0.20, 0.30, 0.30);

float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
               mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

float clouds(vec2 p) {
    float value = noise(p) * 0.55;
    value += noise(p * 2.03 + vec2(7.1, 3.8)) * 0.28;
    value += noise(p * 4.11 + vec2(2.3, 9.2)) * 0.17;
    return value;
}

void fragment() {
    vec3 source = texture(scene_texture, SCREEN_UV).rgb;
    // Grain belongs to the home-room layer, so it travels with that layer
    // instead of being regenerated at fixed window coordinates in the editor.
    vec2 pixels = UV / SCREEN_PIXEL_SIZE;
    vec2 p = pixels / min(1.0 / SCREEN_PIXEL_SIZE.x, 1.0 / SCREEN_PIXEL_SIZE.y);
    // Soft teal pigment gathers around the PC and clears toward the perimeter.
    vec2 offset = (UV - vec2(0.5, 0.38)) / vec2(0.49, 0.53);
    float around_pc = 1.0 - smoothstep(0.35, 1.55, length(offset));
    vec2 warp = vec2(noise(p * 1.7 + 8.0), noise(p * 1.9 + 23.0));
    float pigment = smoothstep(0.31, 0.70, clouds(p * 3.3 + warp * 1.6 + vec2(3.8, 8.2)));
    float luminance = dot(source, vec3(0.2126, 0.7152, 0.0722));
    float paper = smoothstep(0.12, 0.85, luminance);
    vec3 treated = mix(source, vec3(0.35, 0.66, 0.60), pigment * 0.16 * around_pc * mix(0.18, 1.0, paper));
    // Visible fine grain and slightly larger teal speckles around the computer.
    float grain = hash(floor(pixels)) - 0.5;
    treated += grain * mix(0.012, 0.040, paper) * mix(0.04, 1.0, around_pc);
    float fleck = smoothstep(0.82, 0.98, hash(floor(pixels / 1.35) + vec2(81.0, 29.0)));
    treated -= vec3(0.070, 0.025, 0.034) * fleck * paper * around_pc;
    if (darkness > 0.0) {
        // A quiet room gradient, not a painted halo over the plastic bezel.
        // The center follows the projected tube across aspect/camera changes.
        vec2 center = monitor_rect.xy + monitor_rect.zw * vec2(0.5, 1.18);
        vec2 room_offset = (SCREEN_UV - center) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
        float pool = exp(-dot(room_offset / vec2(0.72, 0.48), room_offset / vec2(0.72, 0.48)) * 2.0);
        float vignette = smoothstep(0.3, 1.1, length((SCREEN_UV - vec2(0.5)) * vec2(1.0, 1.2)));
        vec3 room = mix(vec3(0.016, 0.025, 0.033), vec3(0.046, 0.100, 0.105), pool) * (1.0 - vignette * 0.18);
        vec3 night_base = vec3(17.0, 23.0, 25.0) / 255.0;
        vec3 base = mix(vec3(217.0, 223.0, 226.0) / 255.0, night_base, darkness);
        float background = 1.0 - smoothstep(0.035, 0.090, distance(source, base));
        vec3 quiet_finish = source + (treated - source) * 0.24;
        // The room color is already partway to night; offset the target by what
        // remains so the fade stays linear (identical to the room at full dark).
        vec3 night = mix(quiet_finish, room + grain * 0.003 + (base - night_base), background);
        treated = mix(treated, night, darkness);
    }
    float layer_fade = 1.0 - smoothstep(0.84, 1.0, UV.y);
    COLOR = vec4(mix(source, clamp(treated, vec3(0.0), vec3(1.0)), strength * layer_fade * home_visibility), 1.0);
}
