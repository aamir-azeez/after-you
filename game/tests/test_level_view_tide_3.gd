extends "res://tests/test_level_view_tide.gd"
## The level view of Turn of the Tide @3; see test_level_view_tide.gd.

func _runs(key: String) -> bool:
	return Registry.world_script(key).resource_path == TIDE_WORLD and key in LATER

func _answers(prefix: String) -> bool:
	return prefix in LATER_KNOWN

func _least() -> Dictionary:
	var least: Dictionary = super()
	least.merge({"spots": 20, "bubbles": 55, "water_edges": 17000}, true)
	return least
