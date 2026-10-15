shader_type canvas_item;
// Darkens the screen edges so the eye goes to the middle (the lobby character).

uniform float strength = 0.55;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * vec2(1.25, 1.0);
	float v = smoothstep(0.35, 0.85, length(d));
	COLOR = vec4(0.0, 0.0, 0.0, v * strength);
}
