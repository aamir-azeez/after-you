extends "res://tests/test_world_fingerprint.gd"
## Every chapter world draws its scenery with about one material per look: the
## shape helpers share the kit's cached material for each colour
## (Primitives.shared_material), and only meshes whose material changes later
## (a plate that lights, a lamp that glows, a floor that fades) take their own.
## - Built and folded, each chapter's stages use no more materials than
##   MOST_MATERIALS allows. Before the kit shared looks, Turn of the Tide's
##   harbour alone made over a thousand materials, most of them the same look.
## - Driven through its fixture scenarios, Turn of the Tide @2 (not pinned by
##   the world fingerprint) changes no cached look in place.
const Batch = preload("res://presentation/kit/static_batch.gd")

## The most materials a chapter stage's built and folded world may use (all
## geometry, shown or hidden), about a fifth above what it used when the kit
## began sharing looks (Turn of the Tide: 309 against 1,936 before).
const MOST_MATERIALS := {
	"first-steps@1": [74, 74],
	"relay-isles@2": [72, 74],
	"high-and-low@1": [76, 94],
	"rolling-home@1": [87, 95],
	"a-house-for-two@1": [80, 99],
	"conservatory@1": [119, 117],
	"long-way-home@1": [106, 122],
	"the-wishing-well@1": [89, 106],
	"long-way-home@2": [106, 134],
	"turn-of-the-tide@1": [371, 382],
	"sleeping-lighthouse@2": [84, 83, 83, 104, 84, 107],
	"turn-of-the-tide@2": [371, 382],
}
## Of those, the most that are not the kit's shared looks: materials a world
## made itself (water, glass, lamps, plates, spirits and their faces).
const MOST_OWN := {
	"first-steps@1": [24, 24],
	"relay-isles@2": [25, 25],
	"high-and-low@1": [19, 24],
	"rolling-home@1": [23, 28],
	"a-house-for-two@1": [20, 28],
	"conservatory@1": [40, 37],
	"long-way-home@1": [40, 42],
	"the-wishing-well@1": [18, 23],
	"long-way-home@2": [40, 52],
	"turn-of-the-tide@1": [227, 235],
	"sleeping-lighthouse@2": [18, 22, 25, 30, 29, 31],
	"turn-of-the-tide@2": [227, 235],
}

func _suite() -> String:
	return "world_looks"

func _run() -> void:
	for key: String in Registry.keys():
		var definition := Registry.definition(key)
		if definition.is_empty() or definition.get("stages", []).is_empty(): continue
		for index in range(definition.stages.size()):
			_census(key, definition, index)
	var key := "turn-of-the-tide@2"
	var stages := _snapshots(key)
	_check(stages.size() == 2, key + ": both stages replay from their fixtures")
	_passes(key, false, stages)
	_check(Primitives.changed_shared_looks().is_empty(), key + ": its scenarios change no cached look in place: %s" % [Primitives.changed_shared_looks()])
	print("WORLD LOOKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Turn of the Tide @2 has no replay golden chain yet: its stage fixtures.
func _native_chain(key: String) -> Dictionary:
	var spec := super._native_chain(key)
	if not spec.is_empty() or key != "turn-of-the-tide@2": return spec
	var stages: Array = []
	for stage_id: String in ["set-the-tide", "slack-water"]:
		var prefix := "journey/turn-of-the-tide-v2-" + stage_id
		stages.append([prefix + "-a.json", prefix + "-b.json", prefix + "-checkpoint.json"])
	return {"stages": stages}

func _census(key: String, definition: Dictionary, index: int) -> void:
	var viewport := _viewport()
	var world: Node3D = Registry.world_script(key).new()
	_mount(viewport, world, false)
	world.load_level(definition)
	world.present_stage(definition.stages[index])
	if world._folds_static_scenery(): world._fold_static_scenery()
	var materials: Dictionary = {}
	var own := 0
	for node: Node in world.find_children("*", "GeometryInstance3D", true, false):
		var mat: Material = (node as GeometryInstance3D).material_override
		if mat == null or materials.has(mat.get_instance_id()): continue
		materials[mat.get_instance_id()] = true
		if not Primitives.is_shared(mat): own += 1
	var label := "%s stage %d" % [key, index + 1]
	print("LOOKS|%s|materials %d|own %d" % [label, materials.size(), own])
	var most: Array = MOST_MATERIALS.get(key, [])
	var most_own: Array = MOST_OWN.get(key, [])
	if _check(index < most.size() and index < most_own.size(), label + ": has a material bound (MOST_MATERIALS, MOST_OWN)"):
		_check(materials.size() <= int(most[index]), label + ": uses at most %d materials (%d)" % [int(most[index]), materials.size()])
		_check(own <= int(most_own[index]), label + ": at most %d of them its own, not kit looks (%d)" % [int(most_own[index]), own])
	viewport.free()
