shader_type spatial;
// Island terrain: heights come from a heightmap texture (vertex shader), colours
// are blended from height, slope and a painted mask (roads, fields, towns).

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D maskmap : filter_linear, repeat_disable;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform float map_size = 3072.0;
uniform float texel = 0.001953125; // 1 / (N - 1)

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

void fragment() {
	vec4 mask = texture(maskmap, UV);
	float n1 = texture(noise_a, wpos.xz / 37.0).r;
	float n2 = texture(noise_b, wpos.xz / 7.0).r;
	float n3 = texture(noise_a, wpos.xz / 230.0).r;
	float n4 = texture(noise_b, wpos.xz / 1.3).r;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(30.0, 90.0, dist);
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - wn.y;

	vec3 grass = mix(vec3(0.12, 0.2, 0.06), vec3(0.2, 0.28, 0.08), n1);
	grass = mix(grass, vec3(0.3, 0.3, 0.13), smoothstep(0.55, 0.85, n3) * 0.6);
	grass *= 0.8 + n2 * 0.35;
	vec3 dirt = mix(vec3(0.26, 0.2, 0.13), vec3(0.34, 0.27, 0.18), n2);
	vec3 rock = mix(vec3(0.3, 0.29, 0.27), vec3(0.42, 0.41, 0.38), n2);
	vec3 sand = mix(vec3(0.52, 0.46, 0.33), vec3(0.6, 0.54, 0.4), n2);
	vec3 wet = vec3(0.24, 0.21, 0.15);
	vec3 field = mix(vec3(0.46, 0.38, 0.16), vec3(0.54, 0.45, 0.2), n2) * (0.85 + 0.15 * sin(wpos.x * 1.4));
	vec3 asphalt = mix(vec3(0.09, 0.09, 0.1), vec3(0.15, 0.15, 0.16), n2);
	vec3 paved = mix(vec3(0.32, 0.3, 0.27), vec3(0.4, 0.37, 0.33), n2);

	vec3 col = grass;
	col = mix(col, dirt, smoothstep(0.62, 0.8, n3) * 0.5);
	col = mix(col, dirt, smoothstep(0.62, 0.78, n2 * 0.6 + n4 * 0.4) * 0.45);
	col = mix(col, field, mask.g);
	col = mix(col, mix(dirt, paved, 0.6), mask.b * 0.9);
	float rocky = max(smoothstep(0.32, 0.5, slope), smoothstep(48.0, 58.0, hgt));
	col = mix(col, rock, rocky);
	float sandy = 1.0 - smoothstep(1.6, 2.6, hgt + (n2 - 0.5) * 0.8);
	col = mix(col, sand, sandy);
	col = mix(col, wet, 1.0 - smoothstep(0.0, 0.7, hgt));
	float road = smoothstep(0.3, 0.6, mask.r);
	col = mix(col, asphalt, road);
	// Close-up grain so the ground does not look like flat paint.
	col *= mix(1.0, 0.82 + n4 * 0.36, near);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, road);
	SPECULAR = 0.3;
	// Detail normal from the fine noise.
	float e = 0.02;
	float dx = texture(noise_b, (wpos.xz + vec2(e * 1.3, 0.0)) / 1.3).r - n4;
	float dz = texture(noise_b, (wpos.xz + vec2(0.0, e * 1.3)) / 1.3).r - n4;
	float bump = mix(1.2, 3.0, rocky + sandy * 0.5) * (1.0 - road * 0.7) * (1.0 - mask.b * 0.6) * near;
	vec3 bn = normalize(vec3(-dx * bump / e * 0.05, 1.0, -dz * bump / e * 0.05));
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bn.x, 0.0, bn.z, 0.0)).xyz);
}
