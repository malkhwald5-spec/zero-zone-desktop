shader_type spatial;
// Land behind the lobby: rock on the slopes, grass on the flats, sand along
// the water; the headland under the squad is bare rock and dust.
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile = 0.2;
uniform float near = 0.0;
uniform float sea = -30.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wn), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 rock = texture(rock_tex, wp.zy * tile).rgb * w.x + texture(rock_tex, wp.xz * tile).rgb * w.y + texture(rock_tex, wp.xy * tile).rgb * w.z;
	vec3 grass = texture(grass_tex, wp.xz * tile).rgb * vec3(0.9, 0.92, 0.75);
	vec3 sand = texture(sand_tex, wp.xz * tile).rgb;
	float slope = 1.0 - wn.y;
	float rk = smoothstep(0.22, 0.42, slope);
	float sk = 1.0 - smoothstep(sea + 3.0, sea + 9.0, wp.y);
	vec3 c = mix(mix(grass, sand, sk), rock, rk);
	// The headland: dusty rock, warm.
	c = mix(c, mix(rock, sand, 0.35) * vec3(1.0, 0.93, 0.85), near * (1.0 - sk));
	// The volcano's upper slopes: dark ash.
	c = mix(c, rock * vec3(0.3, 0.28, 0.27), smoothstep(45.0, 100.0, wp.y));
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
