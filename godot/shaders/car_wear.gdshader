shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Laid over a car (as an overlay): the life it has had. Dried mud thick on the
// sills and wheel arches thinning up the doors, a film of dust on the top,
// and (camo cars) a blotchy two-tone paint on the body below the windows.
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec4 mud : source_color = vec4(0.36, 0.3, 0.22, 1.0);
uniform float dirt = 0.7;        // 0 clean .. 1 caked
uniform float camo = 0.0;        // 1: the body painted in camo
uniform vec4 camo_a : source_color = vec4(0.22, 0.23, 0.25, 1.0);
uniform vec4 camo_b : source_color = vec4(0.62, 0.64, 0.66, 1.0);
uniform vec4 camo_c : source_color = vec4(0.08, 0.08, 0.09, 1.0);
uniform float window_y = 1.3;    // camo stops here (glass above)

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	float n = texture(noise, lp.xz * 0.35 + lp.y * 0.21).r;
	float n2 = texture(noise, vec2(lp.z, lp.y) * 1.3 + lp.x * 0.4).r;
	// Mud: thickest low down, splashed up in streaks.
	float low = 1.0 - smoothstep(0.25, 1.0 + n2 * 0.5, lp.y);
	float m = clamp(low * (0.55 + n * 0.8) * dirt, 0.0, 1.0);
	// Dust settled on the upward faces.
	float top = smoothstep(0.6, 0.95, ln.y) * (0.25 + n2 * 0.3) * dirt;
	vec3 col = mud.rgb;
	float a = max(m, top * 0.6);
	if (camo > 0.5 && lp.y < window_y && ln.y < 0.8) {
		float c = texture(noise, lp.xz * 0.45 + vec2(lp.y * 0.6)).r * 0.6 + texture(noise, vec2(lp.z, lp.y) * 0.9).r * 0.4;
		vec3 cc = c < 0.42 ? camo_a.rgb : (c < 0.58 ? camo_b.rgb : camo_c.rgb);
		col = mix(cc, mud.rgb, m);
		a = 1.0;
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.95, max(m, top));
	ALPHA = clamp(a, 0.0, 0.95);
}
