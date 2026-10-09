shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;
uniform vec4 trail_color : source_color = vec4(0.91, 0.93, 0.84, 0.12);
void fragment() {
	ALBEDO = trail_color.rgb;
	// Feather the rounded silhouette instead of duplicating a pickable ball.
	ALPHA = trail_color.a * pow(max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 1.6) * pow(1.0 - UV.y, 0.6);
}
