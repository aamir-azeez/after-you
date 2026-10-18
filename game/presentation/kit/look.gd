extends RefCounted
## World kit: the one place a chapter world's lighting is set. Presets give the
## sky, ambient light, sun, bounce light and mote tint; apply() writes them to
## the nodes island_world creates in _ready. They never add or remove motes, so
## graphics quality keeps counting the motes each lineage authored.

## The sun draws no shadow pass at any quality. In gl_compatibility that pass
## added the sun's light on top of the base pass, which lit scenes brighter
## than one pass does; these gains keep the old brightness. Presets keep their
## original values.
const SUN_GAIN := 2.2
const AMBIENT_GAIN := 2.0
## Lamps (OmniLight3D) now add to that brighter base, so their pools need more
## energy to show as before. Every lamp's energy goes through lamp_energy().
const LAMP_GAIN := 2.5

const PRESETS := {
	# The meadow day of Home, First Steps and the Relay Isles.
	"day": {"sky": Color("123a3d"), "ambient": Color("c4e0d1"), "ambient_energy": 0.26, "sun": Color("fff0cb"), "sun_energy": 0.65, "bounce": Color("8ebbb2"), "bounce_energy": 0.24, "mote": Color("c1ddbd")},
	# The Sleeping Lighthouse night, which every physical chapter inherited.
	"night": {"sky": Color("111e32"), "ambient": Color("b0c9df"), "ambient_energy": 0.42, "sun": Color("c4d9ef"), "sun_energy": 0.72, "bounce": Color("859cba"), "bounce_energy": 0.28, "mote": Color("8aabc0")},
	# The Wishing Well dusk.
	"dusk": {"sky": Color("2b2945"), "ambient": Color("aeb3cf"), "ambient_energy": 0.42, "sun": Color("f4d9bf"), "sun_energy": 0.72, "bounce": Color("8e95c6"), "bounce_energy": 0.3, "mote": Color("e7c48e")},
	# A sunny meadow for the physical chapters: the day family, a touch warmer
	# and brighter so grass, timber and tile read warm rather than grey.
	"meadow": {"sky": Color("1c4744"), "ambient": Color("e3e2c8"), "ambient_energy": 0.34, "sun": Color("fff0cb"), "sun_energy": 0.72, "bounce": Color("a6c4b0"), "bounce_energy": 0.24, "mote": Color("efe2b0")},
	# Golden hour: lamps and windows glow, the sky is a warm plum dusk.
	"golden": {"sky": Color("2f2a40"), "ambient": Color("d8ccc0"), "ambient_energy": 0.40, "sun": Color("f7ddc2"), "sun_energy": 0.68, "bounce": Color("9b97c6"), "bounce_energy": 0.28, "mote": Color("f2c98e")},
}

static func preset(name: String) -> Dictionary:
	return PRESETS.get(name, PRESETS.day)

## A lamp's energy, from the value it was tuned at with the shadow pass.
static func lamp_energy(energy: float) -> float:
	return energy * LAMP_GAIN

## Lights the world's environment, sun and bounce light and tints its motes.
static func apply(world: Node3D, name: String) -> void:
	var look := preset(name)
	var sun: DirectionalLight3D = world.get("sun")
	for child: Node in world.get_children():
		if child is WorldEnvironment:
			child.environment.background_color = look.sky
			child.environment.ambient_light_color = look.ambient
			child.environment.ambient_light_energy = look.ambient_energy * AMBIENT_GAIN
		elif child == sun:
			sun.light_color = look.sun
			sun.light_energy = look.sun_energy * SUN_GAIN
			sun.shadow_enabled = false
		elif child is DirectionalLight3D:
			child.light_color = look.bounce
			child.light_energy = look.bounce_energy
	for mote: MeshInstance3D in world.get("motes"):
		(mote.material_override as StandardMaterial3D).albedo_color = look.mote
