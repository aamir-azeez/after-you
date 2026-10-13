// Shared by the ball and its band: how much of a spin exposure the band covers
// at direction `d` from the ball centre. The band is every direction within
// `half_width` of the plane with unit normal `n`; the ball turns about unit
// axis `a` through `angle` radians during the exposure. Newer samples weigh
// more (a soft shutter), and edges soften as the exposure grows.
float spin_coverage(vec3 d, vec3 n, vec3 a, float angle, float half_width, int taps, float tail_weight) {
	vec3 p = normalize(d);
	// Turning p about a by t moves its offset from the band plane to
	// still + cos(t) * swing + sin(t) * lift (Rodrigues' formula).
	float still = dot(a, n) * dot(a, p);
	float swing = dot(p, n) - still;
	float lift = dot(cross(a, p), n);
	float soft = 0.015 + 0.06 * angle;
	float last = float(max(taps - 1, 1));
	float step_c = cos(angle / last);
	float step_s = sin(angle / last);
	float c = 1.0;
	float s = 0.0;
	float covered = 0.0;
	float total = 0.0;
	for (int i = 0; i < taps; i++) {
		float age = float(i) / last;
		float weight = mix(1.0, tail_weight, age * age);
		float x = still + c * swing + s * lift;
		covered += weight * (1.0 - smoothstep(half_width - soft, half_width + soft, abs(x)));
		total += weight;
		// Advance the angle without another cos/sin per sample.
		float next_c = c * step_c - s * step_s;
		s = s * step_c + c * step_s;
		c = next_c;
	}
	return covered / total;
}
