shader_type spatial;
// Tree crowns: per-instance colour, baked occlusion in UV.x, leaf-cluster
// noise in world space, soft translucency and a gentle wind sway.

uniform float sway = 0.25;

varying vec3 lpos;
varying vec3 wpos;

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = sin(TIME * 1.3 + base.x * 0.13 + base.z * 0.11) + 0.3 * sin(TIME * 3.7 + VERTEX.x * 9.0);
	float up = max(VERTEX.y + 0.4, 0.0);
	VERTEX.x += w * sway * up * 0.04;
	VERTEX.z += w * sway * 0.5 * up * 0.04;
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	float ao = UV.x;
	float n = vnoise(wpos * 1.6) * 0.6 + vnoise(wpos * 4.3) * 0.4;
	float clump = smoothstep(0.25, 0.75, n);
	vec3 col = COLOR.rgb * mix(0.55, 1.15, clump) * mix(0.45, 1.0, ao);
	col = mix(col, col * vec3(1.15, 1.1, 0.7), smoothstep(0.7, 0.95, vnoise(wpos * 0.7)) * 0.5);
	ALBEDO = col;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	// Bumpy leaf clusters.
	float e = 0.05;
	float nx = vnoise((wpos + vec3(e, 0, 0)) * 4.3) - vnoise(wpos * 4.3);
	float nz = vnoise((wpos + vec3(0, 0, e)) * 4.3) - vnoise(wpos * 4.3);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(nx, 0.0, nz, 0.0)).xyz * 6.0);
	BACKLIGHT = col * 0.4;
	AO = mix(0.6, 1.0, ao);
	AO_LIGHT_AFFECT = 0.4;
}
