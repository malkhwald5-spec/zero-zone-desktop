shader_type spatial;
// Island terrain: heights come from a heightmap texture (vertex shader), colours
// are blended from height, slope and a painted mask (roads, fields, towns,
// forest floor in alpha).

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D maskmap : filter_linear, repeat_disable;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform float map_size = 3072.0;
uniform float texel = 0.001953125; // 1 / (N - 1)
// Photo textures (CC0, ambientCG): colour + normal per ground type.
uniform sampler2D grass_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_c : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normals = true;

varying vec3 wpos;
varying float hgt;

// Sample i of the heightmap sits at x = i * step, i.e. at the centre of texel i.
float H(vec2 uv) { return textureLod(heightmap, (uv * 512.0 + 0.5) / 513.0, 0.0).r; }

void vertex() {
	vec2 uv = (VERTEX.xz + map_size * 0.5) / map_size;
	float h = H(uv);
	VERTEX.y = h;
	float st = map_size * texel;
	float hl = H(uv - vec2(texel, 0.0)), hr = H(uv + vec2(texel, 0.0));
	float hd = H(uv - vec2(0.0, texel)), hu = H(uv + vec2(0.0, texel));
	NORMAL = normalize(vec3(hl - hr, 2.0 * st, hd - hu));
	UV = uv;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	hgt = h;
}

// Two scales, the second rotated, mixed by a noise value: hides tiling.
vec2 rot2(vec2 p) { return vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8); }
vec3 tcol(sampler2D t, vec2 p, float sc, float k) {
	return mix(texture(t, p / sc).rgb, texture(t, rot2(p) / (sc * 2.7) + 0.31).rgb, k);
}
vec2 tnrm(sampler2D t, vec2 p, float sc) {
	return texture(t, p / sc).rg * 2.0 - 1.0;
}

void fragment() {
	vec4 mask = texture(maskmap, UV);
	float n1 = texture(noise_a, wpos.xz / 37.0).r;
	float n2 = texture(noise_b, wpos.xz / 7.0).r;
	float n3 = texture(noise_a, wpos.xz / 230.0).r;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - wn.y;
	float k = smoothstep(0.3, 0.7, n1) * 0.6 + 0.2;

	vec3 grass = tcol(grass_c, wpos.xz, 4.0, k) * mix(vec3(0.82, 0.9, 0.7), vec3(1.0, 0.95, 0.75), n3);
	vec3 dirt = tcol(dirt_c, wpos.xz, 3.5, k);
	vec3 sand = tcol(sand_c, wpos.xz, 4.0, k);
	vec3 asphalt = tcol(asphalt_c, wpos.xz, 5.0, k) * 0.85;
	vec3 paved = tcol(concrete_c, wpos.xz, 6.0, k) * 0.55;
	// Rock: triplanar so steep slopes are not stretched.
	vec3 tw = pow(abs(wn), vec3(4.0));
	tw /= (tw.x + tw.y + tw.z);
	vec3 rock = texture(rock_c, wpos.zy / 6.0).rgb * tw.x + texture(rock_c, wpos.xz / 6.0).rgb * tw.y + texture(rock_c, wpos.xy / 6.0).rgb * tw.z;
	vec3 field = mix(dirt, vec3(0.55, 0.45, 0.2), 0.45) * (0.85 + 0.15 * sin(wpos.x * 1.4));
	vec3 wet = sand * 0.5;
	vec3 moss = tcol(moss_c, wpos.xz, 3.0, k);
	vec3 litter = mix(tcol(forest_c, wpos.xz, 3.0, k) * vec3(0.85, 0.85, 0.8), moss, 0.25 + smoothstep(0.35, 0.65, n1) * 0.5);
	float n4 = texture(noise_b, wpos.xz / 160.0 + 0.5).r;

	// Layer weights (each step blends the previous result towards a layer).
	float w_dirt = max(smoothstep(0.62, 0.8, n3) * 0.55, smoothstep(0.6, 0.78, n2 * 0.6 + n1 * 0.4) * 0.4);
	float w_moss = smoothstep(0.55, 0.72, n4) * 0.75;
	float w_forest = smoothstep(0.1, 0.65, mask.a) * (0.75 + 0.25 * n2);
	float w_field = mask.g;
	float w_town = mask.b * 0.9;
	float w_rock = max(smoothstep(0.32, 0.5, slope), smoothstep(48.0, 58.0, hgt));
	float w_sand = 1.0 - smoothstep(1.6, 2.6, hgt + (n2 - 0.5) * 0.8);
	float w_wet = 1.0 - smoothstep(0.0, 0.7, hgt);
	float w_road = smoothstep(0.3, 0.6, mask.r);

	vec3 col = mix(grass, moss, w_moss);
	col = mix(col, dirt, w_dirt);
	col = mix(col, litter, w_forest);
	col = mix(col, field, w_field);
	// Towns: yards of trampled grass and dirt, with paved patches.
	float paved_k = smoothstep(0.5, 0.62, n1);
	col = mix(col, mix(mix(grass, dirt, 0.5), paved, paved_k), w_town);
	col = mix(col, rock, w_rock);
	col = mix(col, sand, w_sand);
	col = mix(col, wet, w_wet);
	col = mix(col, asphalt, w_road);
	col *= 0.85 + 0.3 * n3;     // large-scale colour variation
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.8, w_road);
	SPECULAR = 0.3;
	if (use_normals) {
		float near = 1.0 - smoothstep(40.0, 140.0, dist);
		vec2 nb = tnrm(grass_n, wpos.xz, 4.0);
		nb = mix(nb, tnrm(moss_n, wpos.xz, 3.0), w_moss);
		nb = mix(nb, tnrm(dirt_n, wpos.xz, 3.5), w_dirt);
		nb = mix(nb, tnrm(forest_n, wpos.xz, 3.0), w_forest);
		nb = mix(nb, tnrm(dirt_n, wpos.xz, 3.5), w_field);
		nb = mix(nb, tnrm(dirt_n, wpos.xz, 3.5) * 0.6, w_town);
		nb = mix(nb, tnrm(rock_n, wpos.xz, 6.0) * 1.3, w_rock);
		nb = mix(nb, tnrm(sand_n, wpos.xz, 4.0), w_sand);
		nb = mix(nb, tnrm(asphalt_n, wpos.xz, 5.0), w_road);
		// Tangent space (u = +x, v = +z) to world, then to view space.
		vec3 bent = normalize(wn + vec3(nb.x, 0.0, -nb.y) * 0.9 * near);
		NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);
	}
}
