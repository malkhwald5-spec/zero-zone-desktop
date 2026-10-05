shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// Grass clumps in a patch that follows the player. Each clump is placed on the
// terrain using the heightmap, sways in the wind and shrinks away at the edge.

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D maskmap : filter_linear, repeat_disable;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform float map_size = 3072.0;
uniform vec3 center = vec3(0.0);
uniform float radius = 40.0;

varying float tip;
varying float tint;
varying float dry;

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 uv = base.xz / map_size;
	float h = textureLod(heightmap, (uv * 512.0 + 0.5) / 513.0, 0.0).r;
	vec4 m = textureLod(maskmap, uv, 0.0);
	float d = distance(base.xz, center.xz);
	float keep = (1.0 - smoothstep(radius * 0.6, radius, d)) * step(2.4, h) * (1.0 - step(0.25, m.r)) * (1.0 - step(0.5, m.b)) * (1.0 - step(0.5, m.g) * 0.4);
	tip = 1.0 - UV.y;
	tint = textureLod(noise_a, base.xz / 31.0, 0.0).r;
	dry = textureLod(noise_a, base.xz / 97.0 + 0.3, 0.0).r;
	vec3 local = VERTEX - base;
	local.y *= keep * (0.6 + tint * 0.9);
	local.xz *= mix(0.3, 1.0, keep);
	float gust = sin(TIME * 0.7 + base.x * 0.03 + base.z * 0.02) * 0.5 + 0.5;
	float wind = sin(TIME * 1.8 + base.x * 0.21 + base.z * 0.17) * (0.06 + gust * 0.1) + sin(TIME * 3.1 + base.x * 0.5) * 0.03;
	local.xz += vec2(wind, wind * 0.6) * tip * tip;
	VERTEX = vec3(base.x, h - 0.05, base.z) + local;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec3 lo = vec3(0.05, 0.09, 0.02);
	vec3 hi = mix(vec3(0.17, 0.26, 0.06), vec3(0.24, 0.29, 0.08), tint);
	hi = mix(hi, vec3(0.36, 0.33, 0.14), smoothstep(0.55, 0.8, dry) * 0.7);
	ALBEDO = mix(lo, hi, smoothstep(0.0, 0.8, tip));
	ROUGHNESS = 0.85;
	SPECULAR = 0.35;
	AO = mix(0.35, 1.0, tip);
	AO_LIGHT_AFFECT = 0.3;
	BACKLIGHT = vec3(0.18, 0.26, 0.06) * tip;
}
