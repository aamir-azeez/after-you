extends "res://tests/test_fold_present.gd"
## The folded chapters in Tide's world; see test_fold_present.gd.

func _runs(key: String) -> bool:
	return _tide(key)
