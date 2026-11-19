shader_type canvas_item;
// Low mist (docs/ART_STYLE.md): two noise layers drifting past each other, banded into a few soft steps so
// it reads as pixel art rather than a smooth blur. Ambience sets amount (time of day x the player's slider).

uniform sampler2D noise : repeat_enable, filter_linear;
uniform float amount = 0.5;
uniform vec2 wind = vec2(3.0, 0.6);
uniform vec3 tint = vec3(0.78, 0.82, 0.9);
varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 w = floor(world);
	float a = texture(noise, (w - TIME * wind) / 360.0).r;
	float b = texture(noise, (w + TIME * wind * vec2(0.6, -1.4)) / 230.0 + vec2(0.5, 0.2)).r;
	float m = smoothstep(0.42, 0.75, a * 0.6 + b * 0.4);
	m = floor(m * 4.0) / 4.0;  // a few steps, pixel style
	COLOR = vec4(tint, m * 0.38 * amount);
}
