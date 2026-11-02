extends RefCounted
## Tide (body): colour only, no geometry. The head through the face shader's
## Tide variant (spirit_face_tide.gdshader: two foam lines, a deeper shade
## below the low one), the torso through spirit_body_tide.gdshader (the deeper
## shade and one foam line), the feet through a deeper material. The waves
## move at the idle rate.
const Primitives = preload("res://presentation/kit/primitives.gd")

const SHADER = preload("res://presentation/spirit_face_tide.gdshader")
const BODY_SHADER = preload("res://presentation/spirit_body_tide.gdshader")
## Radians a second the waves travel round the head.
const WAVE_SPEED := 0.6
## The shade below the low wave: each channel raised to DEEP_POWER, then
## darkened, so peach turns a rich apricot and mint a deep sea green, never grey.
const DEEP_POWER := 2.2
const DEEP_DARKEN := 0.14

static func wear(look: RefCounted) -> void:
	var deep := deep_shade(look.body_color())
	look.set_face(SHADER, {&"deep_color": deep, &"skin_phase": 0.0})
	var body := ShaderMaterial.new()
	body.shader = BODY_SHADER
	body.set_shader_parameter(&"body_color", deep)
	look.set_material(look.torso(), body)
	var feet := Primitives.shared_material(deep.darkened(0.08), 0.9)
	for foot: Node3D in look.feet(): look.set_material(look.foot_mesh(foot), feet)
	look.animate(func(worn: RefCounted, seconds: float) -> void:
		worn.set_face_parameter(&"skin_phase", seconds * WAVE_SPEED)
		body.set_shader_parameter(&"skin_phase", seconds * WAVE_SPEED))

## A clearly deeper shade in the same hue, readable at the smallest pip sizes
## and under the Home island's bright light (DEEP_POWER, DEEP_DARKEN).
static func deep_shade(color: Color) -> Color:
	return Color(pow(color.r, DEEP_POWER), pow(color.g, DEEP_POWER), pow(color.b, DEEP_POWER)).darkened(DEEP_DARKEN)
