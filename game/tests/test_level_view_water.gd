extends "res://tests/test_level_view.gd"
## The level view of every chapter on the water outside the Tide's world (The
## Falls, Fog Marsh); see test_level_view.gd.
const TIDE_WORLD := "res://presentation/tide_world.gd"

func _runs(key: String) -> bool:
	return FoldPresent._on_water(key) and Registry.world_script(key).resource_path != TIDE_WORLD

func _runs_shared() -> bool:
	return false

func _least() -> Dictionary:
	return {"spots": 20, "bubbles": 4, "cut": 0, "boats": 0, "stones": 1, "cover": 1000, "wall_spots": 1000, "walls": 0}
