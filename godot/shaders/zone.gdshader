shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
// The edge of the safe zone, drawn as the disaster that lives in each part of
// the island: a wall of fire and ash round the volcano, a white snowstorm in
// the north, a sandstorm over the desert and a dark rain storm elsewhere.
// Billowing noise rolls along it; it fades out towards the top.

uniform sampler2D biomemap : filter_linear, repeat_disable;   // R desert, G forest, B north, A volcano
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform float map_size = 4096.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 b = texture(biomemap, clamp(wpos.xz / map_size, 0.0, 1.0));
	float rest = clamp(1.0 - b.r - b.b - b.a, 0.0, 1.0);
	vec3 storm = vec3(0.22, 0.27, 0.36);
	vec3 col = storm * rest + vec3(0.78, 0.6, 0.36) * b.r + vec3(0.9, 0.94, 1.0) * b.b + vec3(0.95, 0.32, 0.06) * b.a;
	float h = UV.y;                                    // 0 at the top, 1 at the bottom
	vec2 p = vec2(UV.x * 160.0, h * 6.0);
	float n = texture(noise_a, p * 0.11 + vec2(TIME * 0.02, -TIME * 0.05)).r * 0.6
		+ texture(noise_a, p * 0.37 - vec2(TIME * 0.05, TIME * 0.09)).r * 0.4;
	float billow = smoothstep(0.3, 0.8, n);
	// Embers glow inside the volcano wall.
	vec3 hot = vec3(1.0, 0.55, 0.1) * b.a * smoothstep(0.65, 0.9, n) * 1.6;
	ALBEDO = col * mix(0.65, 1.15, billow) + hot;
	float fade = smoothstep(0.0, 0.75, h);
	ALPHA = clamp((0.32 + billow * 0.3 + b.b * 0.12 + b.r * 0.08) * fade, 0.0, 0.85);
}
