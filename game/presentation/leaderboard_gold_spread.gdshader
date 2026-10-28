shader_type spatial;
// A pip's leaf turning gold from its stalk to its tip, for the first place
// celebration (presentation/leaderboard_celebration.gd). The leaf colours are
// the leaf's own material; the gold ones are the Gold leaf cosmetic's
// (presentation/pip_wear/gold_leaf.gd material()), which replaces this once
// the spread is done. `progress` 0 is all leaf, 1 all gold; `glint` lifts the
// gold's glow for one soft glint.
uniform vec3 leaf_color : source_color;
uniform float leaf_roughness = 0.9;
uniform vec3 gold_color : source_color;
uniform float gold_roughness = 0.38;
uniform vec3 gold_glow : source_color;
uniform float gold_glow_energy = 0.22;
// The leaf mesh's height range, stalk to tip, in its own space.
uniform float base_y = 0.0;
uniform float tip_y = 0.15;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float glint : hint_range(0.0, 1.0) = 0.0;
const float EDGE = 0.12;
varying float along;

void vertex() {
	along = clamp((VERTEX.y - base_y) / max(tip_y - base_y, 0.0001), 0.0, 1.0);
}

void fragment() {
	float front = progress * (1.0 + 2.0 * EDGE) - EDGE;
	float gold = 1.0 - smoothstep(front - EDGE, front + EDGE, along);
	ALBEDO = mix(leaf_color, gold_color, gold);
	ROUGHNESS = mix(leaf_roughness, gold_roughness, gold);
	EMISSION = gold_glow * gold * (gold_glow_energy + glint);
}
