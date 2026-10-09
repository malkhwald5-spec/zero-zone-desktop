shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Painted battlefield art behind the lobby: shown as is, with a soft fade at
// the bottom so it melts into the sand in front.
uniform sampler2D tex : source_color, filter_linear_mipmap;

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	ALBEDO = c * 1.05;
	ALPHA = smoothstep(1.0, 0.86, UV.y);
}
