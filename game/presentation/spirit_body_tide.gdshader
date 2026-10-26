shader_type spatial;
// The torso with the Tide body cosmetic (presentation/pip_wear/tide.gd): the
// pip's deeper shade with one wavy line of foam round the lower body. Colour
// only, on the torso's own mesh. skin_phase moves the wave; it is written from
// the spirit's own clock, never TIME.
uniform vec3 body_color : source_color = vec3(0.8);
uniform float skin_phase = 0.0;
const vec3 FOAM = vec3(1.0, 0.969, 0.91);
varying vec3 body_pos;

void vertex() {
	body_pos = VERTEX;
}

void fragment() {
	// The torso's visible part runs from y -0.15 to about 0.04 (its top is
	// inside the head); the stripe crosses the middle of it.
	float a = atan(body_pos.x, body_pos.z);
	float line = -0.035 + 0.009 * sin(a * 6.0 + skin_phase + 0.7);
	float w = max(fwidth(body_pos.y), 1e-4);
	float foam = abs(body_pos.y - line) - 0.0095;
	ALBEDO = mix(body_color, FOAM, clamp(0.5 - foam / w, 0.0, 1.0));
	ROUGHNESS = 0.9;
}
