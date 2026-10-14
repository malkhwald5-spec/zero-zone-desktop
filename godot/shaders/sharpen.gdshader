shader_type canvas_item;
render_mode unshaded, blend_disabled;
// Contrast-adaptive sharpening (after AMD's CAS) over the finished 3D picture:
// brings back the detail that anti-aliasing and texture filtering soften,
// without ringing on hard edges.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float amount : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec3 n = texture(screen, SCREEN_UV + vec2(0.0, -px.y)).rgb;
	vec3 s = texture(screen, SCREEN_UV + vec2(0.0, px.y)).rgb;
	vec3 e = texture(screen, SCREEN_UV + vec2(px.x, 0.0)).rgb;
	vec3 w = texture(screen, SCREEN_UV + vec2(-px.x, 0.0)).rgb;
	vec3 lo = min(c, min(min(n, s), min(e, w)));
	vec3 hi = max(c, max(max(n, s), max(e, w)));
	// Less sharpening where the neighbourhood already has strong contrast.
	vec3 amp = sqrt(clamp(min(lo, 1.0 - hi) / max(hi, vec3(1e-4)), 0.0, 1.0));
	vec3 k = amp * (-1.0 / mix(8.0, 4.5, amount));
	vec3 res = (c + (n + s + e + w) * k) / (1.0 + 4.0 * k);
	COLOR = vec4(clamp(res, 0.0, 1.0), 1.0);
}
