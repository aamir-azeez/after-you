shader_type spatial;
// The spirit face with a patterned body skin (presentation/kit/skin_pattern.gd:
// Knit, Night sky, Patchwork, Blue pottery, Autumn, Sea glass): the head's
// colour is the skin's flat marks (skin_pattern.gdshaderinc), the eyes and
// cheeks drawn over them by the shared face body. No time input.
#include "res://presentation/skin_pattern.gdshaderinc"

vec3 skin_color(vec3 p, vec3 body) {
	return pattern_color(p);
}

#define SPIRIT_SKIN
#include "res://presentation/spirit_face.gdshaderinc"
