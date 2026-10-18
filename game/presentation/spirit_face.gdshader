shader_type spatial;
// A spirit's head: its body colour with the two eyes painted on as flat
// surface art (presentation/spirit_look.gd describes every uniform below).
// The eyes are drawn from the head's own position, projected straight onto
// the face, so they follow the head, are hidden by whatever hides the head and
// never show from behind. No time input: everything moves through uniforms
// written from the spirit's own clock.

uniform vec3 body_color : source_color = vec3(0.96, 0.76, 0.55);
uniform vec3 cream_color : source_color = vec3(0.98, 0.94, 0.85);
uniform vec3 pupil_color : source_color = vec3(0.06, 0.13, 0.2);
// Per eye: the anchor x, y in face space, its vertical squash (blink), unused.
uniform vec4 eye_at[2];
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

const float PUPIL_RIM = 0.007;

varying vec3 face_pos;

void vertex() {
	face_pos = VERTEX;
}

// A wavy oval's signed distance (approximate, metres).
float oval(vec2 q, vec4 shape, vec4 wave, vec4 phase) {
	vec2 p = (q - shape.zw) / shape.xy;
	float a = atan(p.y, p.x);
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

float coverage(float d) {
	float w = max(fwidth(d), 1e-5);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

void fragment() {
	vec3 color = body_color;
	// Front half only: the back of the head never shows an eye.
	float front = step(0.0, face_pos.z);
	for (int i = 0; i < 2; i++) {
		vec2 q = face_pos.xy - eye_at[i].xy;
		q.y /= max(eye_at[i].z, 0.02);
		if (stroke_end[i].w > 0.5) {
			float d = min(segment(q, stroke[i].xy, stroke[i].zw), segment(q, stroke[i].zw, stroke_end[i].xy)) - stroke_end[i].z;
			color = mix(color, pupil_color, coverage(d) * front);
		} else {
			float d_outer = oval(q, outer[i], outer_wave[i], outer_phase[i]);
			float d_pupil = oval(q - look_shift, pupil[i], pupil_wave[i], pupil_phase[i]);
			if (tear[i].z > 0.0) {
				d_outer = smooth_union(d_outer, length(q - tear[i].xy) - tear[i].z, 0.035);
				vec2 tip = tear_pupil[i].xy;
				float lobe = min(length(q - tip) - tear_pupil[i].z, segment(q, tip * 0.6, tip) - tear_pupil[i].w);
				d_pupil = smooth_union(d_pupil, lobe, 0.014);
			}
			d_pupil = max(d_pupil, d_outer + PUPIL_RIM);
			float d_cut = dot(q, cut[i].xy) - cut[i].z;
			d_outer = max(d_outer, d_cut);
			d_pupil = max(d_pupil, d_cut + cut[i].w);
			color = mix(color, cream_color, coverage(d_outer) * front);
			color = mix(color, pupil_color, coverage(d_pupil) * front);
		}
	}
	ALBEDO = color;
	ROUGHNESS = 0.9;
}
