shader_type spatial;
// A floor's baked grounding (kit/contact_shadows.gd bakes it once a world is
// built): a flat overlay just over the floor that multiplies what is under it,
// so the floor keeps its own colour and light. The texture holds, per spot:
//   r: how dark it is where something stands on the floor (soft, footprint
//      shaped, the darkest of overlapping feet, never their sum);
//   g: how worn the grass is round a base (a wider, browner patch);
//   b: the sun's soft shadow of the static scenery standing on this floor.
// One texture read; Balanced and High add a little flattened grass and grit
// in the worn patch from the floor position alone.
render_mode unshaded, blend_mul, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform sampler2D shade : filter_linear, repeat_disable, hint_default_black;
// What full shade multiplies the floor by: a warm dark, so a lawn stays green.
uniform vec3 dark_tint = vec3(0.50, 0.47, 0.40);
// What a fully worn patch multiplies the floor by: browner and a little darker.
uniform vec3 worn_tint = vec3(0.80, 0.70, 0.52);
uniform float contact_strength = 0.62;
uniform float cast_strength = 0.30;
uniform float worn_strength = 0.45;
// Flattened grass and grit in the worn patch (off on Low).
uniform bool detail = true;

varying vec2 spot;

void vertex() {
	spot = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

// A cheap hash with no sine (steady on phone GPUs).
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec3 s = texture(shade, UV).rgb;
	float worn = s.g * worn_strength;
	if (detail && s.g > 0.01) {
		// Flattened grass: short streaks a little more or less worn.
		worn *= mix(0.7, 1.15, hash(floor(spot * vec2(7.0, 26.0))));
		// Grit: a few small dark specks where it is most worn.
		vec2 cell = floor(spot * 16.0);
		vec2 at = vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.6 + 0.2;
		float speck = step(0.8, hash(cell)) * (1.0 - smoothstep(0.10, 0.18, distance(fract(spot * 16.0), at)));
		worn = max(worn, speck * s.g * 0.85);
	}
	float dark = max(s.r * contact_strength, s.b * cast_strength);
	ALBEDO = mix(vec3(1.0), worn_tint, clamp(worn, 0.0, 1.0)) * mix(vec3(1.0), dark_tint, clamp(dark, 0.0, 1.0));
}
