extends "res://tests/test_staged_build.gd"
## The staged builds of every chapter in the Tide's world (Turn of the Tide's
## versions); see test_staged_build.gd.

func _suite() -> String:
	return "staged_build_tide"

func _runs(key: String) -> bool:
	return _tide(key)

func _runs_shared() -> bool:
	return false
