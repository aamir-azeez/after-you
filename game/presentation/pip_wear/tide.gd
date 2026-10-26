extends RefCounted
## Tide (body): two wavy lines of foam round the head, above and below the
## eyes, and under the low line the pip turns a deeper shade of its own
## colour, as if it went paddling: the head through the face shader's Tide
## variant (spirit_face_tide.gdshader), the torso and feet through their
## materials. No new mesh. The waves move at the idle rate.
const Primitives = preload("res://presentation/kit/primitives.gd")

const SHADER = preload("res://presentation/spirit_face_tide.gdshader")
## Radians a second the waves travel round the head.
const WAVE_SPEED := 0.6

static func wear(look: RefCounted) -> void:
	var deep := deep_shade(look.body_color())
	look.set_face(SHADER, {&"deep_color": deep, &"skin_phase": 0.0})
	look.set_material(look.torso(), Primitives.shared_material(deep, 0.9))
	var feet := Primitives.shared_material(deep.darkened(0.08), 0.9)
	for foot: Node3D in look.feet(): look.set_material(look.foot_mesh(foot), feet)
	look.animate(func(seconds: float) -> void: look.set_face_parameter(&"skin_phase", seconds * WAVE_SPEED))

## A shade deeper in the same hue: each channel raised to a power, so peach
## turns a warmer apricot and mint a deeper sea green, never brown or grey.
static func deep_shade(color: Color) -> Color:
	return Color(pow(color.r, 1.25), pow(color.g, 1.25), pow(color.b, 1.25)).darkened(0.04)
