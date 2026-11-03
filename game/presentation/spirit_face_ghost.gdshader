shader_type spatial;
// The race ghost's head (presentation/race_ghost_view.gd): the spirit face at
// `veil` strength, drawn see-through. A depth pre-pass keeps the head one even
// veil where its own surface folds. Everything else is spirit_face.gdshader's.
render_mode blend_mix, depth_prepass_alpha;
#define SPIRIT_VEIL

#include "res://presentation/spirit_face.gdshaderinc"
