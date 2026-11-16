// Paints dirt paths over the grass with smooth, organic edges.
// TEXTURE is the map's path mask (1 texel per tile, linear filtered); it is blurred and
// wobbled with noise, then thresholded per screen pixel and filled with the repeating dirt tile.
// The same mood grading and Blank fade as world_tint.gdshader are applied.
shader_type canvas_item;

uniform sampler2D dirt_tex : repeat_enable, filter_nearest;
uniform vec2 tiles = vec2(80.0, 60.0);
uniform vec3 fringe = vec3(0.145, 0.33, 0.18);
uniform float blank_x = 1100.0;
uniform float fade_width = 300.0;
uniform float desat = 0.4;
uniform vec3 tint = vec3(0.8, 0.86, 0.97);

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
	vec2 px = floor(UV * tiles * 16.0) + 0.5;  // snap to whole pixels for crisp pixel art
	// 4-tap blur of the (already bilinear) mask rounds off corners.
	vec2 to_uv = 1.0 / (16.0 * tiles);
	float m = 0.25 * (texture(TEXTURE, (px + vec2(-5.0, -5.0)) * to_uv).r
		+ texture(TEXTURE, (px + vec2(5.0, -5.0)) * to_uv).r
		+ texture(TEXTURE, (px + vec2(-5.0, 5.0)) * to_uv).r
		+ texture(TEXTURE, (px + vec2(5.0, 5.0)) * to_uv).r);
	m += (value_noise(px / 7.0) - 0.5) * 0.22 + (value_noise(px / 2.5) - 0.5) * 0.06;

	vec4 col = vec4(0.0);
	if (m > 0.5) {
		col = texture(dirt_tex, px / 16.0);
	} else if (m > 0.43) {
		col = vec4(fringe, 1.0);
	}
	float l = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	vec3 c = mix(col.rgb, vec3(l), desat) * tint;
	float f = clamp((px.x - (blank_x - fade_width)) / fade_width, 0.0, 1.0);
	c = mix(c, mix(vec3(l), vec3(0.95, 0.94, 0.9), 0.6), f * f * 0.95);
	COLOR = vec4(c, col.a);
}
