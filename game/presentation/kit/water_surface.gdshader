shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;
// Every body of water's look (presentation/kit/water_look.gd, values from
// content/water/looks.gd). Soft ripples from two panning reads of one small
// tiling slope texture, a soft foam band where the water meets what stands in
// it (one small edge map per body and level), a shade darker as it deepens,
// clear enough to show the seabed while thin, rings round up to eight spots
// and a few glints. Nothing here reads TIME: `clock` is the kit's own,
// advanced with the world, so a held world and a still show still water.
// No vertex lift, no depth read and no screen read.

uniform vec4 base_color : source_color;
// Solid share round each spot (1 = something stands there), blurred so it
// falls off over about 20 cm: one per body and level (water_look.gd).
uniform sampler2D edges : filter_linear_mipmap, repeat_disable;
// x0, z0, width, depth of the edge map (terrain metres).
uniform vec4 edge_rect = vec4(0.0, 0.0, 1.0, 1.0);
// Ripple slopes in RG (0.5 = flat), tiling.
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;
uniform float clock = 0.0;
// Where this mesh's vertices sit in the terrain's plan (a flood's centre).
uniform vec2 offset_xz = vec2(0.0);
// Metres from the seabed to the water's surface, and 1 while the seabed shows.
uniform float depth_m = 0.6;
uniform float floor_on = 1.0;
// 1 draws the second ripple layer and the far edge read (GraphicsPolicy.water_detail).
uniform float detail = 1.0;
uniform float sparkles = 1.0;
// How warm the glints near lamps are (the light's "glints", kit/look.gd).
uniform float warm = 0.0;
uniform vec4 lamps[8];
uniform int lamp_count = 0;
// x, z, phase, strength of each ring spot.
uniform vec4 rings[8];
uniform int ring_count = 0;
uniform float clear_from = 0.15;
uniform float clear_to = 1.3;
uniform float clear_alpha = 0.24;
uniform float deep_alpha = 0.9;

varying vec2 plan;
varying float top;

float hash12(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	plan = VERTEX.xz + offset_xz;
	top = NORMAL.y > 0.5 ? 1.0 : 0.0;
}

