// World kit: the pair tags' look (presentation/kit/pair_tags.gd). One mesh
// holds every tag of a stage; each vertex carries its pair (UV2.x) and its
// layer (UV2.y: 0 rim, 1 face, 2 letter and bands), its colour in COLOR.
// states[pair] is (clear, lit): faint while both are 0, clear when a pip is
// near, glowing while its control is active. Nothing here reads TIME: a tag
// changes only when the world sets new states.
shader_type spatial;
// Flat quads seen from above: no culling, so their winding never matters.
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// MAX_STATES in pair_tags.gd.
uniform vec2 states[32];

varying float clear;
varying float lit;
varying float layer;

void vertex() {
	int pair = clamp(int(UV2.x + 0.5), 0, 31);
	clear = states[pair].x;
	lit = states[pair].y;
	layer = UV2.y;
}

void fragment() {
	// Faint: a soft wash of the pair's colour and a whisper of its letter.
	float faint = layer > 1.5 ? 0.35 : (layer > 0.5 ? 0.6 : 0.45);
	float shown = max(clear, lit);
	ALBEDO = COLOR.rgb;
	ALPHA = mix(faint, 1.0, shown);
	ROUGHNESS = 0.85;
	// Pressed: the rim and face glow in their own colour; the letter stays ink.
	EMISSION = layer < 1.5 ? COLOR.rgb * 0.55 * lit : vec3(0.0);
}
