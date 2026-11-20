shader_type spatial;
// A soft contact shadow where something meets the ground (kit/contact_shadows.gd):
// a flat quad, darkest over the thing's footprint and fading out past its edge.
// A world draws all of its shadows in one MultiMesh with this one look; a pip
// draws its own with the same look (spirit_visual.gd). Unlit and see-through,
// one colour, writing no depth, so overlapping shadows blend the same in any
// order and whatever stands on them draws over them.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.12, 0.23, 0.21);
// A MultiMesh instance gives its shape in INSTANCE_CUSTOM: the footprint's half
// width and depth (metres), how far the shadow fades out past it, and how round
// it is (0 a box, 1 an ellipse); its colour's alpha scales its strength.
// A single quad (a pip's) gives the shape here instead and is sized in metres.
uniform bool from_instance = true;
uniform vec4 shape = vec4(0.1, 0.1, 0.2, 1.0);
// The world's strength (the graphics quality softens it).
instance uniform float shadow_strength = 0.42;

varying vec2 local;
varying vec4 form;
varying float weight;

void vertex() {
	form = from_instance ? INSTANCE_CUSTOM : shape;
	// An instance's quad spans -1..1 scaled by its basis to the shadow's outer
	// size; a pip's mesh is already that size in metres.
	local = from_instance ? VERTEX.xz * (form.xy + form.z) : VERTEX.xz;
	weight = from_instance ? COLOR.a : 1.0;
}

void fragment() {
	// Distance (metres) outside the footprint, a rounded box whose corners are
	// as round as its `round` share of its shorter half.
	float corner = form.w * min(form.x, form.y);
	vec2 inside = max(form.xy - corner, vec2(0.0));
	float outside = length(max(abs(local) - inside, vec2(0.0))) - corner;
	float fade = clamp(1.0 - outside / max(form.z, 0.001), 0.0, 1.0);
	ALBEDO = tint;
	ALPHA = shadow_strength * weight * fade * fade * (3.0 - 2.0 * fade);
}
