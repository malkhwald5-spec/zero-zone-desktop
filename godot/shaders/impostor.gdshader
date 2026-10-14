shader_type spatial;
render_mode cull_disabled;
// Far trees: photo cards of the detailed models (tools/bake_impostors.gd).
// Upright cards fade out when looked at from straight above, where the card
// of the crown seen from above takes over. Per-instance colour tints each tree.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alpha_cut = 0.5;
uniform float translucency = 0.4;

varying float steep;

void vertex() {
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
	steep = to_cam.y;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	// Mipmaps average alpha away: boost it with distance so far crowns stay full.
	float lod = textureQueryLod(albedo_tex, UV).y;
	float a = t.a * (1.0 + max(lod, 0.0) * 0.45);
	float top = UV2.x;
	// Upright cards thin out from above; the top card only shows from above.
	a *= top > 0.5 ? smoothstep(0.25, 0.6, steep) : 1.0 - smoothstep(0.8, 0.97, steep) * 0.6;
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALBEDO = t.rgb * COLOR.rgb * 0.92;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = ALBEDO * translucency;
}
