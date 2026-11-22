extends "res://tests/chapter_world_suite.gd"
## turn-of-the-tide@2 played through its solo scene and world; see chapter_world_suite.gd.
const Witness = preload("res://tests/turn_of_the_tide_v2_witness.gd")
const SpotChecks = preload("res://tests/pad_checks.gd")

## Every pressure pad is a board ringed exactly at its radius_cm, the
## turn's beacon rings breathe on them, and after the first turn's real
## inputs the pad that counts shows held and no other does.
func _turn_played(screen: Node, stage: Dictionary, role: String) -> void:
	var world: Node3D = screen.world
	var state: Dictionary = screen.sim.snapshot()
	world.present(state)
	for problem: String in SpotChecks.shapes(world, stage) + SpotChecks.beacon_rings(world, stage) + SpotChecks.held(world, stage, state): _check(false, "%s/%s: %s" % [stage.id, role, problem])
	if role == "a": _check(state.hold_pads.values().has(true) and world.pad_pieces.values().any(func(piece: RefCounted) -> bool: return piece.held()), "%s: the first turn ends on a pad that counts, and it shows held" % stage.id)
