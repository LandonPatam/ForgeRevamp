shader_type canvas_item;
render_mode unshaded;
void fragment() {
	float line = 1.0 - step(1.0, mod(FRAGCOORD.y, 3.0));
	COLOR = vec4(0.0, 0.0, 0.0, line * 0.11);
}
