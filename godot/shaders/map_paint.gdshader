shader_type canvas_item;
// Turns the top-down capture of the island into a clean map: water coloured
// by depth with a light shore line, the land a bit crisper, and hill shading
// from the height map.

uniform sampler2D photo : source_color, filter_linear;
uniform sampler2D heights : filter_linear;
uniform sampler2D mask : filter_linear;   // R >= 0.5: road
uniform sampler2D biomes : filter_linear;  // R desert, G jungle, B north, A beach island
uniform float texel = 0.00195;   // one height sample in uv

float h(vec2 uv) { return texture(heights, uv).r; }

void fragment() {
	vec2 uv = UV;
	float y = h(uv);
	vec3 land = texture(photo, uv).rgb;
	// Clear the haze: more contrast and colour.
	land = clamp((land - 0.05) * 1.12, 0.0, 1.0);
	float grey = dot(land, vec3(0.299, 0.587, 0.114));
	land = mix(vec3(grey), land, 0.92);
	// Regions read clearly from above: deep green jungle, cooler north.
	vec4 bio = texture(biomes, uv);
	land *= mix(vec3(1.0), vec3(0.62, 0.86, 0.55), bio.g * 0.85);
	land *= mix(vec3(1.0), vec3(0.88, 0.92, 0.9), bio.b * 0.6);
	// Hill shade, light from the north-west.
	float dx = h(uv + vec2(texel, 0.0)) - h(uv - vec2(texel, 0.0));
	float dz = h(uv + vec2(0.0, texel)) - h(uv - vec2(0.0, texel));
	vec3 n = normalize(vec3(-dx, 16.0, -dz));
	float shade = dot(n, normalize(vec3(-0.6, 0.9, -0.6)));
	land *= 0.62 + 0.5 * shade;
	// Roads: light asphalt (a little wider than the mask, to cover the photo's).
	float road = texture(mask, uv).r;
	float mt = 1.0 / 2048.0;
	road = max(road, max(max(texture(mask, uv + vec2(mt, 0.0)).r, texture(mask, uv - vec2(mt, 0.0)).r),
		max(texture(mask, uv + vec2(0.0, mt)).r, texture(mask, uv - vec2(0.0, mt)).r)));
		land = mix(land, vec3(0.66, 0.64, 0.6), smoothstep(0.55, 0.75, road));
	// Water by depth.
	float depth = -y;
	vec3 shallow = vec3(0.36, 0.66, 0.70);
	vec3 deep = vec3(0.10, 0.27, 0.42);
	vec3 water = mix(shallow, deep, smoothstep(0.0, 14.0, depth));
	water = mix(water, vec3(0.86, 0.92, 0.90), (1.0 - smoothstep(0.05, 0.7, depth)) * 0.55);
	float wet = smoothstep(-0.15, 0.15, depth);
	COLOR = vec4(mix(land, water, wet), 1.0);
}
