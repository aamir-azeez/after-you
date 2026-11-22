extends "res://tests/test_level_view.gd"
## The level view of every chapter on the water outside the Tide's and The
## Falls' worlds (Fog Marsh); see test_level_view.gd.
const OWN_SUITES := ["res://presentation/tide_world.gd", "res://presentation/the_falls_world.gd"]

func _runs(key: String) -> bool:
	return FoldPresent._on_water(key) and Registry.world_script(key).resource_path not in OWN_SUITES

func _runs_shared() -> bool:
	return false

func _least() -> Dictionary:
	return {"spots": 10, "bubbles": 2, "cut": 0, "boats": 1, "stones": 1, "cover": 1000, "wall_spots": 1000, "walls": 0, "feet": 1, "sized": 10000, "water_edges": 15000}
