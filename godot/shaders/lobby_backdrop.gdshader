shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
// Painted battlefield art behind the lobby: slightly soft (like a camera
// focused on the character in front), with a soft fade at the bottom so it
// melts into the sand.
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float soften = 1.6;     // mip level: how out of focus

void fragment() {
	vec3 c = textureLod(tex, UV, soften).rgb;
	ALBEDO = c * 1.05;
	ALPHA = smoothstep(1.0, 0.86, UV.y);
}
