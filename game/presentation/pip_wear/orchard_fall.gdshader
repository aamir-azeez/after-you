shader_type spatial;
// The Orchard skin's falling petals (pip_wear/orchard_skin.gd): every petal of
// the one mesh fades in above the head, flutters down round the pip and fades
// out by the feet, waits a moment and falls again. Each fall draws its own
// look from an integer hash of the petal, the fall's number and the pip's
// seed; the fall's number wraps every `loop` seconds, so the whole fall loops
// perfectly. The motion is all here, driven by the pip's own clock
// (fall_clock, set at the idle card rate), never the engine's running time,
// so a calm screen still draws only on change. Each vertex is a petal's own
// point (UV.x is the petal's index). The numbers come from orchard_skin.gd,
// which also holds the same path and hash in GDScript (fall_petal) for its
// tests: change both together.
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform float loop = 30.0;
// Turns per loop for even and odd petals, how many petals, a fall's seconds.
uniform vec2 slots = vec2(5.0, 6.0);
uniform float petals = 10.0;
uniform vec2 fall_time = vec2(3.4, 4.6);
// Share of falls starting in front of the head, a start's turn from straight
// toward or away from the camera, the drift round the body; then the ranges
// a fall draws its sway, sways, spin, rock, tip, size and start height from.
uniform float front = 0.6;
uniform float sector = 0.35;
uniform float drift = 2.2;
uniform vec2 sway_size = vec2(0.15, 0.22);
uniform vec2 sways = vec2(1.0, 2.0);
uniform float spin = 0.6;
uniform vec2 rock = vec2(0.3, 0.6);
uniform vec2 tip = vec2(0.2, 0.5);
uniform vec2 scale = vec2(0.8, 1.0);
uniform vec2 top = vec2(0.92, 0.97);
uniform float bottom = 0.1;
uniform float fade_in = 0.12;
uniform float fade_out = 0.22;
uniform float ease = -0.7;
uniform float least_reach = 0.3;
uniform float open_from = 0.28;
uniform float open_to = 0.15;
uniform float bob = 0.01;
uniform float lean = 1.1;
uniform float shrink = 0.3;
// How much of its own colour it shows unlit, so a small petal stays bright.
uniform float glow = 0.4;
// The two pinks a fall picks between (raw, like the resting petals' vertex colours).
uniform vec3 pink;
uniform vec3 pink_deep;
// The head (at rest or sunk) and the torso, grown by the petal's clearance
// (upper body space).
uniform vec3 head_center;
uniform vec3 head_half;
uniform float head_power = 3.0;
uniform vec3 torso_center;
uniform vec3 torso_half;
uniform float torso_power = 2.4;
// The pip's clock (seconds), its seed (a whole number below 65536), and its
// strength (the race ghost draws it see-through).
instance uniform float fall_clock = 0.0;
instance uniform float fall_seed = 0.0;
instance uniform float veil = 1.0;

varying float fade;
varying vec3 tint;

// lowbias32: orchard_skin.gd _mix.
uint mix_word(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float draw(uint key, int at) {
	return float(mix_word(key + uint(at)) >> 8u) / 16777216.0;
}

// How far out from the upright axis the rounded box `extent` reaches at height
// y in direction d (x, z), 0 above or below it.
float reach(float y, vec2 d, vec3 center, vec3 extent, float power) {
	float k = 1.0 - pow(abs((y - center.y) / extent.y), power);
	if (k <= 0.0) return 0.0;
	return pow(k, 1.0 / power) / pow(pow(abs(d.x / extent.x), power) + pow(abs(d.y / extent.z), power), 1.0 / power);
}

mat3 turn_y(float a) { return mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a))); }
mat3 turn_x(float a) { return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(a), sin(a)), vec3(0.0, -sin(a), cos(a))); }
mat3 turn_z(float a) { return mat3(vec3(cos(a), sin(a), 0.0), vec3(-sin(a), cos(a), 0.0), vec3(0.0, 0.0, 1.0)); }

void vertex() {
	int index = int(UV.x + 0.5);
	float turns = index % 2 == 0 ? slots.x : slots.y;
	float turn_time = loop / turns;
	float at = mod(fall_clock + turn_time * float(index) / petals, loop);
	int fall = min(int(floor(at / turn_time)), int(turns) - 1);
	uint key = mix_word((uint(index) * 2654435769u + uint(fall) * 2246822507u) ^ uint(fall_seed));
	float time = mix(fall_time.x, min(fall_time.y, turn_time), draw(key, 1));
	float u = (at - float(fall) * turn_time - draw(key, 0) * (turn_time - time)) / time;
	bool waiting = u < 0.0 || u >= 1.0;
	u = clamp(u, 0.0, 1.0);
	float w = u + ease * sin(TAU * u) / TAU;
	float sway = TAU * mix(sways.x, sways.y, draw(key, 6)) * u + TAU * draw(key, 7);
	float y = mix(mix(top.x, top.y, draw(key, 12)), bottom, w) + bob * sin(2.0 * sway);
	float open = 1.0 - smoothstep(open_to, open_from, y);
	vec3 camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec2 toward = length(camera.xz) > 0.0001 ? camera.xz : vec2(0.0, 1.0);
	float start = (draw(key, 2) < front ? 0.0 : PI) + mix(-sector, sector, draw(key, 3));
	float angle = atan(toward.x, toward.y) + start + mix(-drift, drift, draw(key, 4)) * open + mix(sway_size.x, sway_size.y, draw(key, 5)) * sin(sway);
	vec2 d = vec2(sin(angle), cos(angle));
	float out_to = max(least_reach, max(reach(y, d, head_center, head_half, head_power), reach(y, d, torso_center, torso_half, torso_power)));
	fade = waiting ? 0.0 : smoothstep(0.0, fade_in, u) * smoothstep(bottom, fade_out, y);
	float size = waiting ? 0.0 : mix(scale.x, scale.y, draw(key, 11)) * mix(shrink, 1.0, fade);
	float turning = mix(-spin, spin, draw(key, 8));
	mat3 pose = turn_y(angle + turning * TAU * u) * turn_x(lean + mix(rock.x, rock.y, draw(key, 9)) * cos(sway)) * turn_z(mix(tip.x, tip.y, draw(key, 10)) * sin(sway + 1.0));
	tint = mix(pink, pink_deep, draw(key, 13));
	VERTEX = vec3(d.x * out_to, y, d.y * out_to) + pose * (VERTEX * size);
	NORMAL = pose * NORMAL;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.9;
	EMISSION = tint * glow;
	ALPHA = fade * veil;
}
