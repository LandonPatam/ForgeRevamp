shader_type canvas_item;
render_mode unshaded;
uniform sampler2D eye_texture : filter_linear_mipmap, repeat_disable;
uniform sampler2D closed_eye_texture : filter_linear_mipmap, repeat_disable;
uniform vec2 gaze = vec2(0.0);
uniform float openness = 1.0;
uniform float clock = 0.0;
uniform vec4 ink : source_color = vec4(0.39, 0.80, 0.68, 1.0);

float bayer2(vec2 p) { return 2.0 * p.x + 3.0 * p.y - 4.0 * p.x * p.y; }
float threshold(vec2 pixel) {
    float ordered = (4.0 * bayer2(mod(pixel, 2.0)) + bayer2(mod(floor(pixel / 2.0), 2.0)) + 0.5) / 16.0;
    vec2 dot_p = (mod(pixel, 4.0) + 0.5) / 4.0 - 0.5;
    float cluster = 1.0 - smoothstep(0.0, 0.65, length(dot_p));
    return mix(cluster, ordered, 0.25);
}
void fragment() {
    vec2 resolution = vec2(272, 184);
    vec2 pixel = floor(UV * resolution);
    vec2 uv = (pixel + 0.5) / resolution;
    // The photograph supplies asymmetrical lid contours and real socket shading.
    // Warp only the eyeball; skin, lashes and the lid crease stay stationary.
    float t = clamp((uv.x - 0.105) / 0.765, 0.0, 1.0);
    float span = pow(max(0.0, sin(t * 3.14159265)), 0.90);
    float corner_line = mix(0.61, 0.54, t);
    float upper = corner_line - 0.255 * span;
    float lower = corner_line + 0.080 * span;
    float inside_eye = smoothstep(upper + 0.008, upper + 0.038, uv.y);
    inside_eye *= 1.0 - smoothstep(lower - 0.030, lower - 0.002, uv.y);
    inside_eye *= smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.94, 1.0, t));
    vec2 center = vec2(0.514, 0.468);
    float iris_region = 1.0 - smoothstep(0.225, 0.36, length((uv - center) * vec2(1.5, 1.0)));
    vec2 moved = uv - gaze;
    vec2 enlarged = center + (moved - center) / 1.17;
    vec2 sample_uv = mix(uv, enlarged, inside_eye * iris_region);
    // Match the reference's pupil/iris ratio without enlarging the entire eye.
    vec2 pupil_sample = sample_uv - center;
    float pupil_region = 1.0 - smoothstep(0.065, 0.125, length(pupil_sample * vec2(1.5, 1.0)));
    sample_uv = center + pupil_sample * (1.0 - 0.20 * pupil_region * inside_eye);
    vec3 photo = texture(eye_texture, clamp(sample_uv, vec2(0.0), vec2(1.0))).rgb;
    // A registered closed-lid photograph preserves real creases during blinks.
    // Never stretch a single strip of skin over the eyeball.
    if (openness < 0.999) {
        vec3 closed_photo = texture(closed_eye_texture, uv).rgb;
        float region = 1.0 - smoothstep(0.90, 1.10, length((uv - vec2(0.50, 0.49)) / vec2(0.51, 0.31)));
        float closure = smoothstep(0.0, 0.80, 1.0 - openness);
        photo = mix(photo, closed_photo, closure * region);
    }
    float luminance = dot(photo, vec3(0.2126, 0.7152, 0.0722));
    // A high-key monochrome print: broad lit skin, clustered black dots in
    // midtones, dense ink under the lid and in the pupil, not uniform checkerboard.
    float shade = pow(clamp((luminance - 0.025) * 1.16, 0.0, 1.0), 0.86);
    float cut = threshold(pixel);
    float hatch = (1.0 - smoothstep(0.15, 0.34, uv.x)) * (1.0 - smoothstep(0.17, 0.32, uv.y));
    cut = mix(cut, (mod(pixel.y, 4.0) + 0.5) / 4.0, hatch * 0.7);
    float bit = step(cut, shade);
    float scan = 0.96 + 0.04 * mod(pixel.y, 2.0);
    COLOR = vec4(mix(vec3(0.005, 0.025, 0.020), ink.rgb * scan, bit), 1.0);
}
