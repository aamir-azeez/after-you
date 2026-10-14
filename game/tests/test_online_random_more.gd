extends "res://tests/test_online_random.gd"
## Two more fixed seeds for the random Play with a friend walks.

func seeds() -> Array:
	return [37, 41]

func suite_name() -> String:
	return "Online random walks (more)"
