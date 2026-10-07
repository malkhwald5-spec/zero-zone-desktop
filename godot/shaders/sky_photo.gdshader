shader_type sky;
// Real photographed sky (equirectangular panorama). The photo is turned so its
// sun sits where the game's sun light is, and the band between the horizon and
// the sun is stretched a little so their heights match too.

uniform sampler2D pano : source_color, filter_linear, repeat_enable;
uniform vec2 photo_sun = vec2(0.5, 0.4);    // where the sun is in the photo (uv)
uniform float energy = 1.0;
uniform float sun_boost = 3.0;               // brightens the burnt-out sun in the LDR photo
uniform vec3 haze : source_color = vec3(0.72, 0.78, 0.84);
uniform float haze_amount = 0.35;
uniform float overcast = 0.0;               // 0 clear .. 1 grey rain clouds

const float HALF_PI = 1.5707963;

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 l = normalize(LIGHT0_DIRECTION);
	float el = asin(clamp(d.y, -1.0, 1.0));
	float sun_el = clamp(asin(l.y), 0.05, 1.4);
	float photo_el = (0.5 - photo_sun.y) * PI;
	float e = el;
	if (el > 0.0) {
		e = el < sun_el ? el * photo_el / sun_el
			: photo_el + (el - sun_el) * (HALF_PI - photo_el) / (HALF_PI - sun_el);
	}
	float az = atan(d.x, d.z) - atan(l.x, l.z);
	vec2 uv = vec2(fract(az / TAU + photo_sun.x), 0.5 - e / PI);
	vec3 col = texture(pano, uv).rgb * energy;
	// The photo is clipped at white around the sun: lift it back up so the
	// sun and its glow are actually bright (bloom picks this up).
	float sdot = max(dot(d, l), 0.0);
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col += LIGHT0_COLOR * (smoothstep(0.85, 1.0, lum) * sun_boost * pow(sdot, 40.0) + pow(sdot, 1400.0) * 30.0);
	// Rain: the photo turns into a flat grey cloud deck, darker overhead.
	if (overcast > 0.0) {
		vec3 cloud = mix(vec3(0.62, 0.64, 0.67), vec3(0.36, 0.38, 0.41), smoothstep(0.0, 0.8, d.y));
		cloud *= 0.85 + 0.3 * texture(pano, uv * vec2(3.0, 1.5)).r;
		col = mix(col, cloud * energy, overcast);
	}
	// Blend toward the scene's fog colour low on the horizon so the far terrain meets it.
	float h = 1.0 - smoothstep(-0.02, 0.22, d.y);
	col = mix(col, haze, h * haze_amount);
	COLOR = col;
}
