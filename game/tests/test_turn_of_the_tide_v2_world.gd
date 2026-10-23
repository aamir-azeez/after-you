extends "res://tests/chapter_world_suite.gd"
## turn-of-the-tide@2 played through its solo scene and world; see chapter_world_suite.gd.
const Witness = preload("res://tests/turn_of_the_tide_v2_witness.gd")
const SpotChecks = preload("res://tests/stand_spot_checks.gd")

## Every pressure pad wears a stand spot drawn exactly at its radius_cm, the
## turn's beacon rings breathe inside them, and after the first turn's real
## inputs the pad that counts shows held and no other does.
func _turn_played(screen: Node, stage: Dictionary, role: String) -> void:
	var world: Node3D = screen.world
	var state: Dictionary = screen.sim.snapshot()
	world.present(state)
	for problem: String in SpotChecks.shapes(world, stage) + SpotChecks.beacon_rings(world, stage) + SpotChecks.held(world, stage, state): _check(false, "%s/%s: %s" % [stage.id, role, problem])
	if role == "a": _check(state.hold_pads.values().has(true) and world._stand_spots.values().any(func(spot: Node3D) -> bool: return spot.held), "%s: the first turn ends on a pad that counts, and its spot shows held" % stage.id)
