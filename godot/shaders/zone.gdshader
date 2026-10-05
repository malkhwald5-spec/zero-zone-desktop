shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
// The blue zone wall: translucent blue with slowly moving vertical stripes,
// fading out towards the top.

void fragment() {
	float h = UV.y;                       // 0 at the top, 1 at the bottom
	float stripes = 0.5 + 0.5 * sin(UV.x * 900.0 + TIME * 1.5);
	float fade = smoothstep(0.0, 0.7, h);
	ALBEDO = mix(vec3(0.1, 0.3, 1.0), vec3(0.45, 0.7, 1.0), stripes * 0.5);
	ALPHA = (0.34 + stripes * 0.14) * fade;
}
