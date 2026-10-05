shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;
// Sea / river surface: animated waves, fresnel tint and shore foam (from the heightmap).

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D noise_a : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_b : filter_linear_mipmap, repeat_enable;
uniform float map_size = 3072.0;
uniform vec3 deep_color : source_color = vec3(0.04, 0.19, 0.27);
uniform vec3 shallow_color : source_color = vec3(0.1, 0.42, 0.45);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wpos.x * 0.05 + TIME * 1.2) * 0.12 + cos(wpos.z * 0.07 + TIME * 0.9) * 0.1;
	VERTEX.y += w;
}

void fragment() {
	vec2 uv = wpos.xz / map_size;
	float ground = -30.0;
	if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) ground = textureLod(heightmap, (uv * 512.0 + 0.5) / 513.0, 0.0).r;
	float depth = clamp(-ground / 12.0, 0.0, 1.0);
	vec2 t = vec2(TIME * 0.02, TIME * 0.015);
	float n = texture(noise_a, wpos.xz / 23.0 + t).r * 0.5 + texture(noise_b, wpos.xz / 9.0 - t * 1.7).r * 0.5;
	vec3 nrm = normalize(vec3((n - 0.5) * 0.35, 1.0, (texture(noise_a, wpos.zx / 17.0 - t).r - 0.5) * 0.35));
	NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(shallow_color, deep_color, depth);
	col = mix(col, vec3(0.55, 0.72, 0.85), fres * 0.6);
	// Foam where the water is very shallow.
	float foam = (1.0 - smoothstep(0.0, 0.9, -ground)) * step(-ground, 1.6) * smoothstep(0.45, 0.7, n + sin(TIME * 1.5 + wpos.x * 0.3) * 0.1);
	col = mix(col, vec3(0.92, 0.95, 0.95), foam * 0.8);
	ALBEDO = col;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.75, 0.94, depth);
}
