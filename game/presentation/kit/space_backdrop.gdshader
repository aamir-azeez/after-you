shader_type sky;
// The space behind every world (kit/space_backdrop.gd): the look's sky colour,
// faint tiny stars, a few larger soft stars that twinkle, a shooting star now
// and then, far floating islands drifting slowly (tiles of a small baked atlas),
// soft cloud wisps far below and a few edge lights in the look's accent. The sky
// only shades pixels nothing in the world covers, so none of it can ever show in
// front of a world.
// Everything moves with `clock`, the world's own time, never TIME: a still or
// a clip stepped by fixed frames shows the same. Each layer shifts with the
// camera by its own share of `parallax`, the far islands and wisps laid out by
// `layout_seed`, so every place has its own sky.

uniform vec3 sky_color : source_color = vec3(0.07, 0.23, 0.24);
uniform vec3 star_color : source_color = vec3(0.76, 0.87, 0.74);
uniform vec3 far_color : source_color = vec3(0.12, 0.3, 0.3);
uniform vec3 accent_color : source_color = vec3(1.0, 0.91, 0.66);
// 0 none, 1 petals, 2 fireflies, 3 dust in the light.
uniform int accent_kind = 0;
// Each edge light this frame: where (screen heights), a petal's turn, brightness.
uniform vec4 accents[7];
uniform float clock = 0.0;
// Camera pan in PAN_SPAN units (kit/space_backdrop.gd); each layer shifts by
// its own share of it, all less than the world's.
uniform vec2 parallax = vec2(0.0);
// The place's layout, 0 to 1 (SpaceBackdrop.layout_seed).
uniform float layout_seed = 0.0;
// The 3D picture's size in pixels; FRAGCOORD is read against it.
uniform vec2 buffer_size = vec2(1920.0, 1080.0);
// 0 on Low: half the faint stars, no far islands, wisps or edge lights.
uniform float detail = 1.0;
// 0 under Reduce motion: no shooting star.
uniform float shooting = 1.0;
// The far islands (assets/sky/far_islands.png, baked from six island models by
// the private Blender kit): one tile each, R the top's coverage, G the rock
// underneath, B the light on them times coverage. Every tile has its grass top
// on the same row and its middle in the middle.
uniform sampler2D islands : filter_linear_mipmap, repeat_disable;

const float SHOOT_EVERY = 9.0;
const float SHOOT_LENGTH = 0.8;
// The far islands and wisps repeat every this many screen heights across.
const float FAR_TILE = 3.0;
const int FAR_SLOTS = 4;
const vec2 ISLAND_GRID = vec2(3.0, 2.0);
const float ISLAND_KINDS = 6.0;
// The tile's pixels across, and the share of it above the grass top.
const float ISLAND_TILE = 128.0;
const float ISLAND_TOP = 0.353;
const int WISPS = 3;
const int ACCENT_LIGHTS = 7;

vec3 hash32(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.xxy + q.yxx) * q.zyx);
}

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// One star per cell at most; `on` is the share of cells that hold one.
vec4 star_cell(vec2 q, float on) {
	vec2 cell = floor(q);
	vec3 h = hash32(cell);
	if (h.z > on) return vec4(0.0, 0.0, 9.0, 0.0);
	vec2 at = 0.25 + 0.5 * h.xy;
	return vec4(h.xy, length(fract(q) - at), 1.0);
}

// The atlas around one far island: `d` from its grass top's middle, `w` half its
// tile's width, `kind` which tile, `flip` -1 for mirrored. Zero outside the tile.
vec3 far_island(vec2 d, float w, float kind, float flip) {
	vec2 t = vec2(0.5 + 0.5 * flip * d.x / w, ISLAND_TOP + 0.5 * d.y / w);
	if (t.x < 0.0 || t.x > 1.0 || t.y < 0.0 || t.y > 1.0) return vec3(0.0);
	vec2 cell = vec2(mod(kind, ISLAND_GRID.x), floor(kind / ISLAND_GRID.x));
	// Its own mip level from its size on screen; the sample sits in a branch, so
	// the level is worked out here rather than from screen derivatives.
	float lod = max(log2(ISLAND_TILE / (2.0 * w * buffer_size.y)), 0.0);
	return textureLod(islands, (cell + t) / ISLAND_GRID, lod).rgb;
}

