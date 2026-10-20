shader_type spatial;
// World kit goal beacon (goal_beacon.gd): each piece moves on the GPU from
// TIME alone, so a beacon at rest costs no CPU work. `motion` 0 (Reduce
// motion) holds every piece in its rest pose.
render_mode unshaded, cull_disabled, shadows_disabled;

// 0 still, 1 a floor ring breathing outward, 2 a pennant fluttering from its
// hoist (the mesh's -x end), 3 a lamp bobbing gently.
uniform int part = 0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float motion = 1.0;
uniform float hoist = -0.17;
uniform float span = 0.34;

void vertex() {
	float t = TIME * motion;
	if (part == 1) {
		VERTEX.xz *= 1.0 + 0.12 * motion * (0.5 + 0.5 * sin(t * 2.6));
	} else if (part == 2) {
		float along = clamp((VERTEX.x - hoist) / span, 0.0, 1.0);
		VERTEX.z += sin(t * 5.0 - along * 5.0) * 0.045 * along * motion;
	} else if (part == 3) {
		VERTEX.y += sin(t * 2.0) * 0.035 * motion;
	}
}

void fragment() {
	ALBEDO = tint;
}
