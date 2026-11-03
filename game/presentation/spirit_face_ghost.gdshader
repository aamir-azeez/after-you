shader_type spatial;
// The race ghost's head (presentation/race_ghost_view.gd): the spirit face at
// `veil` strength, drawn see-through. Everything else is spirit_face.gdshader's.
render_mode blend_mix;
#define SPIRIT_VEIL

#include "res://presentation/spirit_face.gdshaderinc"
