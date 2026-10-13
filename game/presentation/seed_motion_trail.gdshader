shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, world_vertex_coords;
// The tube is built here from the flight history, so the mesh never changes:
// UV.x is the side (0..1 around the tube), UV.y the history sample.
// Flight history in world space, oldest first; w is freshness (1 = now).
uniform vec4 path[64];
uniform int count = 0;
uniform float width = 0.08;
uniform vec4 trail_color : source_color = vec4(0.91, 0.93, 0.84, 0.6);
varying float freshness;
void vertex() {
	int last = max(count - 1, 0);
	int i = min(int(UV.y + 0.5), last);
	vec3 tangent = path[min(i + 1, last)].xyz - path[max(i - 1, 0)].xyz;
	tangent = dot(tangent, tangent) > 1e-12 ? normalize(tangent) : vec3(1.0, 0.0, 0.0);
	vec3 across = normalize(cross(tangent, abs(tangent.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 vertical = normalize(cross(tangent, across));
	float angle = TAU * UV.x;
	vec3 normal = across * cos(angle) + vertical * sin(angle);
	freshness = clamp(path[i].w, 0.0, 1.0);
	// A tapered tail stays at its historic world position while the head moves.
	VERTEX = path[i].xyz + normal * width * sqrt(freshness);
	NORMAL = normal;
}
void fragment() {
	ALBEDO = trail_color.rgb;
	ALPHA = trail_color.a * pow(max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 1.6) * pow(freshness, 0.6);
}
