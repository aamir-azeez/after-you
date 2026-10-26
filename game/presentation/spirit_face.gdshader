shader_type spatial;
// A spirit's head: its body colour with the two eyes painted on as flat
// surface art (presentation/spirit_look.gd describes every uniform in
// spirit_face.gdshaderinc, which holds the body of this shader).
// The eyes are drawn from the head's own position, projected straight onto
// the face, so they follow the head, are hidden by whatever hides the head and
// never show from behind. No time input: everything moves through uniforms
// written from the spirit's own clock.

#include "res://presentation/spirit_face.gdshaderinc"
