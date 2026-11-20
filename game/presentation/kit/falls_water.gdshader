shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_schlick_ggx;
// A waterfall's water (kit/props.gd "waterfall"): one mesh per fall, drawn
// over its Blender cliff. COLOR.r picks the part:
//   1  running water: each tier's strip runs flat over its lip (COLOR.g 0),
//      then falls (COLOR.g 1). UV.x is across (0 to 1), UV.y metres along
//      the flow; UV2 is the strip's width and length in metres. COLOR.b 1
//      is a sheet hanging free of rock (clean ends, thicker water).
//   0  foam lying where the water lands, on a ledge or the pool. UV is the
//      spot in -1 to 1 (across, out); UV2 its half size in metres.
// Bright streaks run down the sheet and thin out to a soft edge where it meets
// the rock; it whitens as it nears the foot. The foam churns and sends rings
// out over the pool, as the water's own rings do. Nothing here reads TIME:
// `clock` is the world's (presentation/water_world.gd), so a held world and
// Reduce motion show still water. No depth, screen or texture reads.

uniform vec4 water_color : source_color = vec4(0.72, 0.87, 0.91, 0.78);
uniform vec4 foam_color : source_color = vec4(0.97, 0.99, 1.0, 1.0);
uniform float clock = 0.0;

float hash12(vec2 q) { return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 col;
	float alpha;
	if (COLOR.r > 0.5) {
		float falling = COLOR.g;
		// COLOR.b 1: a sheet hanging free of rock (the curtain over the path
		// behind the falls): thick water, more white, a clean edge at its ends.
		float sheet = COLOR.b;
		float width = UV2.x;
		float across = UV.x * width;
		// Faster and longer streaks once the water drops.
		float along = UV.y - clock * mix(0.7, 2.1, falling);
		float stretch = mix(1.6, 0.55, falling);
		float a = noise(vec2(across * 7.0, along * stretch));
		float b = noise(vec2(across * 19.0 + 3.1, along * stretch * 2.3));
		float streak = smoothstep(mix(0.52, 0.4, sheet), 0.86, a * 0.62 + b * 0.38);
		// White and broken as it nears the foot.
		float white = smoothstep(UV2.y - 0.9, UV2.y, UV.y) * falling;
		// The soft, ragged edge into the rock; a free sheet's end is a clean
		// white line, water seen side on.
		float edge = min(across, width - across);
		float ragged = mix(0.12 + 0.12 * noise(vec2(UV.y * 2.3 - clock * 1.2, step(0.5, UV.x) * 7.0)), 0.02, sheet);
		float soft = smoothstep(0.0, ragged, edge);
		streak = max(streak, sheet * (1.0 - smoothstep(0.04, 0.1, edge)));
		// Fine glints running down with the water.
		float glint = step(0.993, hash12(floor(vec2(across * 26.0, along * 9.0)))) * falling;
		float bright = clamp(streak * 0.85 + white * 0.75 + glint, 0.0, 1.0);
		col = mix(water_color.rgb * mix(0.92, 1.0, falling), foam_color.rgb, bright);
		// Faded in where it starts, so the stream above the top lip comes from
		// the banks rather than ending square.
		alpha = mix(mix(water_color.a, 0.94, sheet), 1.0, bright * 0.9) * soft * smoothstep(0.0, 0.8, UV.y);
	} else {
		vec2 half_m = UV2;
		vec2 p = UV * half_m;
		float r = length(UV);
		float churn = noise(p * 3.2 + vec2(clock * 0.9, -clock * 0.6)) * 0.6 + noise(p * 7.5 - vec2(clock * 0.5, clock * 1.1)) * 0.4;
		// Heaped white where the water lands, frayed at its rim.
		float heap = 1.0 - smoothstep(0.25, 0.62, r + (churn - 0.5) * 0.35);
		// Rings spreading out over the pool and fading, broken by the churn.
		float ph = fract(r * 2.4 - clock * 0.42);
		float ring = (1.0 - smoothstep(0.0, 0.1, abs(ph - 0.5))) * smoothstep(0.3, 0.55, r) * smoothstep(0.35, 0.7, churn);
		float flecks = smoothstep(0.62, 0.8, churn) * (1.0 - smoothstep(0.5, 0.9, r));
		float foam = clamp(max(heap * mix(0.75, 1.0, churn), max(ring * 0.7, flecks * 0.6)), 0.0, 1.0);
		col = foam_color.rgb;
		alpha = foam * (1.0 - smoothstep(0.78, 1.0, r));
	}
	ALBEDO = col;
	ALPHA = alpha;
	ROUGHNESS = 0.35;
	SPECULAR = 0.3;
	// A little of its own light, so the water reads bright in the cliff's shade.
	EMISSION = col * 0.18;
}
