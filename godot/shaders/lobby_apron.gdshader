shader_type spatial;
// Lobby ground: the airfield apron at dusk. Concrete slabs with dark joints,
// painted yellow taxi lines, a damp sheen that catches the sky, fading out
// into the distance.
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line(float v, float w) {
	return 1.0 - smoothstep(w * 0.5, w * 0.5 + 0.02, abs(v));
}

void fragment() {
	vec2 p = wpos.xz;
	vec3 c = texture(tex, p / 4.0).rgb * vec3(0.62, 0.63, 0.66);
	float n = texture(noise, p / 9.0).r;
	c *= 0.85 + n * 0.3;
	// Slab joints every 5 m.
	vec2 g = abs(fract(p / 5.0) - 0.5) * 5.0;
	float joint = 1.0 - smoothstep(2.44, 2.5, max(g.x, g.y));
	c *= mix(1.0, 0.55, 1.0 - joint);
	// Taxi line along the front and a curve towards the plane; a stop bar.
	float yel = line(p.y - 2.2, 0.16) + line(length(p - vec2(-7.0, -6.0)) - 8.2, 0.16) * step(p.y, 2.2) * step(p.x, -1.0);
	yel += line(p.x - 4.5, 0.5) * step(abs(p.y - 2.2), 1.2);
	c = mix(c, vec3(0.95, 0.68, 0.12), clamp(yel, 0.0, 1.0) * 0.85);
	ALBEDO = c;
	// Damp: smoother in the patches, so the dusk sky shows in it.
	ROUGHNESS = mix(0.35, 0.85, smoothstep(0.35, 0.65, n));
	SPECULAR = 0.6;
	ALPHA = 1.0 - smoothstep(-16.0, -34.0, wpos.z);
}
