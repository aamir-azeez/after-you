extends "res://tests/test_level_view.gd"
## The level view of every chapter in The Falls' world; see test_level_view.gd.
const FALLS_WORLD := "res://presentation/the_falls_world.gd"

func _runs(key: String) -> bool:
	return Registry.world_script(key).resource_path == FALLS_WORLD

func _runs_shared() -> bool:
	return false

func _least() -> Dictionary:
	return {"spots": 10, "bubbles": 2, "cut": 0, "boats": 1, "stones": 1, "cover": 1000, "wall_spots": 1000, "walls": 0, "rolls": 1, "sized": 10000, "water_edges": 50000}
