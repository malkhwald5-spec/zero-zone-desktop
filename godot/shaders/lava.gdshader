shader_type spatial;
render_mode cull_disabled;
// Molten rock: bright orange cracks between slowly drifting dark crust.

uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 t = vec2(TIME * 0.006, TIME * 0.004);
	float n = texture(noise_a, wpos.xz / 23.0 + t).r * 0.6 + texture(noise_b, wpos.xz / 7.0 - t * 2.0).r * 0.4;
	float crust = smoothstep(0.48, 0.66, n);
	float pulse = 0.85 + 0.15 * sin(TIME * 1.3 + wpos.x * 0.05 + wpos.z * 0.04);
	vec3 hot = vec3(1.0, 0.3, 0.03);
	ALBEDO = mix(hot * 0.7, vec3(0.07, 0.05, 0.045), crust);
	EMISSION = mix(hot * 2.4 * pulse, vec3(0.2, 0.04, 0.0), crust);
	ROUGHNESS = mix(0.35, 0.95, crust);
}
