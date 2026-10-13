shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// The raised band while the ball rolls: it fades by how much of the exposure
// it still covers, so it thins into the smear instead of vanishing.
// One material for every band; each band sets its own values, in world space.
#include "res://presentation/ball_spin_coverage.gdshaderinc"
instance uniform vec4 band_color : source_color = vec4(0.20, 0.29, 0.36, 1.0);
instance uniform vec3 ball_center = vec3(0.0);
instance uniform vec3 band_normal = vec3(1.0, 0.0, 0.0);
instance uniform vec3 spin_axis = vec3(0.0, 0.0, 1.0);
instance uniform float exposure_angle = 0.0;
instance uniform float band_half_width = 0.30;
uniform int taps = 12;
uniform float tail_weight = 0.35;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	ALBEDO = band_color.rgb;
	ROUGHNESS = 0.9;
	ALPHA = spin_coverage(world_position - ball_center, normalize(band_normal), normalize(spin_axis), exposure_angle, band_half_width, taps, tail_weight);
}
