shader_type spatial;
// Boulders with photo-scanned rock surfaces, projected from three sides
// (triplanar) so the shapes need no UVs. Per instance (INSTANCE_CUSTOM):
// r = which rock (0 grey granite, 0.5 dark basalt, 1 layered sandstone),
// g = moss on the upward faces, b = tint variation.

uniform sampler2D col_grey : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_grey : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D col_dark : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_dark : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D col_sand : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_sand : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_col : source_color, filter_linear_mipmap, repeat_enable;
uniform float scale = 0.45;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 custom;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	custom = INSTANCE_CUSTOM;
}

vec3 tri_col(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}
vec3 tri_nrm(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = wpos * scale;
	vec3 c;
	vec3 nm;
	if (custom.r < 0.25) {
		c = tri_col(col_grey, p, w);
		nm = tri_nrm(nrm_grey, p, w);
	} else if (custom.r < 0.75) {
		c = tri_col(col_dark, p, w);
		nm = tri_nrm(nrm_dark, p, w);
	} else {
		// Sandstone layers run level across the boulder.
		c = tri_col(col_sand, p * vec3(1.0, 1.6, 1.0), w) * vec3(1.15, 0.94, 0.76);
		nm = tri_nrm(nrm_sand, p * vec3(1.0, 1.6, 1.0), w);
	}
	c *= mix(0.85, 1.12, custom.b);
	// Moss grows on the tops, patchy.
	float up = smoothstep(0.35, 0.85, wnrm.y);
	float patch = texture(moss_col, wpos.xz * 0.11).g;
	float moss = clamp(up * custom.g * smoothstep(0.25, 0.5, patch + up * 0.25), 0.0, 1.0);
	vec3 mc = texture(moss_col, wpos.xz * 0.6).rgb * vec3(0.8, 0.95, 0.65);
	ALBEDO = mix(c, mc, moss);
	NORMAL_MAP = mix(nm, vec3(0.5, 0.5, 1.0), moss * 0.6);
	NORMAL_MAP_DEPTH = 1.4;
	ROUGHNESS = mix(0.88, 0.95, moss);
	SPECULAR = 0.35;
}
