extends RefCounted
## World kit: look presets. Sky, ambient light, sun, bounce light and mote tint
## for a chapter world. Presets only recolour the nodes island_world creates in
## _ready; they never add or remove motes, so graphics quality keeps counting
## the motes each lineage authored.

const PRESETS := {
	# The meadow day of Home, First Steps and the Relay Isles.
	"day": {"sky": Color("123a3d"), "ambient": Color("c4e0d1"), "ambient_energy": 0.26, "sun": Color("fff0cb"), "sun_energy": 0.65, "bounce": Color("8ebbb2"), "bounce_energy": 0.24, "mote": Color("c1ddbd")},
	# The Sleeping Lighthouse night, which every physical chapter inherited.
	"night": {"sky": Color("111e32"), "ambient": Color("b0c9df"), "ambient_energy": 0.42, "sun": Color("c4d9ef"), "sun_energy": 0.72, "bounce": Color("859cba"), "bounce_energy": 0.28, "mote": Color("8aabc0")},
	# The Wishing Well dusk.
	"dusk": {"sky": Color("2b2945"), "ambient": Color("aeb3cf"), "ambient_energy": 0.42, "sun": Color("f4d9bf"), "sun_energy": 0.72, "bounce": Color("8e95c6"), "bounce_energy": 0.3, "mote": Color("e7c48e")},
}

static func preset(name: String) -> Dictionary:
	return PRESETS.get(name, PRESETS.day)

## Recolours the world's environment, sun, bounce light and motes.
static func apply(world: Node3D, name: String) -> void:
	var look := preset(name)
	var sun: DirectionalLight3D = world.get("sun")
	for child: Node in world.get_children():
		if child is WorldEnvironment:
			child.environment.background_color = look.sky
			child.environment.ambient_light_color = look.ambient
			child.environment.ambient_light_energy = look.ambient_energy
		elif child is DirectionalLight3D:
			child.light_color = look.sun if child == sun else look.bounce
			child.light_energy = look.sun_energy if child == sun else look.bounce_energy
	for mote: MeshInstance3D in world.get("motes"):
		(mote.material_override as StandardMaterial3D).albedo_color = look.mote
