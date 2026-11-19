shader_type sky;
// The space behind every world (kit/space_backdrop.gd): the look's sky colour,
// faint tiny stars, a few larger soft stars that twinkle, a shooting star now
// and then, far island shapes and a few edge lights in the look's accent. The
// sky only shades pixels nothing in the world covers, so none of it can ever
// show in front of a world. Everything moves with `clock`, the world's own
// time, never TIME: a still or a clip stepped by fixed frames shows the same.

uniform vec3 sky_color : source_color = vec3(0.07, 0.23, 0.24);
uniform vec3 star_color : source_color = vec3(0.76, 0.87, 0.74);
uniform vec3 far_color : source_color = vec3(0.12, 0.3, 0.3);
uniform vec3 accent_color : source_color = vec3(1.0, 0.91, 0.66);
// 0 none, 1 petals, 2 fireflies, 3 dust in the light.
uniform int accent_kind = 0;
uniform float clock = 0.0;
// Camera offset in screen heights; each layer shifts by its own share.
uniform vec2 parallax = vec2(0.0);
// The 3D picture's size in pixels; FRAGCOORD is read against it.
uniform vec2 buffer_size = vec2(1920.0, 1080.0);
// 0 on Low: half the faint stars, no far islands, no edge lights.
uniform float detail = 1.0;
// 0 under Reduce motion: no shooting star.
uniform float shooting = 1.0;

const float SHOOT_EVERY = 9.0;
const float SHOOT_LENGTH = 0.8;

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

// A far floating island: a flat cap over a rounded cone, `w` wide.
float far_island(vec2 p, vec2 c, float w) {
	vec2 l = (p - c) / w;
	float cap = length(l * vec2(1.0, 5.5)) - 1.0;
	float cone = max(abs(l.x) - (1.0 - l.y / 0.9) * 0.95, l.y - 0.85);
	float body = l.y < 0.0 ? cap : min(cap, cone);
	return 1.0 - smoothstep(-0.04, 0.04, body);
}

void sky() {
	// Screen heights from the centre, y down.
	float aspect = buffer_size.x / buffer_size.y;
	vec2 p = (FRAGCOORD.xy - 0.5 * buffer_size) / buffer_size.y;
	vec2 shift = vec2(parallax.x, -parallax.y);
	vec3 col = sky_color;

	// Far islands, low and to the sides, closest of the far layers.
	if (detail > 0.5) {
		vec2 q = p + shift * 0.22;
		float tile = 2.6;
		float shape = 0.0;
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float x = mod(q.x - (fi * 0.87 - 0.9) + tile * 0.5, tile) - tile * 0.5;
			vec2 at = vec2(0.0, (i == 1 ? -0.36 : 0.24) + 0.09 * hash11(fi + 3.0) + 0.006 * sin(clock * 0.21 + fi * 2.0));
			shape = max(shape, far_island(vec2(x, q.y), at, 0.07 + 0.05 * hash11(fi + 7.0)));
		}
		col = mix(col, far_color, shape * 0.55);
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
	col = mix(col, star_color, clamp(light, 0.0, 1.0));

	// A few lights round the edges of the view, in the look's accent.
	if (detail > 0.5 && accent_kind > 0) {
		float glow = 0.0;
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			float a = fi * 0.8976 + hash11(fi + 1.0) * 0.5;
			vec2 home = vec2(cos(a) * aspect * 0.44, sin(a) * 0.4);
			vec2 at;
			float size;
			float bright;
			if (accent_kind == 1) {
				// Petals drift sideways and sway.
				float x = mod(home.x + clock * 0.012 + aspect * 0.5, aspect) - aspect * 0.5;
				at = vec2(x, home.y + 0.02 * sin(clock * 0.6 + fi));
				size = 0.0055;
				bright = 0.55;
			} else if (accent_kind == 2) {
				// Fireflies wander and pulse.
				at = home + 0.025 * vec2(sin(clock * 0.5 + fi * 1.9), sin(clock * 0.65 + fi * 2.3));
				size = 0.0035;
				bright = 0.55 + 0.45 * sin(clock * 1.3 + fi * 2.1);
			} else {
				// Dust floats slowly up.
				float y = mod(home.y - clock * 0.006 + 0.5, 1.0) - 0.5;
				at = vec2(home.x + 0.01 * sin(clock * 0.3 + fi), y);
				size = 0.0025;
				bright = 0.4;
			}
			vec2 d = p + shift * 0.3 - at;
			if (accent_kind == 1) {
				float r = clock * 0.8 + fi;
				d = mat2(vec2(cos(r), sin(r)), vec2(-sin(r), cos(r))) * d * vec2(1.0, 1.9);
			}
			float dist = length(d);
			glow += bright * ((1.0 - smoothstep(size * 0.6, size, dist)) + (accent_kind == 2 ? exp(-dist * dist * 9000.0) * 0.35 : 0.0));
		}
		col = mix(col, accent_color, clamp(glow, 0.0, 1.0));
	}
	COLOR = col;
}
