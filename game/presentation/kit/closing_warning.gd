extends RefCounted
## World kit: the one closing warning (presentation/cooperative_world.gd hosts
## one for every chapter world; never a copy). While a crossing closes (the
## snapshot's route_progress.closing: route id -> ticks left before it shuts,
## core/physical/runtime.gd CLOSING_GRACE_TICKS), the whole crossing (its deck,
## rails, ropes and everything else that is about to go: the world's
## closing_parts) fades out and back in with the ticks left, so live play, the
## friend's replay, a memory and a replay all blink alike; Reduce motion holds
## it at a steady half fade instead. Held, crank and rope bridges and stones
## all close this way, so every one warns the same.
## It fades through each mesh's own transparency (GeometryInstance3D), so no
## material is copied or made and a deck's batches fade like any mesh; every
## mesh goes back to the transparency it had once the crossing is held again
## or has shut. Presentation only.
## Ticks a blink takes to fade out, then as many to come back: three blinks a
## second at 30 ticks. Other warnings blink on this timing too.
const BLINK := 5
## The crossing's transparency at the bottom of a blink, and held under Reduce motion.
const FADED := 0.7
const STEADY := 0.5

var _world: Node3D
## Route id -> {mesh: the transparency it had before the warning}, for every
## crossing warning now.
var _fading: Dictionary = {}
## Route id -> the most ticks left seen in this warning: a blink starts from
## solid, wherever the warning is first seen.
var _first: Dictionary = {}

func _init(world: Node3D) -> void:
	_world = world

## A new stage: its terrain is built again, so the fading meshes are forgotten.
func forget() -> void:
	_fading.clear()
	_first.clear()

## Each snapshot: its closing crossings (route id -> ticks left; {} for none).
func show(closing: Dictionary) -> void:
	for id: String in _fading.keys():
		if not closing.has(id): _restore(id)
	for key: Variant in closing:
		var id := str(key)
		var ticks := int(closing[key])
		_first[id] = maxi(int(_first.get(id, ticks)), ticks)
		var amount := STEADY if _world.reduced_motion else fade(ticks, int(_first[id]))
		var meshes: Dictionary = _meshes(id)
		for mesh: Variant in meshes:
			if is_instance_valid(mesh): (mesh as GeometryInstance3D).transparency = maxf(float(meshes[mesh]), amount)

## How faded (0 solid, FADED most) a crossing `ticks` from shutting is, its
## warning first seen `first` ticks from shutting: a smooth blink every
## BLINK * 2 ticks, solid as it shuts, eased in from solid at the start.
static func fade(ticks: int, first: int) -> float:
	var blink := (1.0 - cos(PI * float(ticks) / float(BLINK))) * 0.5
	return FADED * blink * clampf(float(first - ticks) / float(BLINK), 0.0, 1.0)

## Route `id`'s meshes and the transparency each had, found on its first
## warning (and again should a fold have swapped them).
func _meshes(id: String) -> Dictionary:
	var had: Dictionary = _fading.get(id, {})
	if not had.is_empty() and had.keys().all(func(mesh: Variant) -> bool: return is_instance_valid(mesh)): return had
	var meshes: Dictionary = {}
	for part: Node3D in _world.closing_parts(id):
		if not is_instance_valid(part): continue
		var found: Array = part.find_children("*", "GeometryInstance3D", true, false)
		if part is GeometryInstance3D: found.append(part)
		for mesh: GeometryInstance3D in found: meshes[mesh] = had.get(mesh, mesh.transparency)
	_fading[id] = meshes
	return meshes

func _restore(id: String) -> void:
	var meshes: Dictionary = _fading.get(id, {})
	for mesh: Variant in meshes:
		if is_instance_valid(mesh): (mesh as GeometryInstance3D).transparency = float(meshes[mesh])
	_fading.erase(id)
	_first.erase(id)
