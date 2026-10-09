shader_type spatial;
// Lobby ground: sand under the character that fades out towards the backdrop.
uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = texture(tex, wpos.xz / 3.0).rgb * vec3(0.92, 0.78, 0.62);
	ALBEDO = c;
	ROUGHNESS = 0.95;
	// Fade away into the backdrop beyond about 12 m behind the character.
	ALPHA = 1.0 - smoothstep(-6.0, -15.0, wpos.z);
}
