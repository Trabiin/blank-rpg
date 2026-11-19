shader_type canvas_item;
render_mode blend_mul;
// Cloud shadows drifting over the field (docs/ART_STYLE.md): a soft noise mask, multiplied over the world.
// Snapped to world pixels so the edges stay crisp at game zoom. Ambience follows the camera with this rect
// and sets strength, scale and wind from Options > Visual effects.

uniform sampler2D noise : repeat_enable, filter_linear;
uniform float strength = 0.22;
uniform float scale = 520.0;  // world pixels per noise tile: bigger = bigger clouds
uniform vec2 wind = vec2(5.0, 2.0);  // world pixels per second
uniform vec3 undo = vec3(1.0);  // 1 / the CanvasModulate colour, which tints this rect too
uniform vec3 shade = vec3(0.66, 0.70, 0.84);
varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = (floor(world) - TIME * wind) / scale;
	float n = texture(noise, p).r * 0.75 + texture(noise, p * 2.3 + vec2(0.31, 0.77)).r * 0.25;
	float s = smoothstep(0.5, 0.62, n);
	COLOR = vec4(mix(vec3(1.0), shade, s * strength / 0.22) * undo, 1.0);
}
