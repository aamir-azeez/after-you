extends "res://tests/test_online_random.gd"
## Three more fixed seeds for the random Play with a friend walks.

func seeds() -> Array:
	return [41, 59, 73]

func suite_name() -> String:
	return "Online random walks (more)"
