shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// A weapon skin, drawn over the gun's own material (as an overlay) so its
// shape and detail still read through: a colour scheme worked out from the
// position along the gun (the gun's frame: barrel along -Z).
//  kind 0 neon gradient   1 gold   2 camo   3 dragon stripes   4 carbon
uniform int kind = 0;
uniform vec4 c1 : source_color = vec4(0.45, 0.2, 0.95, 1.0);
uniform vec4 c2 : source_color = vec4(0.15, 0.55, 1.0, 1.0);
uniform vec4 c3 : source_color = vec4(1.0, 0.3, 0.7, 1.0);
uniform float scale = 1.0;      // the mesh's own size (imported parts in other units)
uniform float glow = 0.0;

varying vec3 lp;

void vertex() {
	lp = VERTEX * scale;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = vec2(lp.z, lp.y);
	vec3 col;
	float metal = 0.4;
	float rough = 0.35;
	vec3 emit = vec3(0.0);
	if (kind == 0) {
		// Neon: purple to blue along the gun, pink streaks across it.
		float g = clamp(-lp.z * 1.2 + 0.4, 0.0, 1.0);
		col = mix(c1.rgb, c2.rgb, g);
		float st = smoothstep(0.82, 0.9, fract(lp.z * 6.0 + lp.y * 9.0));
		col = mix(col, c3.rgb, st);
		emit = c3.rgb * st * glow;
		metal = 0.55; rough = 0.25;
	} else if (kind == 1) {
		// Gold with fine engraved swirls.
		float e = vnoise(p * 60.0) * 0.5 + vnoise(p * 140.0) * 0.5;
		col = c1.rgb * mix(0.75, 1.1, e);
		metal = 1.0; rough = 0.18 + e * 0.12;
	} else if (kind == 2) {
		// Camo: three blotchy colours.
		float n = vnoise(p * 9.0 + lp.x * 4.0) * 0.65 + vnoise(p * 22.0) * 0.35;
		col = n < 0.42 ? c1.rgb : (n < 0.6 ? c2.rgb : c3.rgb);
		metal = 0.1; rough = 0.7;
	} else if (kind == 3) {
		// Dragon: black with red scale bands and a hot edge.
		float b = fract(lp.z * 5.0 + sin(lp.y * 30.0) * 0.08);
		float band = smoothstep(0.55, 0.62, b) * (1.0 - smoothstep(0.88, 0.95, b));
		col = mix(c1.rgb, c2.rgb, band);
		emit = c3.rgb * smoothstep(0.86, 0.9, b) * (1.0 - smoothstep(0.9, 0.95, b)) * glow;
		metal = 0.6; rough = 0.3;
	} else {
		// Carbon weave.
		vec2 q = floor(p * 90.0);
		float w = mod(q.x + q.y, 2.0);
		col = mix(c1.rgb, c2.rgb, w * 0.6);
		metal = 0.3; rough = 0.3;
	}
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	EMISSION = emit;
	ALPHA = 0.9;
}
