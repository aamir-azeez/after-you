// World kit: the pair tags' look (presentation/kit/pair_tags.gd). One mesh
// holds every tag of a stage; each vertex carries its pair (UV2.x) and its
// layer (UV2.y: 0 rim, 1 face, 2 letter and bands, 3 the glow under a tile),
// its colour in COLOR. states[pair] is (clear, lit): faint while both are 0,
// clear while a pip is near, lit while its control is active. Every number
// of the look comes from the kit, which sets each uniform; tests check the
// three states stay apart. Nothing here reads TIME: a tag changes only when
// the world sets new states.
shader_type spatial;
// Flat quads seen from above: no culling, so their winding never matters.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// MAX_STATES in pair_tags.gd.
uniform vec2 states[32];
// Colours come as the kit writes them, like the vertex colours, so every mix
// stays in one space.
// Faint alpha per layer (rim, face, letter).
uniform vec3 faint_alpha;
// Near: the face this much toward pale.
uniform float near_lighten;
uniform vec3 pale;
// Lit: the face and rim this much toward warm, glowing this strongly.
uniform float lit_lighten;
uniform float lit_glow;
uniform vec3 warm;
// The glow under a lit tile: its colour and strength at the centre.
uniform vec3 glow;
uniform float glow_alpha;

varying float clear;
varying float lit;
varying float layer;

void vertex() {
	int pair = clamp(int(UV2.x + 0.5), 0, 31);
	clear = states[pair].x;
	lit = states[pair].y;
	layer = UV2.y;
	// An unlit tile's glow folds to a point: it draws nothing at all.
	if (layer > 2.5 && lit < 0.5) VERTEX = vec3(0.0);
}

void fragment() {
	ROUGHNESS = 0.85;
	float shown = max(clear, lit);
	if (layer > 2.5) {
		// A pool of warm light, strongest under the tile, gone at its rim.
		float edge = smoothstep(0.5, 0.12, distance(UV, vec2(0.5)));
		ALBEDO = vec3(0.0);
		EMISSION = glow * lit;
		ALPHA = glow_alpha * edge * lit;
	} else if (layer > 1.5) {
		// The letter and bands stay ink in every state.
		ALBEDO = COLOR.rgb;
		ALPHA = mix(faint_alpha.z, 1.0, shown);
	} else {
		vec3 colour = COLOR.rgb;
		if (layer > 0.5) colour = mix(colour, pale, near_lighten * clear * (1.0 - lit));
		colour = mix(colour, warm, lit_lighten * lit);
		ALBEDO = colour;
		EMISSION = colour * lit_glow * lit;
		ALPHA = mix(layer > 0.5 ? faint_alpha.y : faint_alpha.x, 1.0, shown);
	}
}
