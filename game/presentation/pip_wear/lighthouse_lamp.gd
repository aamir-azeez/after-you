extends RefCounted
## Lighthouse lamp (hat, Special): a tiny lamp room in the lighthouse's slate
## and brass, worn on the head across from the leaf, with a faint beam and a
## light that slowly brightens and dims like the lighthouse breathing in its
## sleep. The glow is the glass's own (emissive) plus one small soft sprite on
## the lamp's outer side, so it never washes over the head. Draw calls: the
## lamp, the glass, the glow, the beam. It moves at the idle rate.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")

const SLATE_DARK := Color("536979")
const BRASS := Color("b09e78")
const ROOF := Color("c4ad7c")
const LIGHT := Color("ffd98a")
const GLASS_ENERGY := 1.7
## The lamp in head space: where it sits, its tilt and size.
const AT := Vector3(0.205, 0.228, 0.0)
const TURN := Vector3(0.12, 0.0, -0.5)
const SIZE := 1.12
## The glass's middle in the lamp's own space.
const GLASS_AT := Vector3(0, 0.1, 0)
const GLOW_SIZE := 0.22
const GLOW_STRENGTH := 0.8
## How far the glow sprite sits out from the glass, away from the head.
const GLOW_OUT := 0.035
## The beam (head space): where it starts, where it points, how long and wide.
const BEAM_FROM := Vector3(0.262, 0.33, 0.0)
const BEAM_TOWARD := Vector3(1.0, 0.08, -0.15)
const BEAM_LENGTH := 0.6
const BEAM_WIDTH := 0.22
const BEAM_STRENGTH := 0.22
## Seconds for one brighten and dim.
const BREATH := 4.0

## The lamp's place on the head.
static func frame() -> Transform3D:
	return Kit.Parts.place(AT, TURN, Vector3.ONE * SIZE)

static func wear(look: RefCounted) -> void:
	var head: Node3D = look.head()
	look.mesh(head, Kit.cached_mesh("lighthouse_lamp", _build), Kit.vertex_material())
	var glass_material := Kit.glow_material(LIGHT, LIGHT, GLASS_ENERGY)
	look.mesh(head, Kit.cached_mesh("lighthouse_lamp:glass", _glass), glass_material)
	var glass := frame() * GLASS_AT
	var glow := Kit.halo(GLOW_SIZE, LIGHT, GLOW_STRENGTH)
	glow.position = glass + glass.normalized() * GLOW_OUT
	look.attach(head, glow)
	var beam := Kit.beam("lighthouse_lamp", BEAM_FROM, BEAM_TOWARD, BEAM_LENGTH, BEAM_WIDTH, BEAM_STRENGTH)
	look.attach(head, beam)
	var glow_material: StandardMaterial3D = glow.material_override
	var beam_material: StandardMaterial3D = beam.material_override
	look.animate(func(seconds: float) -> void:
		var breath := 0.5 - 0.5 * cos(seconds * TAU / BREATH)
		glass_material.emission_energy_multiplier = GLASS_ENERGY * (0.7 + 0.3 * breath)
		glow_material.albedo_color.a = GLOW_STRENGTH * (0.6 + 0.4 * breath)
		beam_material.albedo_color.a = BEAM_STRENGTH * (0.5 + 0.5 * breath))

static func _build() -> Mesh:
	var parts := Kit.Parts.new()
	parts.push(frame())
	parts.cylinder(SLATE_DARK, Vector3(0, 0.022, 0), 0.092, 0.05, 0.084)
	parts.cylinder(BRASS, Vector3(0, 0.052, 0), 0.098, 0.016)
	for index in range(6):
		var a := TAU * float(index) / 6.0
		var at := Vector3(cos(a) * 0.066, 0.0, sin(a) * 0.066)
		parts.rod(BRASS, at + Vector3(0, 0.058, 0), at + Vector3(0, 0.142, 0), 0.008, 5)
	parts.cylinder(BRASS, Vector3(0, 0.146, 0), 0.084, 0.014)
	parts.cylinder(ROOF, Vector3(0, 0.182, 0), 0.078, 0.062, 0.012)
	parts.blob(BRASS, Vector3(0, 0.226, 0), Vector3.ONE * 0.018, Vector3.ZERO, 6, 3)
	parts.pop()
	return parts.commit()

static func _glass() -> Mesh:
	var parts := Kit.Parts.new()
	parts.push(frame())
	parts.cylinder(LIGHT, GLASS_AT, 0.066, 0.082)
	parts.pop()
	return parts.commit()
