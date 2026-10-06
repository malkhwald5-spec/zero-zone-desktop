shader_type spatial;
render_mode cull_disabled;
// Tree leaves / pine needles on alpha-tested cards. Normals point out of the
// crown so it lights as one soft volume; light shines through from behind.
// Per-instance colour tints each tree; UV2.x is baked occlusion.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.5;
uniform float sway = 1.0;
uniform float translucency = 0.55;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y - 2.0, 0.0);
	float gust = sin(TIME * 0.6 + base.x * 0.02 + base.z * 0.015) * 0.5 + 0.5;
	float w = sin(TIME * 1.1 + base.x * 0.13 + base.z * 0.11) * (0.5 + gust * 0.5);
	VERTEX.xz += vec2(w, w * 0.6) * sway * h * 0.01;
	// Leaf flutter.
	VERTEX += NORMAL * sin(TIME * 3.7 + dot(VERTEX, vec3(2.3, 1.7, 2.9)) + base.x) * 0.04 * sway * (0.4 + gust);
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	// Mipmaps average alpha away: boost it with distance so far trees stay full.
	float lod = textureQueryLod(albedo_tex, UV).y;
	ALPHA = t.a * (1.0 + max(lod, 0.0) * 0.35);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	float ao = UV2.x;
	vec3 col = t.rgb * COLOR.rgb * mix(0.4, 1.0, ao);
	ALBEDO = col;
	if (!FRONT_FACING) NORMAL = -NORMAL;     // keep the crown-shaped normal on both sides
	ROUGHNESS = 0.7;
	SPECULAR = 0.35;
	BACKLIGHT = col * translucency;
	AO = mix(0.5, 1.0, ao);
	AO_LIGHT_AFFECT = 0.35;
}
