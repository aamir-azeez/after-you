shader_type spatial;
// The ball itself while it rolls: its band smeared around the spin axis.
// One material for every rolling ball; each ball sets its own values.
#include "res://presentation/ball_spin_coverage.gdshaderinc"
instance uniform vec4 ball_color : source_color = vec4(0.91, 0.93, 0.84, 1.0);
instance uniform vec4 band_color : source_color = vec4(0.20, 0.29, 0.36, 1.0);
// Rotation axis in the ball's own space, and the rotation the exposure covers.
instance uniform vec3 spin_axis = vec3(0.0, 0.0, 1.0);
instance uniform float exposure_angle = 0.0;
// Half the band's width on the unit sphere, measured from the band mesh, so
// the stripe at rest is exactly as wide as the sharp band.
instance uniform float band_half_width = 0.30;
uniform int taps = 12;
uniform float tail_weight = 0.35;
varying vec3 surface_position;
void vertex() { surface_position = VERTEX; }
void fragment() {
	// The band's plane is the ball's local x = 0.
	float covered = spin_coverage(surface_position, vec3(1.0, 0.0, 0.0), normalize(spin_axis), exposure_angle, band_half_width, taps, tail_weight);
	ALBEDO = mix(ball_color.rgb, band_color.rgb, covered);
	ROUGHNESS = 0.9;
}
