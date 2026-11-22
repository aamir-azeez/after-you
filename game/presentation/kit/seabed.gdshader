shader_type spatial;
render_mode cull_back;
// The floor under the water (presentation/kit/water_look.gd bed_material,
// styles in content/water/looks.gd SEABEDS). No texture: everything comes
// from where the spot lies in the terrain's plan, so it never repeats and two
// beds side by side carry on from each other.
// - Wide soft patches (a couple of metres) of bare sand or silt and of stones.
// - The ground softly mottled between its two colours, with fine grit.
// - Pebbles of mixed sizes, shapes, turns and colours, one at most per cell of
//   two grids at different scales and angles, thinning out and shrinking
//   toward the bare patches; each a little lighter on top with a soft dark rim
//   round it.
// Low draws the bigger pebbles only, with one patch layer and no grit.

uniform vec3 ground : source_color = vec3(0.66, 0.64, 0.57);
uniform vec3 light : source_color = vec3(0.77, 0.75, 0.67);
uniform vec4 stones[5] : source_color;
uniform int stone_count = 1;
// The share of cells that hold a pebble where the ground is stony.
uniform float density = 0.5;
// How much the wide patches swing that share (0 even, 1 bare to full).
uniform float patchiness = 0.6;
// Soft sand ripples (0 none).
uniform float ripples = 0.0;
// 1 on Balanced and High (GraphicsPolicy.water_detail).
uniform float detail = 1.0;

varying vec2 plan;

void vertex() {
	// The sheet only moves up and down, so its own x and z are the terrain's.
	plan = VERTEX.xz;
}

// A cheap hash with no sine (steady on phone GPUs).
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// One grid of pebbles: x the pebble's share of the spot, y its shade, z which
// colour, w the dark rim round it. `chance` is the share of cells with one,
// `px` a pixel's width in cells (read before any branch).
vec4 pebbles(vec2 q, float px, float chance, float seed) {
	vec2 cell = floor(q);
	float h = hash(cell + seed);
	// Near the patch's edge a pebble shrinks away rather than being cut off.
	float grow = smoothstep(0.0, 0.18, chance - h);
	if (grow <= 0.0) return vec4(0.0);
	vec2 k = vec2(hash(cell + seed + 1.7), hash(cell + seed + 4.3));
	// Kept inside its cell, rim and all: 0.12 + 0.30 * 1.25 < 0.5.
	vec2 f = fract(q) - 0.5 - (k - 0.5) * 0.24;
	float r = mix(0.17, 0.30, k.x * k.y + 0.25 * h) * mix(0.55, 1.0, grow);
	vec2 axis = normalize(k - 0.5 + 0.001);
	vec2 turned = vec2(dot(f, axis), dot(f, vec2(-axis.y, axis.x)));
	float d = length(turned * vec2(1.0, mix(1.0, 1.6, k.y))) / r;
	float aa = max(px * 0.7 / r, 0.02);
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, d);
	float rim = (1.0 - smoothstep(1.0, 1.25, d)) * (1.0 - inside);
	// Lighter on top, a little darker toward the far side from the sun.
	float shade = mix(1.14, 0.84, d * d) - 0.08 * f.y / r;
	return vec4(inside, shade, fract(h * 7.31 + k.x), rim);
}

vec3 stone_color(float pick) {
	int index = clamp(int(pick * float(stone_count)), 0, stone_count - 1);
	return stones[index].rgb;
}

void fragment() {
	vec2 p = plan;
	vec2 fw = fwidth(p);
	// Wide patches, 1 stony and 0 bare: three warped waves at odd angles and
	// lengths, so they never line up into a repeat across a level.
	float wide = 0.5 + 0.2 * (sin(p.x * 0.47 + sin(p.y * 0.31) * 1.9) + sin(p.y * 0.53 + sin(p.x * 0.37 + 1.1) * 1.7) + 0.6 * sin((p.x - p.y * 0.6) * 0.83 + 2.1));
	float stony = smoothstep(0.32, 0.68, wide);
	float chance = density * mix(1.0, stony * 1.6, patchiness);
	// The ground: softly mottled (no hash), the bare patches a shade lighter.
	float mottle = 0.5 + 0.25 * sin(p.x * 2.3 + sin(p.y * 1.9) * 1.6) + 0.25 * sin(p.y * 2.9 - p.x * 1.1 + wide * 4.0);
	vec3 col = mix(ground, light, clamp(mottle * 0.5 + (1.0 - stony) * 0.35 * patchiness, 0.0, 1.0));
	if (ripples > 0.0) {
		float wave = sin(dot(p, vec2(9.0, 11.0)) + wide * 9.0);
		col *= 1.0 + ripples * 0.06 * wave * (1.0 - stony);
	}
	// Bigger stones on a 25 cm grid turned one way.
	vec2 qa = mat2(vec2(0.96, 0.28), vec2(-0.28, 0.96)) * p * 4.0;
	vec4 a = pebbles(qa, (fw.x + fw.y) * 4.0, chance, 0.0);
	vec3 stone = stone_color(a.z) * a.y;
	float on = a.x;
	float rim = a.w;
	// Grit and small pebbles on a 10 cm grid turned another, where no big
	// one covers the ground.
	if (detail > 0.5 && on < 0.99) {
		col *= 0.95 + 0.08 * hash(floor(p * 45.0));
		vec2 qb = mat2(vec2(0.82, -0.57), vec2(0.57, 0.82)) * p * 10.0;
		vec4 b = pebbles(qb, (fw.x + fw.y) * 10.0, chance * 0.8, 17.0);
		stone = mix(stone_color(b.z) * b.y, stone, on);
		rim = max(rim, b.w * (1.0 - on));
		on = max(on, b.x);
	}
	col *= 1.0 - 0.28 * rim;
	ALBEDO = mix(col, stone, on);
	ROUGHNESS = mix(0.95, 0.75, on);
}
