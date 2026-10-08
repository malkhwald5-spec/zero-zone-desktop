shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
// Ground clutter around the player: wild grasses and weeds (photo cards from an
// atlas of 4 plants), fallen branches and small stones. The instances sit on a
// regular grid that snaps with the player; everything else (jitter, turn, size,
// which plant, whether it is there at all) comes from a hash of the world
// position, so nothing changes or pops as the patch moves.

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform float hm_cells = 1024.0;
uniform sampler2D maskmap : filter_linear, repeat_disable;
uniform sampler2D biomemap : filter_linear, repeat_disable;   // R desert, G jungle, B north, A beach island
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform float map_size = 3072.0;
uniform vec3 center = vec3(0.0);
uniform float radius = 60.0;
uniform float spacing = 2.0;
uniform float density = 0.4;          // share of grid points that get something
uniform vec4 biome_k = vec4(0.1, 1.0, 1.0, 0.6);   // how much grows in desert, jungle, north, beach (plains = 1)
uniform float cluster = 0.5;          // 0 = even, 1 = in patches
uniform vec2 size_range = vec2(0.7, 1.3);
uniform float sink = 0.0;             // pushed into the ground (metres)
uniform bool cards = true;            // atlas plant cards (alpha) or a solid mesh
uniform bool tilt_to_ground = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform vec3 tint = vec3(1.0);
uniform vec3 desert_tint = vec3(1.0);    // colour shift in the desert (sandy stones)
uniform float uv_scale = 1.0;
uniform float wind_k = 1.0;

varying float tip;
varying float shade;
varying float column;
varying vec3 wpos;
varying vec3 wnrm;
varying float desert;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float h_at(vec2 xz) {
	vec2 uv = xz / map_size;
	return textureLod(heightmap, (uv * hm_cells + 0.5) / (hm_cells + 1.0), 0.0).r;
}

void vertex() {
	vec3 grid = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec2 cell = floor(grid.xz / spacing + 0.5);
	float r1 = hash(cell);
	float r2 = hash(cell + 17.3);
	float r3 = hash(cell + 41.9);
	vec3 base = grid + vec3(r1 - 0.5, 0.0, r2 - 0.5) * spacing * 0.9;
	vec2 uv = base.xz / map_size;
	float h = h_at(base.xz);
	vec4 m = textureLod(maskmap, uv, 0.0);
	vec4 bio = textureLod(biomemap, uv, 0.0);
	float plains = clamp(1.0 - bio.r - bio.g - bio.b - bio.a, 0.0, 1.0);
	float grow = plains + bio.r * biome_k.x + bio.g * biome_k.y + bio.b * biome_k.z + bio.a * biome_k.w;
	float patchy = mix(1.0, smoothstep(0.35, 0.7, textureLod(noise_a, base.xz / 53.0 + 0.17, 0.0).r) * 2.0, cluster);
	float d = distance(base.xz, center.xz);
	float keep = step(r3, density * grow * patchy)
		* (1.0 - smoothstep(radius * 0.75, radius, d))
		* step(2.4, h) * (1.0 - step(0.25, m.r)) * (1.0 - step(0.5, m.b)) * (1.0 - step(0.5, m.g));
	// Not on steep slopes (cliffs).
	float dx = h_at(base.xz + vec2(1.0, 0.0)) - h_at(base.xz - vec2(1.0, 0.0));
	float dz = h_at(base.xz + vec2(0.0, 1.0)) - h_at(base.xz - vec2(0.0, 1.0));
	vec3 gn = normalize(vec3(-dx, 2.0, -dz));
	keep *= step(0.8, gn.y);
	float ang = hash(cell + 7.7) * 6.2832;
	float sc = mix(size_range.x, size_range.y, hash(cell + 3.1)) * keep;
	column = floor(hash(cell + 9.4) * 4.0);
	vec3 local = (VERTEX - grid) * sc;
	mat3 rot = mat3(vec3(cos(ang), 0.0, -sin(ang)), vec3(0.0, 1.0, 0.0), vec3(sin(ang), 0.0, cos(ang)));
	local = rot * local;
	vec3 n = rot * NORMAL;
	vec3 t = rot * TANGENT;
	if (tilt_to_ground) {
		// Lie along the slope.
		vec3 x = normalize(cross(gn, vec3(0.0, 0.0, 1.0)));
		vec3 z = cross(x, gn);
		mat3 lay = mat3(-x, gn, z);
		local = lay * local;
		n = lay * n;
		t = lay * t;
	}
	tip = cards ? clamp(1.0 - UV.y, 0.0, 1.0) : 1.0;
	if (cards && wind_k > 0.0) {
		float wind = sin(TIME * 1.6 + base.x * 0.21 + base.z * 0.17) * 0.12 + sin(TIME * 2.9 + base.x * 0.5) * 0.04;
		local.xz += vec2(wind, wind * 0.6) * tip * tip * wind_k * sc;
	}
	shade = mix(0.85, 1.15, hash(cell + 5.5));
	desert = bio.r;
	VERTEX = vec3(base.x, h - sink * sc, base.z) + local;
	NORMAL = cards ? vec3(0.0, 1.0, 0.0) : n;
	TANGENT = t;
	wpos = VERTEX;
	wnrm = n;
}

void fragment() {
	if (cards) {
		vec2 auv = vec2((column + clamp(UV.x, 0.01, 0.99)) * 0.25, UV.y);
		vec4 c = texture(albedo_tex, auv);
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = 0.45;
		ALBEDO = c.rgb * tint * shade * mix(0.6, 1.0, smoothstep(0.0, 0.5, tip));
		ROUGHNESS = 0.85;
		SPECULAR = 0.3;
		BACKLIGHT = c.rgb * 0.25 * tip;
		AO = mix(0.5, 1.0, tip);
		AO_LIGHT_AFFECT = 0.3;
	} else {
		vec2 tuv = UV * uv_scale;
		ALBEDO = texture(albedo_tex, tuv).rgb * tint * shade * mix(vec3(1.0), desert_tint, desert);
		if (use_normal) NORMAL_MAP = texture(normal_tex, tuv).rgb;
		ROUGHNESS = 0.92;
	}
}