void sky() {
	// The radiance map is never read (reflections are off): draw it flat.
	if (AT_CUBEMAP_PASS) {
		COLOR = sky_color;
	} else {
		// Screen heights from the centre, y down.
		float aspect = buffer_size.x / buffer_size.y;
		vec2 p = (FRAGCOORD.xy - 0.5 * buffer_size) / buffer_size.y;
		vec2 shift = vec2(parallax.x, -parallax.y);
		vec3 col = sky_color;
		float seed = layout_seed * 97.0;
		// How much of a far island covers this pixel; the stars stay behind it.
		float veil = 0.0;

		if (detail > 0.5) {
			// Soft cloud wisps far below, long and thin, drifting with the islands.
			vec2 w = p + shift * 0.4;
			if (w.y > 0.16) {
				float wisp = 0.0;
				for (int i = 0; i < WISPS; i++) {
					vec3 h = hash32(vec2(float(i) + 41.0, seed));
					float x = mod(w.x - (float(i) + 0.2 + 0.6 * h.x) * FAR_TILE / float(WISPS) - clock * (0.004 + 0.004 * h.z) + FAR_TILE * 0.5, FAR_TILE) - FAR_TILE * 0.5;
					float y = w.y - (0.27 + 0.16 * h.y) - 0.012 * sin(x * 7.0 + h.z * 6.2832);
					vec2 d = vec2(x / (0.32 + 0.3 * h.z), y / (0.016 + 0.014 * h.x));
					wisp += exp(-dot(d, d));
				}
				col = mix(col, mix(far_color, star_color, 0.3), clamp(wisp, 0.0, 1.0) * 0.2);
			}

			// Far islands, two to four of them high or low, each drifting slowly at
			// its own pace, the nearest of the far layers. Each is a different one of
			// the six shapes, maybe mirrored; the later slots are nearer, so larger
			// and less hazy, and paint over the earlier ones.
			vec2 q = p + shift * 0.3;
			float drift = hash11(seed + 5.0) > 0.5 ? 1.0 : -1.0;
			float first = floor(hash11(seed + 3.0) * ISLAND_KINDS);
			for (int i = 0; i < FAR_SLOTS; i++) {
				float fi = float(i);
				vec3 h = hash32(vec2(fi + 1.0, seed));
				if (i >= 2 && h.z < 0.35) continue;
				float x = mod(q.x - (fi + 0.15 + 0.7 * h.x) * FAR_TILE / float(FAR_SLOTS) - drift * clock * (0.003 + 0.004 * h.z) + FAR_TILE * 0.5, FAR_TILE) - FAR_TILE * 0.5;
				float y = (h.y < 0.4 ? -0.42 + 0.14 * h.y / 0.4 : 0.16 + 0.16 * (h.y - 0.4) / 0.6) + 0.006 * sin(clock * 0.21 + fi * 2.0);
				float near = (fi + 0.5 * h.z) / (float(FAR_SLOTS) - 0.5);
				float w = mix(0.055, 0.14, near) * (0.85 + 0.3 * fract(h.x * 7.0 + h.z));
				float flip = hash11(seed + fi * 13.0 + 7.0) > 0.5 ? -1.0 : 1.0;
				vec3 tile = far_island(vec2(x, q.y - y), w, mod(first + fi * 5.0, ISLAND_KINDS), flip);
				float cover = tile.r + tile.g;
				if (cover < 0.004) continue;
				// Two tones from the look: a grassy top toward its stars (or now and
				// then its accent) and the rock in the far colour, lit from the upper
				// left, then hazed toward the sky the farther it is.
				vec3 tint = mix(star_color, accent_color, step(0.6, fract(h.y * 13.0)) * 0.4);
				float lit = tile.b / cover;
				vec3 top = mix(far_color, tint, 0.36) * (0.9 + 0.2 * lit);
				vec3 rock = far_color * (0.78 + 0.3 * lit);
				vec3 island = mix(mix(rock, top, tile.r / cover), sky_color, mix(0.55, 0.15, near));
				col = mix(col, island, min(cover, 1.0) * 0.9);
				veil = max(veil, min(cover, 1.0));
			}
		}

		// Faint tiny stars, barely moving with the camera.
		vec4 tiny = star_cell((p + shift * 0.06) * 30.0, mix(0.22, 0.45, detail));
		float light = tiny.w * (1.0 - smoothstep(0.02, 0.07, tiny.z)) * (0.18 + 0.3 * tiny.x);

		// A few larger soft stars that twinkle slowly.
		vec4 big = star_cell((p + shift * 0.1) * 6.5, 0.34);
		float twinkle = 0.62 + 0.38 * sin(clock * (0.5 + 0.7 * big.y) + big.x * 6.2832);
		light += big.w * ((1.0 - smoothstep(0.015, 0.045, big.z)) * 0.85 + exp(-big.z * big.z * 160.0) * 0.32) * twinkle;

		// A shooting star now and then, picked by which slot of time it is.
		if (shooting > 0.5) {
			float slot = floor(clock / SHOOT_EVERY);
			float t = clock - slot * SHOOT_EVERY;
			float pick = hash11(slot);
			if (t < SHOOT_LENGTH && pick > 0.3) {
				float side = hash11(slot + 11.0) > 0.5 ? 1.0 : -1.0;
				vec2 from = vec2(side * -(0.15 + 0.5 * hash11(slot + 5.0)) * aspect * 0.5, -0.42 + 0.18 * hash11(slot + 9.0));
				vec2 dir = normalize(vec2(side, 0.42));
				float u = t / SHOOT_LENGTH;
				vec2 head = from + dir * 0.55 * u;
				vec2 rel = p + shift * 0.1 - head;
				float along = dot(rel, -dir);
				float across = abs(dot(rel, vec2(-dir.y, dir.x)));
				float tail = 0.16;
				float streak = step(0.0, along) * (1.0 - smoothstep(0.0, tail, along)) * (1.0 - smoothstep(0.0012, 0.004, across));
				light += streak * sin(3.14159 * u) * 1.1;
			}
		}
		col = mix(col, star_color, clamp(light, 0.0, 1.0) * (1.0 - veil));

		// A few lights round the edges of the view, in the look's accent, each
		// placed once a frame (SpaceBackdrop.advance) and drawn only near it.
		if (detail > 0.5 && accent_kind > 0) {
			float size = accent_kind == 1 ? 0.0055 : (accent_kind == 2 ? 0.0035 : 0.0025);
			float reach = accent_kind == 2 ? 0.03 : size * 1.5;
			vec2 near = p + shift * 0.3;
			float glow = 0.0;
			for (int i = 0; i < ACCENT_LIGHTS; i++) {
				vec2 d = near - accents[i].xy;
				if (abs(d.x) > reach || abs(d.y) > reach) continue;
				if (accent_kind == 1) {
					// A petal turns as it drifts.
					float r = accents[i].z;
					d = mat2(vec2(cos(r), sin(r)), vec2(-sin(r), cos(r))) * d * vec2(1.0, 1.9);
				}
				float dist = length(d);
				glow += accents[i].w * ((1.0 - smoothstep(size * 0.6, size, dist)) + (accent_kind == 2 ? exp(-dist * dist * 9000.0) * 0.35 : 0.0));
			}
			col = mix(col, accent_color, clamp(glow, 0.0, 1.0));
		}
		COLOR = col;
	}
}
