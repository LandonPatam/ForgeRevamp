shader_type canvas_item;
render_mode unshaded;
uniform sampler2D artwork : source_color, filter_linear_mipmap;
uniform bool has_artwork = false;
uniform vec4 shell_color : source_color = vec4(0.77, 0.59, 0.28, 1.0);

float box(vec2 p, vec2 center, vec2 half_size, float radius) {
    vec2 q = abs(p - center) - half_size + radius;
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}
float grain(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float segment(vec2 p, vec2 a, vec2 b) {
    vec2 edge = b - a;
    return length(p - a - edge * clamp(dot(p - a, edge) / dot(edge, edge), 0.0, 1.0));
}
float mould_marks(vec2 p) {
    // Center the insertion arrow in the exposed shoulder: the track ends at
    // upright x=.103, the shell rim at x=.019, and the track spans y=0..354.
    p -= vec2(0.061, 0.177);
    float arrow = segment(p, vec2(0.0, -0.031), vec2(-0.030, 0.005));
    arrow = min(arrow, segment(p, vec2(0.0, -0.031), vec2(0.030, 0.005)));
    arrow = min(arrow, segment(p, vec2(-0.030, 0.005), vec2(-0.014, 0.005)));
    arrow = min(arrow, segment(p, vec2(0.030, 0.005), vec2(0.014, 0.005)));
    arrow = min(arrow, segment(p, vec2(-0.014, 0.005), vec2(-0.014, 0.031)));
    arrow = min(arrow, segment(p, vec2(0.014, 0.005), vec2(0.014, 0.031)));
    arrow = min(arrow, segment(p, vec2(-0.014, 0.031), vec2(0.014, 0.031)));
    return arrow;
}

void fragment() {
    float outline = box(UV, vec2(0.5), vec2(0.493), 0.024);
    if (outline > 0.0 || UV.x + UV.y < 0.085) { discard; }
    // Small guide notches interrupt the folded leading edge at the shoulders.
    if (UV.x < 0.022 && ((UV.y > 0.143 && UV.y < 0.166) ||
                         (UV.y > 0.849 && UV.y < 0.876))) { discard; }
    vec3 plastic = shell_color.rgb;
    vec3 color = plastic * (0.94 + 0.06 * (1.0 - UV.y));
    color += (grain(floor(UV * 640.0)) - 0.5) * 0.025;
    if (outline > -0.010) { color *= 0.66; }
    else if (outline > -0.019) { color = mix(color, vec3(0.94), 0.15 * (1.0 - UV.y)); }
    vec2 upright = vec2(1.0 - UV.y, UV.x);
    float marks = mould_marks(upright);
    float mark_light = mould_marks(upright - vec2(0.002, 0.002));
    color += plastic * (1.0 - smoothstep(0.0015, 0.0035, mark_light)) * 0.20;
    color *= 1.0 - (1.0 - smoothstep(0.0015, 0.0035, marks)) * 0.27;
    // The disk is displayed sideways: metal shutter left, label right.
    // The shutter folds over the leading edge, rather than floating inside
    // a metal frame. A larger shallow moulded pocket remains visible below it.
    float recess = box(UV, vec2(0.177, 0.512), vec2(0.177, 0.385), 0.022);
    if (recess < 0.002) { color = plastic * 0.76; }
    if (recess < -0.003) { color = plastic * 0.94; }
    if (recess < -0.007) { color = plastic * 0.98; }
    float shutter = box(UV, vec2(0.157, 0.49), vec2(0.170, 0.309), 0.018);
    // Only the trailing two corners are rounded; the folded edge runs off
    // the left side of the sideways disk, just as on the reference.
    if (UV.x < 0.025) { shutter = max(UV.y - 0.799, 0.181 - UV.y); }
    if (shutter < 0.0) {
        float brushed = (grain(vec2(floor(UV.x * 1700.0), 7.0)) - 0.5) * 0.018;
        float stipple = (grain(floor(UV * 980.0)) - 0.5) * 0.037;
        float satin = smoothstep(0.0, 0.34, UV.x) * 0.14 + UV.y * 0.06;
        color = vec3(0.51, 0.535, 0.535) + satin + brushed + stipple;
        // A thin rolled rim and contact shadow replace the old thick border.
        if (shutter > -0.0025) { color *= 0.67; }
        else if (shutter > -0.005) { color += vec3(0.09); }
        if (UV.x < 0.016) { color *= 0.76; }
        else if (UV.x < 0.021) { color += vec3(0.08); }
        // Narrow off-centre opening: exposed shell, with metal thickness
        // visible along its cut edge. Most of the shutter remains solid metal.
        float window = box(UV, vec2(0.173, 0.315), vec2(0.118, 0.080), 0.003);
        if (window < 0.0025) {
            color = vec3(0.24, 0.27, 0.26);
            if (window < -0.002) {
                color = plastic * (UV.x < 0.063 || UV.y < 0.244 ? 0.83 : 0.98);
                color += (grain(floor(UV * 640.0)) - 0.5) * 0.025;
            }
        }
    }
    float label = box(UV, vec2(0.66, 0.50), vec2(0.265, 0.389), 0.018);
    if (label < 0.006) { color = plastic * 0.73; }
    if (label < 0.0) {
        color = vec3(0.88, 0.88, 0.82) + (grain(floor(UV * 720.0)) - 0.5) * 0.018;
        vec2 art_uv = (UV - vec2(0.395, 0.111)) / vec2(0.530, 0.778);
        if (has_artwork) { color = texture(artwork, art_uv).rgb; }
        else { color *= 1.0 - step(0.96, fract(art_uv.y * 9.0)) * 0.11; }
    }
    // Write-protect/density apertures and a moulded seam.
    if (box(UV, vec2(0.91, 0.063), vec2(0.033, 0.022), 0.003) < 0.0 ||
        box(UV, vec2(0.91, 0.937), vec2(0.033, 0.022), 0.003) < 0.0) { color = vec3(0.10, 0.13, 0.14); }
    if (abs(UV.x - 0.96) < 0.002 && UV.y > 0.15 && UV.y < 0.86) { color *= 0.72; }
    COLOR = vec4(color, 1.0);
}
