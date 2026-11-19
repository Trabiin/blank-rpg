shader_type canvas_item;
render_mode blend_mul;
// Darker screen edges (docs/ART_STYLE.md). Ambience sizes this rect to the camera's view each frame.

uniform float amount = 0.4;
uniform vec3 undo = vec3(1.0);  // 1 / the CanvasModulate colour, which tints this rect too

void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.75);
	float v = smoothstep(0.22, 0.62, length(d));
	COLOR = vec4(vec3(1.0 - v * amount) * undo, 1.0);
}
