shader_type spatial;
// The Orchard skin's falling petals (pip_wear/orchard_skin.gd): every petal of
// the one mesh fades in above the head, flutters down round the pip with its
// own sway and tumble and fades out by the feet, falling a whole number of
// times per loop, so the fall loops perfectly. The motion is all here, driven
// by the pip's own clock (fall_clock, set at the idle card rate), never the
// engine's running time, so a calm screen still draws only on change. Each
// vertex is a petal's own point (UV.x is the petal's index); the petals' looks
// and the path's numbers come from orchard_skin.gd, which also holds the same
// path in GDScript (fall_petal) for its tests: change both together.
render_mode blend_mix, cull_disabled, depth_draw_opaque;

// Ten petals, each with [falls per loop, share of its cycle spent falling,
// phase, start (radians from straight toward the camera)], [drift round the
// body, sway (radians), sways per fall, sway phase], [turns per fall, rock,
// tip, size] and its start height.
uniform vec4 paths[10];
uniform vec4 sways[10];
uniform vec4 turns[10];
uniform float tops[10];
uniform float loop = 8.0;
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
// The head (at rest or sunk) and the torso, grown by the petal's clearance
// (upper body space).
uniform vec3 head_center;
uniform vec3 head_half;
uniform float head_power = 3.0;
uniform vec3 torso_center;
uniform vec3 torso_half;
uniform float torso_power = 2.4;
// The pip's clock (seconds), its own start, and its strength (the race ghost
// draws it see-through).
instance uniform float fall_clock = 0.0;
instance uniform float fall_offset = 0.0;
instance uniform float veil = 1.0;

varying float fade;

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
	vec4 path = paths[index];
	vec4 swaying = sways[index];
	vec4 turning = turns[index];
	float u = fract((fall_clock + fall_offset) * path.x / loop + path.z) / path.y;
	bool waiting = u >= 1.0;
	u = min(u, 1.0);
	float w = u + ease * sin(TAU * u) / TAU;
	float sway = TAU * swaying.z * u + swaying.w;
	float y = mix(tops[index], bottom, w) + bob * sin(2.0 * sway);
	float open = 1.0 - smoothstep(open_to, open_from, y);
	vec3 camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec2 toward = length(camera.xz) > 0.0001 ? camera.xz : vec2(0.0, 1.0);
	float angle = atan(toward.x, toward.y) + path.w + swaying.x * open + swaying.y * sin(sway);
	vec2 d = vec2(sin(angle), cos(angle));
	float out_to = max(least_reach, max(reach(y, d, head_center, head_half, head_power), reach(y, d, torso_center, torso_half, torso_power)));
	fade = waiting ? 0.0 : smoothstep(0.0, fade_in, u) * smoothstep(bottom, fade_out, y);
	float size = waiting ? 0.0 : turning.w * mix(shrink, 1.0, fade);
	mat3 pose = turn_y(angle + turning.x * TAU * u) * turn_x(lean + turning.y * cos(sway)) * turn_z(turning.z * sin(sway + 1.0));
	VERTEX = vec3(d.x * out_to, y, d.y * out_to) + pose * (VERTEX * size);
	NORMAL = pose * NORMAL;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	EMISSION = COLOR.rgb * glow;
	ALPHA = fade * veil;
}
