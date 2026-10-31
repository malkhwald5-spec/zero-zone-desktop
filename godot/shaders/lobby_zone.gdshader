shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// The zone's wall as seen from far off in the lobby: a curtain of light,
// brightest where it meets the sea, streaks of energy crawling up it.
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec4 col : source_color = vec4(1.0, 0.42, 0.14, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.8, 0.45, 1.0);

void fragment() {
	float h = clamp(UV.y, 0.0, 1.0);          // 0 at the top, 1 at the bottom
	float n = texture(noise, vec2(UV.x * 30.0 + TIME * 0.004, h * 1.5 - TIME * 0.05)).r;
	float n2 = texture(noise, vec2(UV.x * 110.0 - TIME * 0.01, h * 4.0 - TIME * 0.14)).r;
	float streak = smoothstep(0.45, 0.85, n * 0.55 + n2 * 0.45);
	float base = pow(h, 2.5);
	vec3 c = col.rgb * (0.35 + streak * 1.1) * (0.35 + base * 1.8);
	c += hot.rgb * smoothstep(0.9, 1.0, h) * 2.2;
	ALBEDO = c;
	ALPHA = smoothstep(0.15, 0.85, h) * 0.9;
}
