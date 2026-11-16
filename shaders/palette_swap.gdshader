// Paper-doll recolor: swaps each exact source color for a target color.
// Every hero shares the same sprite layers; only these arrays differ.
shader_type canvas_item;

uniform int count = 0;
uniform vec4 src[24];
uniform vec4 dst[24];
uniform float flash = 0.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 c = tex.rgb;
	for (int i = 0; i < 24; i++) {
		if (i >= count) {
			break;
		}
		if (distance(tex.rgb, src[i].rgb) < 0.01) {
			c = dst[i].rgb;
			break;
		}
	}
	COLOR = vec4(mix(c, vec3(1.0), flash), COLOR.a);
}
