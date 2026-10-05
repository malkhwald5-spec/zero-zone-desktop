shader_type sky;
// Daytime sky: blue gradient, bright haze at the horizon, sun disk with glow,
// and two layers of drifting procedural clouds.

uniform vec3 zenith : source_color = vec3(0.16, 0.36, 0.72);
uniform vec3 horizon : source_color = vec3(0.66, 0.78, 0.9);
uniform vec3 ground : source_color = vec3(0.42, 0.5, 0.55);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.48;
uniform float cloud_speed = 0.004;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.45));
	} else {
		col = mix(horizon, ground, clamp(-up * 4.0, 0.0, 1.0));
	}
	// Sun
	vec3 sd = normalize(LIGHT0_DIRECTION);
	float sdot = max(dot(d, sd), 0.0);
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	col += sun_col * pow(sdot, 900.0) * 6.0;            // disk
	col += sun_col * pow(sdot, 12.0) * 0.18;            // glow
	col += vec3(1.0, 0.9, 0.75) * pow(sdot, 3.0) * 0.08 * (1.0 - clamp(up * 2.0, 0.0, 1.0));
	// Clouds on a plane high above.
	if (up > 0.01 && !AT_CUBEMAP_PASS) {
		vec2 uv = d.xz / (up + 0.08) * 1.6;
		float t = TIME * cloud_speed;
		float c1 = fbm(uv * 1.3 + vec2(t, t * 0.6));
		float c2 = fbm(uv * 3.1 - vec2(t * 1.7, 0.0));
		float c = c1 * 0.75 + c2 * 0.25;
		float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, c);
		cov *= smoothstep(0.01, 0.18, up);                  // thin out at the horizon
		float lit = 0.75 + 0.25 * pow(sdot, 4.0);
		vec3 cloud = mix(vec3(0.62, 0.66, 0.72), vec3(1.0, 0.98, 0.95), clamp(c2 * 1.4, 0.0, 1.0)) * lit;
		col = mix(col, cloud, cov * 0.92);
	} else if (up > 0.01) {
		// Ambient/reflection pass: soft average cloud tint.
		col = mix(col, vec3(0.85, 0.87, 0.9), cloud_cover * 0.35 * smoothstep(0.01, 0.3, up));
	}
	COLOR = col;
}
