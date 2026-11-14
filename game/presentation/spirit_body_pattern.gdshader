shader_type spatial;
// The torso with a patterned body skin (presentation/kit/skin_pattern.gd): the
// same flat marks as the head (skin_pattern.gdshaderinc) in the torso's own
// coordinates. Colour only, on the torso's own mesh; shared by every pip
// wearing the skin.
#include "res://presentation/skin_pattern.gdshaderinc"
varying vec3 body_pos;

void vertex() {
	body_pos = VERTEX;
}

void fragment() {
	ALBEDO = pattern_color(body_pos);
	ROUGHNESS = 0.9;
}
