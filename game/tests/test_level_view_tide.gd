extends "res://tests/test_level_view.gd"
## The level view of every chapter in the Tide's world (Turn of the Tide's
## versions); see test_level_view.gd.
const TIDE_WORLD := "res://presentation/tide_world.gd"

func _runs(key: String) -> bool:
	return Registry.world_script(key).resource_path == TIDE_WORLD

func _runs_shared() -> bool:
	return false

func _least() -> Dictionary:
	return {"spots": 60, "bubbles": 150, "cut": 1, "boats": 5, "stones": 0, "cover": 3000, "wall_spots": 1000, "walls": 10}
