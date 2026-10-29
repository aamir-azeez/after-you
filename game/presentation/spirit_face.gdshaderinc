// The spirit face shader's body, shared by spirit_face.gdshader and the body
// cosmetics' variants, which define SPIRIT_SKIN and vec3 skin_color(vec3 p,
// vec3 body) before including it.
uniform vec3 body_color : source_color = vec3(0.96, 0.76, 0.55);
uniform vec3 cream_color : source_color = vec3(0.98, 0.94, 0.85);
uniform vec3 pupil_color : source_color = vec3(0.06, 0.13, 0.2);
// Joy's cheeks: colour, how much of it covers the body, and the soft edge's
// width (spirit_look.gd BLUSH, BLUSH_STRENGTH, BLUSH_SOFT).
uniform vec3 blush_color : source_color = vec3(0.95, 0.56, 0.61);
uniform float blush_strength = 0.85;
uniform float blush_soft = 0.01;
// The eyes' anchors in face space (x0, y0, x1, y1) and their vertical
// squash (blink, swap) per eye. Plain values, written most frames.
uniform vec4 eye_xy;
uniform vec2 eye_squash = vec2(1.0);
// The least cream kept between pupil and outer eye (spirit_look.gd RIM).
uniform float pupil_rim = 0.007;
// Where the tear's dark neck starts, as a fraction of the way to its tip.
uniform float tear_neck_root = 0.6;
// Pupil offset inside the eye (gaze), metres.
uniform vec2 look_shift;
uniform vec4 outer[2];
uniform vec4 outer_wave[2];
uniform vec4 outer_phase[2];
uniform vec4 pupil[2];
uniform vec4 pupil_wave[2];
uniform vec4 pupil_phase[2];
uniform vec4 cut[2];
uniform vec4 tear[2];
uniform vec4 tear_pupil[2];
uniform vec4 stroke[2];
uniform vec4 stroke_end[2];
uniform vec4 blush[2];
// The pack faces (spirit_look.gd eye()): eye_shape.x the pupil's outline (0 oval, 1 heart,
// 2 star), eye_shape.y the cream's (0 oval, 1 heart); a cream tear stream
// from tear_stream (x, y, radius) to tear_stream_end (x, y, radius); the
// heart pupil's colour.
uniform vec4 eye_shape[2];
uniform vec4 tear_stream[2];
uniform vec4 tear_stream_end[2];
uniform vec3 heart_color : source_color = vec3(0.886, 0.384, 0.420);
// Where a heart's middle sits in its unit outline, and how round a star's corners are (spirit_look.gd HEART_MIDDLE, STAR_ROUND).
uniform float heart_middle = 0.55;
uniform float star_round = 0.008;

varying vec3 face_pos;

void vertex() {
	face_pos = VERTEX;
}

// A wavy oval's signed distance (approximate, metres).
float oval(vec2 q, vec4 shape, vec4 wave, vec4 phase) {
	vec2 p = (q - shape.zw) / shape.xy;
	// Nudged off the origin, where atan is undefined on some GPUs.
	float a = atan(p.y, p.x + 1e-6);
	float r = 1.0 + wave.x * cos(2.0 * a + phase.x) + wave.y * cos(3.0 * a + phase.y) + wave.z * cos(4.0 * a + phase.z) + wave.w * cos(5.0 * a + phase.w);
	return (length(p) - r) * min(shape.x, shape.y);
}

