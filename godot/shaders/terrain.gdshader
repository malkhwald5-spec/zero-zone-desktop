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

float H(vec2 uv) { return textureLod(heightmap, uv, 0.0).r; }

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
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - wn.y;

	vec3 grass = mix(vec3(0.24, 0.34, 0.13), vec3(0.36, 0.45, 0.17), n1);
	grass = mix(grass, vec3(0.42, 0.42, 0.2), smoothstep(0.55, 0.85, n3) * 0.6);
	grass *= 0.85 + n2 * 0.3;
	vec3 dirt = mix(vec3(0.36, 0.29, 0.2), vec3(0.45, 0.37, 0.26), n2);
	vec3 rock = mix(vec3(0.42, 0.41, 0.38), vec3(0.55, 0.54, 0.5), n2);
	vec3 sand = mix(vec3(0.76, 0.69, 0.5), vec3(0.84, 0.78, 0.6), n2);
	vec3 wet = vec3(0.33, 0.3, 0.22);
	vec3 field = mix(vec3(0.64, 0.55, 0.27), vec3(0.72, 0.62, 0.3), n2) * (0.9 + 0.1 * sin(wpos.x * 1.4));
	vec3 asphalt = mix(vec3(0.17, 0.17, 0.18), vec3(0.24, 0.24, 0.25), n2);

	vec3 col = grass;
	col = mix(col, dirt, smoothstep(0.62, 0.8, n3) * 0.5);
	col = mix(col, field, mask.g);
	col = mix(col, mix(dirt, vec3(0.5, 0.47, 0.42), 0.4), mask.b * 0.85);
	col = mix(col, rock, smoothstep(0.32, 0.5, slope));
	col = mix(col, rock, smoothstep(48.0, 58.0, hgt));
	col = mix(col, sand, 1.0 - smoothstep(1.6, 2.6, hgt));
	col = mix(col, wet, 1.0 - smoothstep(0.0, 0.7, hgt));
	// Roads with a dashed centre line.
	float road = smoothstep(0.3, 0.6, mask.r);
	col = mix(col, asphalt, road);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.7, road);
	SPECULAR = 0.25;
}
