shader_type spatial;
render_mode unshaded, fog_disabled;
// The sea round the island, seen from the cliff: deep blue under you, the
// warm sky laid over it towards the horizon, a path of sun glitter.
uniform sampler2D waves : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(-0.38, 0.12, -0.92);       // towards the sun
uniform vec4 deep : source_color = vec4(0.03, 0.12, 0.17, 1.0);
uniform vec4 sky : source_color = vec4(0.93, 0.66, 0.48, 1.0);
uniform vec4 glint : source_color = vec4(1.0, 0.82, 0.55, 1.0);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wp.xz * 0.02;
	vec3 n1 = texture(waves, uv + vec2(TIME * 0.006, TIME * 0.004)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(waves, uv * 3.1 - vec2(TIME * 0.011, -TIME * 0.006)).rgb * 2.0 - 1.0;
	vec3 n = normalize(vec3((n1.x + n2.x) * 0.12, 1.0, (n1.y + n2.y) * 0.12));
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(wp - cam);
	vec3 r = reflect(v, n);
	float fres = pow(1.0 - clamp(dot(-v, n), 0.0, 1.0), 4.0);
	vec3 c = mix(deep.rgb, sky.rgb * 0.7, clamp(fres * 0.5, 0.0, 1.0));
	c += glint.rgb * pow(max(dot(r, normalize(sun_dir)), 0.0), 220.0) * 3.0;
	// Haze over the far water, as the sky meets it.
	float far = 1.0 - exp(-length(wp - cam) * 0.0007);
	ALBEDO = mix(c, sky.rgb * 0.8, far * 0.35);
}
