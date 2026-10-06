shader_type spatial;
// Building walls (plaster, brick, stone). Box faces are axis-aligned in the
// building's local space, so each face is mapped straight onto the texture.
// Vertex colour tints the paint; dirt gathers near the ground and rain leaves
// streaks down the walls.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_noise : filter_linear_mipmap, repeat_enable;
uniform float tile = 3.0;           // metres per texture repeat
uniform float tint_amount = 1.0;    // 0 = texture colour only, 1 = multiplied by vertex colour
uniform float grime = 1.0;
uniform float bump = 1.0;
uniform float roughness = 0.9;

varying vec3 lpos;
varying vec3 lnrm;

void vertex() {
	lpos = VERTEX;
	lnrm = NORMAL;
}

void fragment() {
	vec3 an = abs(lnrm);
	vec2 uv;
	vec3 t;
	vec3 b;
	if (an.y > an.x && an.y > an.z) {
		uv = lpos.xz; t = vec3(1, 0, 0); b = vec3(0, 0, -1);
	} else if (an.x > an.z) {
		uv = lpos.zy; t = vec3(0, 0, 1); b = vec3(0, 1, 0);
	} else {
		uv = lpos.xy; t = vec3(1, 0, 0); b = vec3(0, 1, 0);
	}
	uv = uv / tile * vec2(1.0, -1.0);
	vec3 col = texture(albedo_tex, uv).rgb * mix(vec3(1.0), COLOR.rgb, tint_amount);
	float wall_x = lpos.x + lpos.z;
	float ground = 1.0 - smoothstep(0.0, 1.3, lpos.y);
	float splash = texture(grime_noise, vec2(wall_x * 0.7, lpos.y * 0.9)).r;
	col *= mix(1.0, 0.68 + splash * 0.15, ground * grime);
	float streak = texture(grime_noise, vec2(wall_x * 1.3, lpos.y * 0.05)).r;
	col = mix(col, col * vec3(0.8, 0.78, 0.72), smoothstep(0.6, 0.85, streak) * grime * 0.3 * (1.0 - ground));
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.35;
	vec2 n = texture(normal_tex, uv).rg * 2.0 - 1.0;
	vec3 bent = normalize(lnrm + (t * n.x + b * n.y) * bump);
	NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(bent, 0.0)).xyz);
}
