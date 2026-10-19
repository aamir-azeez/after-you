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
## began sharing looks (Turn of the Tide: 322 against 1,936 before).
const MOST_MATERIALS := {
	"first-steps@1": [74, 74],
	"relay-isles@2": [72, 74],
	"high-and-low@1": [76, 95],
	"rolling-home@1": [88, 96],
	"a-house-for-two@1": [88, 104],
	"conservatory@1": [126, 124],
	"long-way-home@1": [107, 124],
	"the-wishing-well@1": [118, 135],
	"long-way-home@2": [107, 136],
	"turn-of-the-tide@1": [387, 405],
	"sleeping-lighthouse@2": [86, 83, 86, 105, 84, 110],
	"turn-of-the-tide@2": [387, 402],
}
## Of those, the most that are not the kit's shared looks: materials a world
## made itself (water, glass, lamps, plates, spirits and their faces).
const MOST_OWN := {
	"first-steps@1": [24, 24],
	"relay-isles@2": [25, 25],
	"high-and-low@1": [22, 26],
	"rolling-home@1": [25, 29],
	"a-house-for-two@1": [31, 36],
	"conservatory@1": [50, 47],
	"long-way-home@1": [43, 46],
	"the-wishing-well@1": [48, 53],
	"long-way-home@2": [43, 55],
	"turn-of-the-tide@1": [247, 260],
	"sleeping-lighthouse@2": [24, 25, 30, 35, 31, 36],
	"turn-of-the-tide@2": [247, 258],
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
	_check(Primitives.changed_shared_materials().is_empty(), key + ": its scenarios change no cached look in place: %s" % [Primitives.changed_shared_materials()])
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
