extends "res://tests/test_staged_build.gd"
## The staged builds of the chapters on the water other than the Tide (The
## Falls, Fog Marsh); see test_staged_build.gd.

func _suite() -> String:
	return "staged_build_water"

func _runs(key: String) -> bool:
	return FoldPresent._on_water(key) and not _tide(key)

func _runs_shared() -> bool:
	return false
