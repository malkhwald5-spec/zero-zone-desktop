shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// Grass blades in a patch that follows the player. Each blade is placed on the
// terrain using the heightmap, sways in the wind and fades out at the edge.

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D maskmap : filter_linear, repeat_disable;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform float map_size = 3072.0;
uniform vec3 center = vec3(0.0);
uniform float radius = 40.0;

varying float tip;
varying float tint;

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 uv = base.xz / map_size;
	float h = textureLod(heightmap, (uv * 512.0 + 0.5) / 513.0, 0.0).r;
	vec4 m = textureLod(maskmap, uv, 0.0);
	float d = distance(base.xz, center.xz);
	float keep = (1.0 - smoothstep(radius * 0.7, radius, d)) * step(2.2, h) * (1.0 - step(0.25, m.r)) * (1.0 - step(0.5, m.b));
	tip = 1.0 - UV.y;
	tint = textureLod(noise_a, base.xz / 31.0, 0.0).r;
	vec3 local = VERTEX - base;
	local.y *= keep * (0.7 + tint * 0.8);
	local.xz *= keep;
	float wind = sin(TIME * 1.8 + base.x * 0.21 + base.z * 0.17) * 0.12 + sin(TIME * 3.1 + base.x * 0.5) * 0.04;
	local.xz += vec2(wind, wind * 0.6) * tip * tip;
	VERTEX = vec3(base.x, h, base.z) + local;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec3 lo = vec3(0.16, 0.24, 0.07);
	vec3 hi = mix(vec3(0.38, 0.5, 0.17), vec3(0.5, 0.52, 0.22), tint);
	ALBEDO = mix(lo, hi, tip);
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.25, 0.35, 0.1) * tip;
}
