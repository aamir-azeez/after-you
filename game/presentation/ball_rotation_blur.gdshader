shader_type spatial;
uniform vec4 ball_color : source_color = vec4(0.57, 0.84, 0.78, 1.0);
uniform vec4 band_color : source_color = vec4(0.20, 0.29, 0.36, 1.0);
uniform vec3 spin_axis = vec3(0.0, 0.0, 1.0);
uniform float exposure_angle = 0.0;
varying vec3 surface_position;
void vertex() { surface_position = VERTEX; }
vec3 rotate_point(vec3 p, vec3 axis, float angle) {
	return p * cos(angle) + cross(axis, p) * sin(angle) + axis * dot(axis, p) * (1.0 - cos(angle));
}
void fragment() {
	vec3 p = normalize(surface_position);
	vec3 axis = normalize(spin_axis);
	float stripe = 0.0;
	for (int i = 0; i < 12; i++) {
		vec3 previous = rotate_point(p, axis, float(i) / 11.0 * exposure_angle);
		stripe += 1.0 - smoothstep(0.09, 0.16, abs(previous.x));
	}
	ALBEDO = mix(ball_color.rgb, band_color.rgb, stripe / 12.0);
	ROUGHNESS = 0.9;
}