float smooth_union(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float segment(vec2 q, vec2 a, vec2 b) {
	vec2 pa = q - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
	return length(pa - ba * h);
}

// An arc bowed upward around its centre: radius r, `sweep` radians either side
// of straight up (after Inigo Quilez's sdArc), unsigned.
float arc(vec2 q, vec2 centre, float r, float sweep) {
	vec2 p = q - centre;
	p.x = abs(p.x);
	vec2 sc = vec2(sin(sweep), cos(sweep));
	return sc.y * p.x > sc.x * p.y ? length(p - sc * r) : abs(length(p) - r);
}

// Inigo Quilez's sdHeart, tip at the origin, top at 1.10, sized
// `size` with its middle at `centre`.
float heart(vec2 q, vec2 centre, float size) {
	vec2 p = (q - centre) / size + vec2(0.0, heart_middle);
	p.x = abs(p.x);
	float d;
	if (p.y + p.x > 1.0) d = length(p - vec2(0.25, 0.75)) - sqrt(2.0) / 4.0;
	else d = sqrt(min(dot(p - vec2(0.0, 1.0), p - vec2(0.0, 1.0)), dot(p - 0.5 * max(p.x + p.y, 0.0), p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
	return d * size;
}

// A five point star, point up (Inigo Quilez's sdStar5), radius r,
// inner radius rf of it, its corners rounded star_round.
float star5(vec2 q, vec2 centre, float r, float rf) {
	vec2 p = q - centre;
	r -= star_round;
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-0.809016994375, -0.587785252292);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y) - star_round;
}

// An Archimedean spiral from `centre` out to `reach` over |turns|
// turns (negative turns the other way), unsigned distance to its line.
float spiral(vec2 q, vec2 centre, float reach, float turns) {
	vec2 p = q - centre;
	p.x *= sign(turns + 1e-6);
	float count = abs(turns);
	float span = 6.28318530718 * count;
	float pitch = reach / span;
	float a = atan(p.y, p.x + 1e-6);
	if (a < 0.0) a += 6.28318530718;
	float r = length(p);
	float best = 1e3;
	for (int k = 0; k < 5; k++) {
		float t = a + 6.28318530718 * float(k);
		if (t <= span) best = min(best, abs(r - pitch * t));
	}
	best = min(best, length(p - vec2(cos(span), sin(span)) * reach));
	return min(best, r);
}

float coverage(float d) {
	float w = max(fwidth(d), 1e-5);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

void fragment() {
#ifdef SPIRIT_SKIN
	// A body cosmetic recolours the head (spirit_face_tide.gdshader).
	vec3 color = skin_color(face_pos, body_color);
#else
	vec3 color = body_color;
#endif
	// Front half only: the back of the head never shows an eye.
	float front = step(0.0, face_pos.z);
	for (int i = 0; i < 2; i++) {
		vec2 q = face_pos.xy - (i == 0 ? eye_xy.xy : eye_xy.zw);
		float squash = i == 0 ? eye_squash.x : eye_squash.y;
		if (blush[i].x > 0.0) {
			// A soft cheek under the eye, drawn first so the eye sits on top.
			// It stays put while the eyes close and open for a swap, and
			// fades with them instead.
			float d_blush = oval(q, blush[i], vec4(0.0), vec4(0.0));
			float soft = max(blush_soft, fwidth(d_blush));
			color = mix(color, blush_color, clamp(0.5 - d_blush / soft, 0.0, 1.0) * blush_strength * clamp(squash, 0.0, 1.0) * front);
		}
		if (tear_stream[i].z > 0.0) {
			// The cream tear stream, an uneven capsule, still while the
			// eyes close and open.
			vec2 a = tear_stream[i].xy;
			vec2 b = tear_stream_end[i].xy;
			vec2 pa = q - a;
			vec2 ba = b - a;
			float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
			float d_stream = length(pa - ba * h) - mix(tear_stream[i].z, tear_stream_end[i].z, h);
			color = mix(color, cream_color, coverage(d_stream) * clamp(squash, 0.0, 1.0) * front);
		}
		q.y /= max(squash, 0.02);
		if (stroke_end[i].w > 4.5) {
			// Kind 5: an arc bowed downward (kind 3 mirrored about its centre).
			vec2 m = vec2(q.x, 2.0 * stroke[i].y - q.y);
			float d = arc(m, stroke[i].xy, stroke[i].z, stroke[i].w) - stroke_end[i].z;
			color = mix(color, pupil_color, coverage(d) * front);
		} else if (stroke_end[i].w > 3.5) {
			// Kind 4: a spiral (centre, reach, turns).
			float d = spiral(q, stroke[i].xy, stroke[i].z, stroke[i].w) - stroke_end[i].z;
			color = mix(color, pupil_color, coverage(d) * front);
		} else if (stroke_end[i].w > 2.5) {
			// Kind 3: an arc bowed upward (centre, radius, half sweep).
			float d = arc(q, stroke[i].xy, stroke[i].z, stroke[i].w) - stroke_end[i].z;
			color = mix(color, pupil_color, coverage(d) * front);
		} else if (stroke_end[i].w > 0.5) {
			// Kind 1: a line a, b, c. Kind 2: a cross, a to b and c to its
			// mirror through the middle of a to b.
			vec2 from = stroke_end[i].w > 1.5 ? stroke[i].xy + stroke[i].zw - stroke_end[i].xy : stroke[i].zw;
			float d = min(segment(q, stroke[i].xy, stroke[i].zw), segment(q, from, stroke_end[i].xy)) - stroke_end[i].z;
			color = mix(color, pupil_color, coverage(d) * front);
		} else {
			float d_outer = eye_shape[i].y > 0.5 ? heart(q, outer[i].zw, outer[i].x) : oval(q, outer[i], outer_wave[i], outer_phase[i]);
			float d_pupil;
			if (eye_shape[i].x > 1.5) d_pupil = star5(q - look_shift, pupil[i].zw, pupil[i].x, pupil[i].y);
			else if (eye_shape[i].x > 0.5) d_pupil = heart(q - look_shift, pupil[i].zw, pupil[i].x);
			else d_pupil = oval(q - look_shift, pupil[i], pupil_wave[i], pupil_phase[i]);
			if (tear[i].z > 0.0) {
				d_outer = smooth_union(d_outer, length(q - tear[i].xy) - tear[i].z, 0.035);
				vec2 tip = tear_pupil[i].xy;
				float lobe = min(length(q - tip) - tear_pupil[i].z, segment(q, tip * tear_neck_root, tip) - tear_pupil[i].w);
				d_pupil = smooth_union(d_pupil, lobe, 0.014);
			}
			d_pupil = max(d_pupil, d_outer + pupil_rim);
			float d_cut = dot(q, cut[i].xy) - cut[i].z;
			d_outer = max(d_outer, d_cut);
			d_pupil = max(d_pupil, d_cut + cut[i].w);
			color = mix(color, cream_color, coverage(d_outer) * front);
			color = mix(color, eye_shape[i].x > 0.5 && eye_shape[i].x < 1.5 ? heart_color : pupil_color, coverage(d_pupil) * front);
		}
	}
	ALBEDO = color;
	ROUGHNESS = 0.9;
}
