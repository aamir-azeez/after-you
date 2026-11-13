// A patterned body skin's flat surface marks (presentation/kit/skin_pattern.gd
// writes every uniform from a skin's recipe): colour fields, bands and stamps
// painted on the pip's own mesh, no added geometry. Shared by the head
// (spirit_face_pattern.gdshader, under the eyes) and the torso
// (spirit_body_pattern.gdshader). Coordinates follow the board's notes: the
// surface seen straight on, u 0 at its left edge to 1 at its right, v 0 at its
// top to 1 at its bottom; the back shows the front's fields and bands, so they
// run round the sides with no seam. Stamps are placed in metres. No time
// input: the drift is written from the pip's own clock.

// The surface: its half width (x), the height of v 0 (y) and its height (z), metres.
uniform vec3 surface_map = vec3(0.345, 0.28, 0.56);
// Colours are the palette's values as they are (kit/skin_pattern.gd).
uniform vec3 pattern_base = vec3(0.8);
// Colour fields, each a polygon in uv: its first point, its point count (0:
// none) and how far its edges wander (uv), so they curve softly.
uniform vec2 field_points[16];
uniform vec4 field_info[4];
uniform vec3 field_color[4];
// Bands round the surface: v from, v to, period (u) and amplitude (v) of
// their edges; kind (0 none, 1 zigzag, 2 wave) and the height (v) of an
// accent strip along the top edge.
uniform vec4 band_rows[3];
uniform vec4 band_style[3];
uniform vec3 band_color[3];
uniform vec3 band_edge_color[3];
// Stamps: centre x, y and half width (metres) and turn (radians); shape (0
// none, 1 a five point star, 2 a five lobed leaf) and side (1 the front, -1
// the back).
uniform vec4 stamp_at[5];
uniform vec4 stamp_style[5];
uniform vec3 stamp_color[5];
// A thin seam line down the back: half width (metres, 0 none).
uniform float seam_half = 0.0;
uniform vec3 seam_color = vec3(0.5);
// The eyes' safety ovals (metres): centre x (either side), y, radii x, y.
// Stamps never draw inside them. 0: no eyes on this surface.
uniform vec4 safe_eyes = vec4(0.0);
// The slow drift (u), triangle shaped, 0 at rest and under Reduce motion.
uniform float skin_drift = 0.0;

float pattern_cover(float d) {
	float w = max(fwidth(d), 1e-5);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

// Signed distance to polygon `count` points from `first` (Inigo Quilez's sdPolygon).
float pattern_polygon(vec2 p, int first, int count) {
	float d = dot(p - field_points[first], p - field_points[first]);
	float s = 1.0;
	for (int k = 0; k < 8; k++) {
		if (k >= count) break;
		int i = first + k;
		int j = first + (k == 0 ? count - 1 : k - 1);
		vec2 e = field_points[j] - field_points[i];
		vec2 w = p - field_points[i];
		vec2 b = w - e * clamp(dot(w, e) / max(dot(e, e), 1e-8), 0.0, 1.0);
		d = min(d, dot(b, b));
		bool c1 = p.y >= field_points[i].y;
		bool c2 = p.y < field_points[j].y;
		bool c3 = e.x * w.y > e.y * w.x;
		if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
	}
	return s * sqrt(d);
}

// A chubby five point star, point up, radius r (Inigo Quilez's sdStar5, rounded).
float pattern_star(vec2 p, float r) {
	float round_by = r * 0.16;
	r -= round_by;
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-0.809016994375, -0.587785252292);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = 0.52 * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y) - round_by;
}

// A broad five lobed leaf, a lobe up and its short stem down, radius r.
float pattern_leaf(vec2 p, float r) {
	float a = atan(p.x, p.y + 1e-6);
	float reach = 0.6 + 0.4 * pow(abs(cos(a * 2.5)), 0.6);
	reach *= mix(1.0, 0.8, smoothstep(0.5, 1.0, -cos(a)));
	float d = (length(p) - r * reach) * 0.75;
	vec2 s = p - vec2(0.0, -r * 0.5);
	float stem = length(vec2(s.x, s.y - clamp(s.y, -r * 0.55, 0.0))) - r * 0.07;
	return min(d, stem);
}

float pattern_wave(float u, vec4 rows, float kind) {
	float x = u / max(rows.z, 1e-4);
	if (kind < 1.5) return rows.w * (1.0 - 4.0 * abs(fract(x + 0.25) - 0.5));
	return rows.w * sin(x * 6.28318530718);
}

// The skin's colour at `p` (the surface's own space, metres, from its centre).
vec3 pattern_color(vec3 p) {
	vec2 uv = vec2(p.x / surface_map.x * 0.5 + 0.5 + skin_drift, (surface_map.y - p.y) / surface_map.z);
	vec3 c = pattern_base;
	for (int i = 0; i < 4; i++) {
		if (field_info[i].y < 0.5) continue;
		float d = pattern_polygon(uv, int(field_info[i].x + 0.5), int(field_info[i].y + 0.5));
		d += field_info[i].z * sin(uv.x * 9.0 + uv.y * 7.0 + float(i) * 2.1);
		c = mix(c, field_color[i], pattern_cover(d));
	}
	for (int i = 0; i < 3; i++) {
		if (band_style[i].x < 0.5) continue;
		float shift = pattern_wave(uv.x, band_rows[i], band_style[i].x);
		float top = band_rows[i].x + shift;
		float bottom = band_rows[i].y + shift;
		c = mix(c, band_color[i], pattern_cover(max(top - uv.y, uv.y - bottom)));
		if (band_style[i].y > 0.0) c = mix(c, band_edge_color[i], pattern_cover(max(top - band_style[i].y - uv.y, uv.y - top)));
	}
	if (seam_half > 0.0 && p.z < 0.0) c = mix(c, seam_color, pattern_cover(abs(p.x) - seam_half));
	vec2 q = vec2(p.x + skin_drift * 2.0 * surface_map.x, p.y);
	float clear = 1.0;
	if (safe_eyes.z > 0.0 && p.z >= 0.0) {
		vec2 e = vec2(abs(p.x) - safe_eyes.x, p.y - safe_eyes.y) / safe_eyes.zw;
		clear = pattern_cover((1.0 - length(e)) * min(safe_eyes.z, safe_eyes.w));
	}
	for (int i = 0; i < 5; i++) {
		if (stamp_style[i].x < 0.5 || stamp_style[i].y * p.z < 0.0) continue;
		vec2 s = q - stamp_at[i].xy;
		float t = stamp_at[i].w;
		s = mat2(vec2(cos(t), -sin(t)), vec2(sin(t), cos(t))) * s;
		float d = stamp_style[i].x < 1.5 ? pattern_star(s, stamp_at[i].z) : pattern_leaf(s, stamp_at[i].z);
		c = mix(c, stamp_color[i], pattern_cover(d) * clear);
	}
	return c;
}
