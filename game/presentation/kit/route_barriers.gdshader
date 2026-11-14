// World kit: the route barriers' look (presentation/kit/route_barriers.gd).
// One mesh holds every barrier piece of a stage; each vertex carries its slot
// (UV2.x: a crossing's end, a stretch of zone edge or a control's lock), its
// layer bit (UV2.y: posts, shut gate, open gate, chain, rope, padlock) and
// its height above its floor (UV.y), its colour in COLOR as the kit writes it
// (like pair_tags' tiles, it lights as the plain scenery does). states[slot] is
// (shown layers as a bit mask, wiggle strength, wiggle direction x, z). A
// layer its slot does not show folds to a point and draws nothing. Nothing
// here reads TIME: the kit sets `clock` only while something wiggles.
shader_type spatial;
// Small closed boxes: no culling, so a face's winding never matters.
render_mode cull_disabled;

// MAX_SLOTS in route_barriers.gd.
uniform vec4 states[96];
// Seconds on the kit's own clock (a rattle's wiggle), 0 at rest.
uniform float clock;
// How far (metres per metre of height) a full wiggle leans a piece, and how
// fast it shakes (radians a second).
uniform float wiggle_lean;
uniform float wiggle_rate;

void vertex() {
	int slot = clamp(int(UV2.x + 0.5), 0, 95);
	int layer = int(UV2.y + 0.5);
	vec4 state = states[slot];
	if ((int(state.x + 0.5) & layer) == 0) {
		VERTEX = vec3(0.0);
	} else if (state.y > 0.0) {
		VERTEX.xz += state.zw * (sin(clock * wiggle_rate) * state.y * wiggle_lean * UV.y);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
}
