shader_type spatial;
// The spirit face with the Tide body cosmetic (presentation/pip_wear/tide.gd):
// two wavy lines of foam with little bubbles round the head, one under the
// eyes and one above them, and a deeper shade of the body colour below the
// low line. skin_phase moves the waves; it is written from the spirit's own
// clock, never TIME.
uniform float skin_phase = 0.0;
uniform vec3 deep_color : source_color = vec3(0.8);
const vec3 FOAM = vec3(1.0, 0.969, 0.91);

float tide_y(float a) {
	return -0.18 + 0.011 * sin(a * 7.0 + skin_phase);
}

vec3 skin_color(vec3 p, vec3 body) {
	float a = atan(p.x, p.z);
	float w = max(fwidth(p.y), 1e-4);
	float line = tide_y(a);
	vec3 c = mix(body, deep_color, clamp(0.5 - (p.y - line) / w, 0.0, 1.0));
	float foam = abs(p.y - line) - 0.0105;
	c = mix(c, FOAM, clamp(0.5 - foam / w, 0.0, 1.0));
	float seg = 6.2831853 / 22.0;
	float k = floor(a / seg + 0.5);
	float ac = k * seg;
	float lift = 0.024 + 0.008 * sin(k * 2.7);
	float r = 0.0068 - 0.0022 * step(0.5, fract(k * 0.5));
	float d = length(vec2((a - ac) * 0.33, p.y - (tide_y(ac) + lift))) - r;
	c = mix(c, FOAM, clamp(0.5 - d / max(fwidth(d), 1e-4), 0.0, 1.0));
	// The second wave wraps the head above the eyes (eye tops at y 0.105), so
	// the pattern also shows from the chapters' high cameras.
	float top_line = 0.168 + 0.01 * sin(a * 6.0 - skin_phase + 1.3);
	float foam2 = abs(p.y - top_line) - 0.0105;
	c = mix(c, FOAM, clamp(0.5 - foam2 / w, 0.0, 1.0));
	float k2 = floor((a + seg * 0.5) / seg + 0.5);
	float ac2 = k2 * seg - seg * 0.5;
	float lift2 = 0.026 + 0.009 * sin(k2 * 1.9);
	float r2 = 0.0068 - 0.0022 * step(0.5, fract(k2 * 0.5));
	float d2 = length(vec2((a - ac2) * 0.33, p.y - (0.168 + 0.01 * sin(ac2 * 6.0 - skin_phase + 1.3) + lift2))) - r2;
	c = mix(c, FOAM, clamp(0.5 - d2 / max(fwidth(d2), 1e-4), 0.0, 1.0));
	return c;
}

#define SPIRIT_SKIN
#include "res://presentation/spirit_face.gdshaderinc"
