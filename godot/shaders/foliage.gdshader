shader_type spatial;
// Tree canopies: per-instance colour and a gentle wind sway.

uniform float sway = 0.25;

void vertex() {
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = sin(TIME * 1.3 + base.x * 0.13 + base.z * 0.11);
	VERTEX.x += w * sway * max(VERTEX.y, 0.0) * 0.12;
	VERTEX.z += w * sway * 0.5 * max(VERTEX.y, 0.0) * 0.12;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	BACKLIGHT = COLOR.rgb * 0.35;
}
