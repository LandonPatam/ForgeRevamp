shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec4 pixel = texture(TEXTURE, UV) * COLOR;
	float value = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(0.24, 1.0, 0.92) * value, pixel.a);
}
