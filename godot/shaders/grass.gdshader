shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// Grass tufts (photo blades on crossed cards) in a patch that follows the
// player. Each clump is placed on the terrain using the heightmap, sways in
// the wind and shrinks away at the edge.

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform float hm_cells = 1024.0;   // heightmap samples per side - 1
uniform sampler2D maskmap : filter_linear, repeat_disable;
uniform sampler2D biomemap : filter_linear, repeat_disable;   // R desert, G jungle, B north, A beach island
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform float map_size = 3072.0;
uniform vec3 center = vec3(0.0);
uniform float radius = 40.0;
uniform sampler2D grass_c : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tuft : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
varying vec3 ground_col;

varying float tip;
varying float tint;
varying float dry;

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 uv = base.xz / map_size;
	float h = textureLod(heightmap, (uv * hm_cells + 0.5) / (hm_cells + 1.0), 0.0).r;
	vec4 m = textureLod(maskmap, uv, 0.0);
	float d = distance(base.xz, center.xz);
	float keep = (1.0 - smoothstep(radius * 0.6, radius, d)) * step(2.4, h) * (1.0 - step(0.25, m.r)) * (1.0 - step(0.5, m.b) * step(0.56, textureLod(noise_a, base.xz / 37.0, 0.0).r)) * (1.0 - step(0.5, m.g) * 0.4) * (1.0 - smoothstep(0.3, 0.9, m.a) * 0.7);
	vec4 bio = textureLod(biomemap, uv, 0.0);
	// Hardly any grass in the desert (a few dry tufts), tall in the jungle.
	keep *= 1.0 - bio.r * step(0.18, textureLod(noise_a, base.xz / 13.0, 0.0).r) * 0.97;
	tip = 1.0 - UV.y;
	tint = textureLod(noise_a, base.xz / 31.0, 0.0).r;
	dry = textureLod(noise_a, base.xz / 97.0 + 0.3, 0.0).r;
	// Same colour as the ground texture under the clump (blurred mip), so blades blend in.
	ground_col = textureLod(grass_c, base.xz / 4.0, 6.0).rgb;
	vec3 local = VERTEX - base;
	local.y *= keep * (0.6 + tint * 0.9) * (1.0 + bio.g * 0.6 - bio.b * 0.2);
	dry = max(dry, bio.r);
	local.xz *= mix(0.3, 1.0, keep);
	float gust = sin(TIME * 0.7 + base.x * 0.03 + base.z * 0.02) * 0.5 + 0.5;
	float wind = sin(TIME * 1.8 + base.x * 0.21 + base.z * 0.17) * (0.06 + gust * 0.1) + sin(TIME * 3.1 + base.x * 0.5) * 0.03;
	local.xz += vec2(wind, wind * 0.6) * tip * tip;
	VERTEX = vec3(base.x, h - 0.05, base.z) + local;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	vec4 t = texture(tuft, UV);
	float lod = textureQueryLod(tuft, UV).y;
	ALPHA = t.a * (1.0 + max(lod, 0.0) * 0.35);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// Photo colour pulled towards the ground texture underneath so the patch
	// edge disappears into the terrain, with patchy fresh / dry areas.
	float lum = (t.r + t.g + t.b) / 3.0;
	vec3 col = mix(t.rgb, ground_col * lum * 7.0, 0.4);
	col *= mix(0.85, 1.15, tint);
	col = mix(col, col * vec3(1.25, 1.05, 0.6), smoothstep(0.6, 0.85, dry) * 0.6);
	ALBEDO = col * mix(0.55, 1.0, smoothstep(0.0, 0.6, tip));
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	AO = mix(0.4, 1.0, tip);
	AO_LIGHT_AFFECT = 0.3;
	BACKLIGHT = col * 0.2 * tip;
}
