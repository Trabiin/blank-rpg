// Mood grading for the CC0 tiles (bright Zelda-like greens -> muted, uneasy dusk)
// plus the Blank's erasure: colors drain to paper-white near its edge.
shader_type canvas_item;

uniform float blank_x = 1100.0;
uniform float fade_width = 300.0;
uniform float desat = 0.4;
uniform vec3 tint = vec3(0.8, 0.86, 0.97);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float l = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(tex.rgb, vec3(l), desat) * tint;
	float f = clamp((world_pos.x - (blank_x - fade_width)) / fade_width, 0.0, 1.0);
	vec3 paper = mix(vec3(l), vec3(0.95, 0.94, 0.9), 0.6);
	col = mix(col, paper, f * f * 0.95);
	COLOR = vec4(col, COLOR.a);
}
