shader_type spatial;
// A pip's trail marks (kit/trail_kit.gd): one MultiMesh per pip, a mark per
// instance, all drawn with this one shared material. Each mark lies flat on
// the floor where the pip passed (in a picture of a pip it stands up beside
// it), turns and drifts a little, holds and then fades out by the end of its life. Placed by the
// instance's transform; the instance's custom data holds its birth (seconds
// of the pip's own trail clock), its first turn, its drift's heading and
// which of the two colours it takes. The clock is an instance uniform written
// from the pip's own clock while a mark lives, never the engine's time.
// Unlit and see-through at most `opacity`, writing no depth, so pads, floor
// letters and pair tags drawn after it stay on top.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// How strong a fresh mark is: at most 0.38 on the floor (kit/trail_kit.gd
// OPACITY); a pictured pip's still sample is drawn stronger.
instance uniform float trail_opacity = 0.38;
instance uniform float trail_clock = 0.0;
// Seconds a mark lives, metres a second it drifts, radians a second it turns.
instance uniform float trail_life = 0.8;
instance uniform float trail_drift = 0.04;
instance uniform float trail_spin = 0.35;
// The two colours (the palette's values), and the race ghost's strength.
instance uniform vec3 trail_color_a = vec3(1.0);
instance uniform vec3 trail_color_b = vec3(1.0);
instance uniform float veil = 1.0;

const float HOLD = 0.55;
varying float fade;
varying vec3 tint;

void vertex() {
	float age = trail_clock - INSTANCE_CUSTOM.x;
	float alive = age >= 0.0 && age <= trail_life ? 1.0 : 0.0;
	age = max(age, 0.0);
	// Full strength for the first HOLD of its life, then fading to nothing,
	// so a short row of marks reads behind a walking pip.
	fade = alive * (1.0 - smoothstep(HOLD, 1.0, age / trail_life));
	// Half the marks turn one way, half the other (from the drift's heading).
	float turn_way = sin(INSTANCE_CUSTOM.z * 7.0) < 0.0 ? -1.0 : 1.0;
	float a = INSTANCE_CUSTOM.y + turn_way * trail_spin * age;
	vec2 turned = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xz;
	vec2 drift = vec2(cos(INSTANCE_CUSTOM.z), sin(INSTANCE_CUSTOM.z)) * trail_drift * age;
	VERTEX = vec3(turned.x + drift.x, VERTEX.y, turned.y + drift.y) * alive;
	// The shape's own shade (its darker outer band, kit/flat_shapes.gd, in UV.x) on the colour.
	tint = (INSTANCE_CUSTOM.w < 0.5 ? trail_color_a : trail_color_b) * UV.x;
}

void fragment() {
	ALBEDO = tint;
	ALPHA = fade * trail_opacity * veil;
}