void fragment() {
	vec2 p = plan;
	// Metres from what the water meets, from the solid share round the spot:
	// the 8 cm cells near it, each wider mip further out (up to about 22 cm).
	// Each mip's share falls off twice as wide, so it counts twice the metres.
	vec2 euv = (p - edge_rect.xy) / edge_rect.zw;
	float d = clamp((0.5 - textureLod(edges, euv, 0.0).r) * 0.107, 0.0, 0.053);
	float d1 = clamp((0.5 - textureLod(edges, euv, 1.0).r) * 0.213, 0.0, 0.106);
	d = mix(d, max(d, d1), smoothstep(0.035, 0.05, d));
	if (detail > 0.5) {
		float d2 = clamp((0.5 - textureLod(edges, euv, 2.0).r) * 0.43, 0.0, 0.215);
		d = mix(d, max(d, d2), smoothstep(0.07, 0.1, d1));
	}
	// Wide, slow light and shade (no texture read).
	float big = 0.5 + 0.25 * sin(p.x * 0.21 + sin(p.y * 0.13) * 1.7) + 0.25 * sin(p.y * 0.17 - p.x * 0.07 + 1.3);
	float blot = 0.5 + 0.3 * sin(p.x * 0.37 + clock * 0.02 + sin(p.y * 0.29) * 2.1) + 0.2 * sin(p.y * 0.53 - p.x * 0.19);
	float deep_shade = mix(1.0, 0.64, clamp(depth_m / 1.4, 0.0, 1.0));
	vec3 base = base_color.rgb;
	vec3 shallow = mix(base, vec3(0.72, 0.90, 0.86), 0.30) * deep_shade * 1.08;
	vec3 col = mix(shallow, base * deep_shade, smoothstep(0.02, 0.22, d));
	col *= mix(0.95, 1.06, big);
	// Two ripple layers panning across each other.
	vec2 na = texture(ripples, p * 0.30 + vec2(clock * 0.020, clock * 0.012)).rg * 2.0 - 1.0;
	vec2 nb = detail > 0.5 ? texture(ripples, p * 0.47 + vec2(-clock * 0.016, clock * 0.021)).rg * 2.0 - 1.0 : vec2(-na.y, na.x) * 0.8;
	vec2 slope = (na + nb) * 0.5 * 0.55;
	vec3 n = normalize(vec3(slope.x, 1.0, slope.y));
	float ripple = 0.5 + 0.5 * (na.x * nb.y);
	// Soft lighter streaks where the two layers agree.
	float along = abs(slope.x + slope.y);
	float lines = smoothstep(0.18, 0.32, along) * (1.0 - smoothstep(0.32, 0.5, along));
	col = mix(col, col * 1.2 + 0.04, lines * 0.45 * smoothstep(0.05, 0.2, d));
	float sparkle = smoothstep(0.30, 0.42, dot(na, nb)) * smoothstep(0.35, 0.8, big) * smoothstep(0.1, 0.2, d);
	// Foam: a soft band where the water meets something, and a thinner broken
	// ring a little further out, both faded by the slow blot.
	float fd = d + (ripple - 0.5) * 0.05;
	float band = 1.0 - smoothstep(0.02, 0.06 + 0.03 * blot, fd);
	float ring_at = 0.11 + 0.02 * sin(clock * 0.8 + blot * 6.0);
	float fring = (1.0 - smoothstep(0.0, 0.018, abs(fd - ring_at))) * smoothstep(0.45, 0.75, blot + (ripple - 0.5) * 0.4);
	float foam = clamp(band * mix(0.35, 0.8, smoothstep(0.25, 0.75, blot)) + fring * 0.35, 0.0, 1.0) * top;
	col = mix(col, vec3(0.97, 0.98, 0.95), foam);
	float alpha = mix(base_color.a, 1.0, foam);
	// The seabed shows through thin water and fades to the tint as it deepens.
	if (floor_on > 0.5) {
		float deepness = smoothstep(clear_from, clear_to, depth_m);
		col = mix(mix(col, vec3(0.62, 0.87, 0.85), 0.40), col, deepness);
		alpha = max(mix(clear_alpha, max(base_color.a, deep_alpha), deepness), foam);
	}
	// Rings spreading from each spot, a new one every second, each fading.
	float ringv = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= ring_count) break;
		float r = length(p - rings[i].xy);
		if (r > 0.95) continue;
		float aa = max(fwidth(r), 0.002);
		for (int k = 0; k < 3; k++) {
			float ph = fract(rings[i].z + clock * 0.32 + float(k) / 3.0);
			float rad = 0.12 + ph * 0.75;
			float w = 0.016 + 0.012 * ph;
			float l = 1.0 - smoothstep(w, w + aa * 2.5, abs(r - rad));
			l *= smoothstep(0.0, 0.1, ph) * pow(1.0 - ph, 0.9) * rings[i].w;
			ringv = max(ringv, l);
		}
	}
	ringv *= smoothstep(0.01, 0.05, d) * top;
	col = mix(col, vec3(0.97, 1.0, 0.98), ringv * 0.9);
	alpha = max(alpha, ringv * 0.9);
	// A few tiny glints that wink in and out, warmer and more often by lamps.
	// Only a pixel near its cell's glint, while that glint is lit, does more.
	vec3 glints = vec3(0.0);
	if (sparkles > 0.5 && top > 0.5) {
		float cs = 0.36;
		vec2 cell = floor(p / cs);
		vec2 c = (cell + 0.35 + 0.3 * vec2(hash12(cell), hash12(cell + 9.1))) * cs;
		vec2 o = abs(p - c);
		float life = 0.5 + 0.5 * sin(clock * 1.9 + hash12(cell + 5.3) * 60.0);
		if (dot(o, o) < 0.03 && life > 0.6) {
			float near = 0.0;
			if (warm > 0.0) {
				for (int i = 0; i < 8; i++) {
					if (i >= lamp_count) break;
					vec2 off = p - lamps[i].xy;
					near = max(near, exp(-dot(off, off) / 6.0));
				}
				near *= warm;
			}
			float on = smoothstep(0.6, 0.95, life) * step(1.0 - mix(0.07, 0.5, near), hash12(cell + 3.7)) * smoothstep(0.06, 0.16, d);
			float star = max(exp(-o.x * o.x / 0.00014 - o.y * o.y / 0.006), exp(-o.y * o.y / 0.00014 - o.x * o.x / 0.006));
			star = max(star, exp(-dot(o, o) / 0.0009)) * on;
			glints = mix(vec3(1.0, 1.0, 0.96), vec3(1.0, 0.72, 0.38), near) * star;
			col = mix(col, mix(vec3(1.0), vec3(1.0, 0.80, 0.52), near), clamp(star, 0.0, 1.0) * 0.6);
			alpha = max(alpha, clamp(star, 0.0, 1.0));
		}
	}
	ALBEDO = col;
	ROUGHNESS = 0.28;
	SPECULAR = 0.35;
	if (top > 0.5) NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	EMISSION = (vec3(1.0) * sparkle * 0.9 + glints * 1.4) * top + col * 0.06;
	ALPHA = alpha;
}
