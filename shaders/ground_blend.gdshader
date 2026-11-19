// Art pass ground layer (docs/ART_STYLE.md): paints a seamless ground texture (town cobbles) over the grass
// where the map says so, with ragged, mossy edges like the target plaza instead of a tile grid.
// TEXTURE is the map's mask (1 texel per tile, linear filtered); it is blurred and wobbled with noise, then
// thresholded per pixel. No colour grade (the art is palette-locked); the Blank fade matches world_tint.
shader_type canvas_item;

uniform sampler2D ground_tex : repeat_enable, filter_nearest;
uniform float tex_size = 128.0;
uniform vec2 tiles = vec2(80.0, 60.0);
uniform vec3 moss_dark = vec3(0.165, 0.227, 0.133);   // #2a3a22
uniform vec3 moss_light = vec3(0.239, 0.318, 0.188);  // #3d5130
uniform vec3 path_dark = vec3(0.227, 0.165, 0.110);   // #3a2a1c trodden earth
uniform vec3 path_mid = vec3(0.353, 0.243, 0.157);    // #5a3e28
uniform vec3 path_light = vec3(0.561, 0.510, 0.439);  // #8f8270 worn spots
uniform vec3 pebble = vec3(0.341, 0.357, 0.420);      // #575b6b
uniform float blank_x = 1e9;
uniform float fade_width = 300.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 px = floor(UV * tiles * 16.0) + 0.5;
	vec2 to_uv = 1.0 / (16.0 * tiles);
	float m = 0.25 * (texture(TEXTURE, (px + vec2(-6.0, -6.0)) * to_uv).r
		+ texture(TEXTURE, (px + vec2(6.0, -6.0)) * to_uv).r
		+ texture(TEXTURE, (px + vec2(-6.0, 6.0)) * to_uv).r
		+ texture(TEXTURE, (px + vec2(6.0, 6.0)) * to_uv).r);
	m += (value_noise(px / 9.0) - 0.5) * 0.30 + (value_noise(px / 3.0) - 0.5) * 0.12;
	// Footpaths (green): a tighter blur so a one-tile path stays narrow.
	float mp = 0.25 * (texture(TEXTURE, (px + vec2(-4.0, -4.0)) * to_uv).g
		+ texture(TEXTURE, (px + vec2(4.0, -4.0)) * to_uv).g
		+ texture(TEXTURE, (px + vec2(-4.0, 4.0)) * to_uv).g
		+ texture(TEXTURE, (px + vec2(4.0, 4.0)) * to_uv).g);
	mp += (value_noise(px / 5.0) - 0.5) * 0.2;
	vec4 col = vec4(0.0);
	if (m <= 0.52 && mp > 0.5) {
		float n = value_noise(px / 3.0) + (hash(floor(px)) - 0.5) * 0.25;
		col = vec4(n > 0.62 ? path_mid : path_dark, 1.0);
		if (mp > 0.68 && value_noise(px / 4.0 + 7.0) > 0.7) {
			col = vec4(path_light, 1.0);  // worn middle
		}
		if (hash(floor(px / 2.0) + 3.1) > 0.94) {
			col = vec4(pebble, 1.0);
		}
		if (mp < 0.56 && hash(floor(px / 2.0)) > 0.6) {
			col = vec4(moss_light, 1.0);  // grass creeping in at the edge
		}
	} else if (m > 0.52) {
		col = texture(ground_tex, px / tex_size);
		// Grass tufts pushing up between the stones near the edge.
		if (m < 0.62 && hash(floor(px / 2.0)) > 0.72) {
			col = vec4(moss_light, 1.0);
		}
	} else if (m > 0.47) {
		col = vec4(hash(floor(px / 2.0)) > 0.5 ? moss_light : moss_dark, 1.0);
	}
	float l = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	float f = clamp((px.x - (blank_x - fade_width)) / fade_width, 0.0, 1.0);
	col.rgb = mix(col.rgb, mix(vec3(l), vec3(0.95, 0.94, 0.9), 0.6), f * f * 0.95);
	COLOR = col;
}
