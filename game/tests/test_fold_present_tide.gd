extends "res://tests/test_fold_present.gd"
## The folded chapters on the water (Tide, The Falls, Fog Marsh); see test_fold_present.gd.

func _runs(key: String) -> bool:
	return _on_water(key)
